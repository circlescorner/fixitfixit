# Security Model

**Document Status**: Living document — this is the most critical doc in the system
**Threat model**: Single-user system. Primary threat is accidental self-lockout.
Secondary threat is unauthorized access from the internet.

---

## Table of Contents

1. [Authentication Layers](#authentication-layers)
2. [What's Wrong With TOTP-Only](#whats-wrong-with-totp-only)
3. [Target Authentication Stack](#target-authentication-stack)
4. [Lockout Prevention (Breakglass)](#lockout-prevention-breakglass)
5. [Secrets Management](#secrets-management)
6. [VPN Design](#vpn-design)
7. [VPN-Only Toggle](#vpn-only-toggle)
8. [Firewall Policy](#firewall-policy)
9. [SSH Hardening](#ssh-hardening)
10. [Dashboard Security](#dashboard-security)
11. [Secrets You Will Have](#secrets-you-will-have)

---

## Authentication Layers

The system has multiple access paths, each with its own auth:

| Access Path          | Current Auth          | Target Auth                        |
|----------------------|-----------------------|------------------------------------|
| Web dashboard        | Password + TOTP       | Password + WebAuthn/FIDO2          |
| SSH to hub           | SSH key               | SSH key (no change needed)         |
| SSH to workers       | SSH key               | SSH key (no change needed)         |
| WireGuard VPN        | (not implemented)     | WireGuard key pair                 |
| DigitalOcean console | DO account login      | DO account login (out of scope)    |

---

## What's Wrong With TOTP-Only

You correctly identified the problem. Here's the technical explanation:

**How TOTP works**:
1. During enrollment, Authelia generates a secret seed (a base32 string)
2. This seed is encoded into a QR code and shown to you
3. Your authenticator app (Google Authenticator, Authy) stores the seed
4. Every 30 seconds, both Authelia and your app compute:
   `HMAC-SHA1(seed, floor(current_time / 30))`
5. The 6-digit code is the output of that computation

**The problem**: The seed is a **shared secret**. It exists in two places:
your authenticator app and Authelia's database. If anyone gets that seed
(screenshot of QR code, backup of Authelia's SQLite, malware on phone),
they can generate valid codes from anywhere on earth. TOTP proves you
**know the seed**, not that you **physically possess** a specific device.

**What TOTP is good for**: It's better than password-only. It's a reasonable
second factor for low-stakes services. It stops credential stuffing attacks.

**What TOTP is not**: It's not hardware-bound. It's not phishing-resistant.
It's not a strong guarantee of physical possession.

---

## Target Authentication Stack

### Primary: Password + WebAuthn/FIDO2

**WebAuthn** (the web standard) / **FIDO2** (the protocol) works like this:
1. During enrollment, your device generates a **public/private key pair**
2. The **private key never leaves the device** — stored in secure hardware
   (YubiKey's secure element, phone's TEE, laptop's TPM)
3. The public key is stored by Authelia
4. At login: Authelia sends a random challenge → your device signs it with
   the private key → Authelia verifies with the public key
5. This is cryptographic proof that **you physically have the enrolled device**

**Why this is better**:
- No shared secret to steal
- Private key is in tamper-resistant hardware
- Phishing-resistant (the browser binds the credential to the domain —
  a fake site can't request your credential)
- Works with: YubiKeys, laptop fingerprint readers, phone biometrics,
  security keys

**What you need to buy/have**:
- A **YubiKey** ($25-50) is the gold standard — physical USB key
- OR your laptop's built-in fingerprint/Windows Hello/Touch ID
- OR your phone as an authenticator (passkey via Bluetooth proximity)

**Authelia supports WebAuthn natively**. The change is configuration, not
a component swap. In `authelia/configuration.yml`:

```yaml
webauthn:
  disable: false
  display_name: CirclesCorner
  attestation_conveyance_preference: indirect
  user_verification: preferred
  timeout: 60s
```

### Fallback: TOTP as Emergency Backup

Keep TOTP enrolled but set it as secondary. If your YubiKey is lost/broken,
TOTP is your backup. This is standard practice. The WebAuthn enrollment
should happen **first**, TOTP second.

### Optional Extra Layer: Client Certificates (Mutual TLS)

For maximum security, Caddy can require a **client certificate** in addition
to Authelia login. This means your browser must present a certificate signed
by your own CA to even reach the login page.

**How it works**:
1. You create a self-signed Certificate Authority (CA)
2. You issue a client certificate from that CA
3. You install the cert in your browser
4. Caddy is configured to require client certs signed by your CA
5. Without the cert, the TLS handshake fails — the site doesn't even load

**Pros**: Even if someone knows your password and has a TOTP code, they
can't reach the login page without the client cert installed in their browser.

**Cons**: You have to install the cert on every device you want to use.
If you lose the CA key, you have to regenerate everything. Can be annoying
to manage across devices.

**Recommendation**: Start with WebAuthn. Add client certs later if you
want the extra layer. Don't do it in phase 1.

---

## Lockout Prevention (Breakglass)

This is the section that exists because you keep locking yourself out.

### Principle: SSH Is the Breakglass

SSH to the hub using your SSH key must **always work**, independent of:
- Authelia being up or down
- Caddy being up or down
- Docker being up or down
- WireGuard being up or down
- The web dashboard being up or down

SSH key authentication goes directly to the OS, not through any of the web
stack. As long as:
1. The droplet is running
2. Port 22 is open (or WireGuard is up and 22 is open on the WG interface)
3. Your SSH private key exists on your local machine

...you can get in.

### Lockout Recovery Procedures

**Scenario 1: Authelia misconfiguration (can't log into web)**
```
ssh root@<hub-ip>
# Check Authelia logs
docker logs sandbox-authelia-1
# Fix the config
nano /opt/sandbox/authelia/configuration.yml
# Restart
cd /opt/sandbox && docker compose restart authelia
```

**Scenario 2: Caddy misconfiguration (HTTPS broken)**
```
ssh root@<hub-ip>
nano /opt/sandbox/caddy/Caddyfile
cd /opt/sandbox && docker compose restart caddy
# If totally broken:
cd /opt/sandbox && docker compose down && docker compose up -d
```

**Scenario 3: Locked out of SSH (key lost/changed)**
```
# Use DigitalOcean web console (Recovery Console)
# Browser → cloud.digitalocean.com → Droplets → sandbox-hub → Console
# This gives you root access without SSH
# From there, add your new SSH key to /root/.ssh/authorized_keys
```

**Scenario 4: Firewall blocks everything**
```
# DigitalOcean web console again
# Or: destroy and recreate via terraform apply
# Your config is in git, so you lose nothing
```

**Scenario 5: Everything is broken, nuke and rebuild**
```
# From your local machine:
cd terraform
terraform destroy  # tears down everything
terraform apply    # rebuilds from code
./scripts/set-password.sh 'YourPassword'
# SSH in, update users.yml, restart authelia
# You're back up with a fresh hub
```

### Breakglass Checklist (Things That Must Always Be True)

- [ ] SSH key pair exists on at least 2 devices (laptop + backup)
- [ ] SSH key is enrolled in DigitalOcean account
- [ ] Port 22 or WireGuard port is open in DO firewall
- [ ] DigitalOcean account has recovery email set
- [ ] DigitalOcean account has its own 2FA (for web console access)
- [ ] Terraform state is accessible (local + backup)
- [ ] This git repo is pushed to GitHub as backup

---

## Secrets Management

### What Is a Secret?

A secret is any value that, if exposed, would let someone:
- Access your infrastructure (DO token, SSH private keys)
- Impersonate you (Authelia JWT secret, session keys)
- Decrypt your data (encryption keys)

### Secrets You Will Have

| Secret                  | What It Is                            | Where It Lives Now       |
|-------------------------|---------------------------------------|--------------------------|
| `do_token`              | DigitalOcean API token                | terraform.tfvars (local) |
| `authelia_jwt_secret`   | Signs Authelia session tokens         | terraform.tfvars (local) |
| SSH private key         | Your SSH identity                     | ~/.ssh/id_ed25519        |
| Authelia password hash  | Your login password (hashed)          | users.yml on hub         |
| TOTP seed               | Shared secret for TOTP codes          | Authelia DB on hub       |
| WireGuard private key   | Hub's WG identity                     | wg0.conf on hub          |
| WireGuard client key    | Your device's WG identity             | peer config on device    |
| TLS certificates        | Auto-managed by Caddy                 | caddy_data volume        |

### Best Practices (Explained Simply)

**Rule 1: Secrets never go in git.**
The `.gitignore` already excludes `terraform.tfvars`, `.env`, `*.key`, and
`*.pem`. This is correct. Never commit these files.

**Rule 2: Secrets on the hub are protected by access control.**
If someone can SSH to the hub, they can read all secrets on it. The defense
is: only you have the SSH key, and the firewall limits SSH access.

**Rule 3: Secrets at rest should be encrypted when practical.**
For a single-user system, full-disk encryption is overkill (DO doesn't
support it easily). Instead, individual sensitive files can be encrypted
with `age` (a simple encryption tool) and decrypted at startup.

**Rule 4: Rotate secrets on a schedule.**
If you suspect any secret is compromised, rotate it. Every 90 days is a
reasonable rotation schedule for API tokens. Authelia session secrets can
be rotated by restarting Authelia (all sessions invalidated).

**Rule 5: Use different secrets for different purposes.**
The DO token, Authelia JWT secret, and WireGuard keys should all be
independently generated. Never reuse a secret.

### VPN Tunnel for Secrets (Your Question Answered)

You asked: "I think that probably means I will need to connect to something
via a separate vpn tunnel for secrets?"

**The answer is simpler than you think.** You don't need a separate VPN
tunnel just for secrets. Here's why:

- **terraform.tfvars** stays on your local machine. It never traverses
  any network. Terraform reads it locally and uses it to talk to the
  DigitalOcean API over HTTPS.

- **Secrets on the hub** (Authelia config, WG keys) are files on disk.
  You access them via SSH, which is already encrypted end-to-end.

- **When you want extra safety**, you can toggle to VPN-only mode. Then
  even SSH goes through the WireGuard tunnel, adding a second layer of
  encryption and hiding the hub's SSH port from the internet.

The WireGuard VPN you're adding serves double duty: it's both your
private access channel and your "secrets tunnel." No need for a separate
one.

### Future Option: HashiCorp Vault / SOPS / age

For a single-user system, file-based secrets are fine. If you later want:
- **Automated secret rotation**: Consider Vault (heavy, probably overkill)
- **Encrypted secrets in git**: Use `age` or `sops` to encrypt secret
  files before committing, decrypt them during deployment
- **Secret sharing across machines**: WireGuard tunnel + SSH is sufficient

---

## VPN Design

### WireGuard Configuration

**Server (hub) — `/opt/sandbox/wireguard/wg0.conf`**:
```ini
[Interface]
Address = 10.200.0.1/24
ListenPort = 51820
PrivateKey = <hub-private-key>
# PostUp/PostDown rules for routing

[Peer]
# Your laptop/device
PublicKey = <your-public-key>
AllowedIPs = 10.200.0.2/32
```

**Client (your device) — downloadable from dashboard**:
```ini
[Interface]
Address = 10.200.0.2/24
PrivateKey = <your-private-key>
DNS = 1.1.1.1

[Peer]
PublicKey = <hub-public-key>
Endpoint = <hub-public-ip>:51820
AllowedIPs = 10.200.0.0/24, 10.100.0.0/16, 172.30.0.0/24
PersistentKeepalive = 25
```

**Why these AllowedIPs on the client**:
- `10.200.0.0/24` — route WG subnet through tunnel
- `10.100.0.0/16` — route VPC traffic through tunnel (reach workers)
- `172.30.0.0/24` — route Docker sandbox traffic through tunnel (reach box1-4)

This is a **split tunnel** — only traffic to your infrastructure goes
through WG. Regular internet browsing goes direct.

### Key Generation

WireGuard keys are generated with:
```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

The dashboard should have a "Generate WireGuard Config" button that:
1. Generates a key pair
2. Adds the peer to the server config
3. Reloads WireGuard (`wg syncconf wg0 /etc/wireguard/wg0.conf`)
4. Offers the client config as a download (or QR code for phone)

---

## VPN-Only Toggle

This is the "kill switch" for public access.

**Public mode (default)**:
- Ports 80, 443 open to internet → web dashboard accessible
- Port 51820 open to internet → WireGuard accessible
- Port 22 open to internet → SSH accessible

**VPN-only mode**:
- Ports 80, 443 **blocked** from internet
- Port 51820 open to internet → WireGuard still accessible
- Port 22 open **only from VPN** (10.200.0.0/24) and VPC (10.100.0.0/16)
- Web dashboard accessible only through WireGuard tunnel

**Implementation**: UFW rules toggled by the dashboard:
```bash
# Switch to VPN-only
ufw delete allow 80/tcp
ufw delete allow 443/tcp
ufw delete allow 22/tcp
ufw allow from 10.200.0.0/24 to any port 22
ufw allow from 10.200.0.0/24 to any port 80
ufw allow from 10.200.0.0/24 to any port 443

# Switch to public
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
```

**CRITICAL SAFETY**: The toggle must **never** block port 51820. If WireGuard
is blocked while in VPN-only mode, you're locked out of everything.

**Dashboard UI**: A toggle switch labeled "Public Access" / "VPN Only" with
a confirmation dialog: "This will block web access from the internet. You
must have WireGuard connected to continue. Are you connected now?"

---

## Firewall Policy

### Current (V1)

```
INBOUND:
  22/tcp    from 0.0.0.0/0      # SSH from anywhere
  80/tcp    from 0.0.0.0/0      # HTTP from anywhere
  443/tcp   from 0.0.0.0/0      # HTTPS from anywhere
  1-65535   from 10.100.0.0/16  # All from VPC

OUTBOUND:
  all       to 0.0.0.0/0        # Everything out
```

### Target (V2) — Public Mode

```
INBOUND:
  22/tcp    from 0.0.0.0/0      # SSH (consider restricting later)
  80/tcp    from 0.0.0.0/0      # HTTP redirect
  443/tcp   from 0.0.0.0/0      # HTTPS
  51820/udp from 0.0.0.0/0      # WireGuard
  1-65535   from 10.100.0.0/16  # VPC
  1-65535   from 10.200.0.0/24  # WireGuard peers

OUTBOUND:
  all       to 0.0.0.0/0
```

### Target (V2) — VPN-Only Mode

```
INBOUND:
  51820/udp from 0.0.0.0/0      # WireGuard (MUST remain open)
  1-65535   from 10.100.0.0/16  # VPC
  1-65535   from 10.200.0.0/24  # WireGuard peers

OUTBOUND:
  all       to 0.0.0.0/0
```

---

## SSH Hardening

Current: SSH is open to the world on port 22 with key auth only (good).

Recommended additions:
1. **Disable password auth** (should already be default on DO):
   `PasswordAuthentication no` in `/etc/ssh/sshd_config`
2. **Disable root login via password** (key only):
   `PermitRootLogin prohibit-password`
3. **Consider changing SSH port** (minor obscurity, reduces log noise):
   Not critical. Skip if it adds friction.
4. **fail2ban**: Already rate-limited by Authelia for web. Consider fail2ban
   for SSH brute force attempts.
5. **In VPN-only mode**: SSH only from WG subnet. Maximum restriction.

---

## Dashboard Security

The dashboard has access to:
- **Docker socket** (read-only mount) — can list/start/stop containers
- **DigitalOcean API token** — can create/destroy droplets
- **File system** — can read/write compose files

This is significant power. It's protected by Authelia forward_auth, meaning
every request to the dashboard has already been authenticated.

**Additional protections to consider**:
- Rate limiting on destructive actions (droplet create/destroy)
- Confirmation dialogs for destructive actions in the UI
- Audit log of all API calls (who did what when)
- Docker socket could be further restricted with a socket proxy that
  limits which API calls are allowed

---

## Secrets You Will Have (Master Reference)

After V2 deployment, you'll manage these secrets:

| # | Secret                    | Generated By        | Stored Where           | Rotation   |
|---|---------------------------|---------------------|------------------------|------------|
| 1 | DO API token              | DigitalOcean panel  | terraform.tfvars       | 90 days    |
| 2 | Authelia JWT secret       | `openssl rand -hex 32` | terraform.tfvars   | On rebuild |
| 3 | SSH private key           | `ssh-keygen`        | ~/.ssh/id_ed25519      | Yearly     |
| 4 | SSH public key            | `ssh-keygen`        | DO + hub authorized_keys| With private|
| 5 | Authelia password         | You (memorized)     | Hash in users.yml      | As desired |
| 6 | WebAuthn credential       | Your device         | Authelia DB            | Per device |
| 7 | TOTP seed (backup)        | Authelia enrollment | Authelia DB + your app | Per enroll |
| 8 | WireGuard hub private key | `wg genkey`         | /opt/sandbox/wireguard/| On rebuild |
| 9 | WireGuard hub public key  | `wg pubkey`         | Client configs         | With private|
|10 | WireGuard client priv key | `wg genkey`         | Your device            | Yearly     |
|11 | WireGuard client pub key  | `wg pubkey`         | Hub wg0.conf           | With private|
|12 | Caddy TLS certs           | Let's Encrypt (auto)| caddy_data volume      | Auto 90d   |

**Backup strategy**: Items 1-4 and 10-11 should be backed up on a separate
device (USB drive in a safe place, encrypted). If you lose these, you can
still access via DO web console and regenerate, but it's painful.
