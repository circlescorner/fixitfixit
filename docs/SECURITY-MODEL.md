# Security Model

**Document Status**: Living document — this is the most critical doc in the system
**Last updated**: 2026-02-06 — revised for mobile-first (DEC-012, DEC-013)
**Threat model**: Single-user system. Primary threat is accidental self-lockout.
Secondary threat is unauthorized access from the internet.
**Access model**: iPhone Safari on corporate WiFi. Normal HTTPS only.

---

## Table of Contents

1. [Authentication Layers](#authentication-layers)
2. [What's Wrong With TOTP-Only](#whats-wrong-with-totp-only)
3. [Target Authentication Stack](#target-authentication-stack)
4. [Lockout Prevention (Breakglass)](#lockout-prevention-breakglass)
5. [Secrets Management](#secrets-management)
6. [Security Modes (Replaces VPN-Only Toggle)](#security-modes)
7. [Firewall Policy](#firewall-policy)
8. [SSH Hardening](#ssh-hardening)
9. [Dashboard Security](#dashboard-security)
10. [Secrets You Will Have](#secrets-you-will-have)

---

## Authentication Layers

The system has multiple access paths, each with its own auth:

| Access Path          | Current Auth          | Target Auth                          |
|----------------------|-----------------------|--------------------------------------|
| Web dashboard        | Password + TOTP       | Password + Face ID (WebAuthn)        |
| DigitalOcean Console | DO account login      | DO account login (breakglass)        |
| SSH to hub           | SSH key               | SSH key (breakglass only, not daily) |
| WireGuard VPN        | (not implemented)     | WireGuard key pair (optional, later) |

**Primary daily access**: iPhone Safari → https://circlescorner.xyz →
Password + Face ID. Looks like a normal website from any network.

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

### Primary: Password + WebAuthn via iPhone Face ID

**WebAuthn** (the web standard) / **FIDO2** (the protocol) works like this:
1. During enrollment, your iPhone generates a **public/private key pair**
2. The **private key never leaves the iPhone** — stored in the Secure Enclave
   (dedicated hardware chip, tamper-resistant)
3. The public key is stored by Authelia
4. At login: Authelia sends a random challenge → Face ID verifies you →
   iPhone signs the challenge with the private key → Authelia verifies
5. This is cryptographic proof that **you physically have your iPhone
   AND you are you** (biometric)

**Why this is better than TOTP**:
- No shared secret to steal
- Private key is in tamper-resistant hardware (Secure Enclave)
- Phishing-resistant (Safari binds the credential to circlescorner.xyz —
  a fake site can't request your credential)
- Biometric verification — someone holding your phone still can't log in
- Works in standard Safari — no app, no extension, nothing to install

**What it looks like in practice**:
1. Open Safari, go to circlescorner.xyz
2. Type your password
3. Face ID prompt appears → look at phone → authenticated
4. Looks like a totally normal website login to anyone watching

**What you need**: Your iPhone 16. That's it. Face ID is the authenticator.

**iCloud Keychain sync**: If you enable it, your passkey syncs across
Apple devices (iPad, Mac). If you get a new iPhone, the passkey transfers
automatically via iCloud Keychain. This is your backup mechanism.

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

Keep TOTP enrolled as secondary. If your iPhone is lost/broken and iCloud
Keychain didn't sync the passkey, TOTP is your backup. Use an authenticator
app (1Password, Authy, or the built-in iOS authenticator).

### What About Logging In From Other Devices?

You said you sometimes use work PCs, library computers, and friends' PCs.

**With WebAuthn cross-device authentication**: Safari and Chrome support
using your phone as a "roaming authenticator." The flow:
1. Open browser on any PC, go to circlescorner.xyz
2. Type password
3. Browser shows "Use your phone" option
4. Scan QR code with iPhone camera
5. Face ID prompt on phone → authenticated on PC
6. No software installed on the PC. Nothing left behind.

This works because WebAuthn supports cross-device authentication via
Bluetooth proximity. The PC's browser talks to your iPhone over BLE.
The private key never leaves your phone.

**Limitation**: The PC must have Bluetooth and the browser must support
FIDO2 cross-device auth. Most modern browsers do. Corporate PCs with
locked-down Bluetooth may not. In that case, fall back to TOTP.

### Client Certificates — NOT recommended for your scenario

Client certs require installing certificates on every device. You can't
install certs on work PCs. Explicitly ruled out per DEC-012.

---

## Lockout Prevention (Breakglass)

This is the section that exists because you keep locking yourself out.

### Principle: DO Console Is the Breakglass

DigitalOcean's web console provides a browser-based terminal that requires
only your DO account login. It works from an iPhone. It doesn't depend on
SSH keys, firewall rules, Caddy, Authelia, Docker, or anything else running
on the hub. As long as:
1. The droplet is running
2. You can log into your DO account

...you can get a root shell via DO Console and fix anything.

This is why saving your DO recovery codes is the #1 priority.

### Lockout Recovery Procedures

All recovery starts with: DO panel → Droplets → sandbox-hub → Console

**Scenario 1: Authelia misconfiguration (can't log into web)**
```
# In DO Console:
docker logs sandbox-authelia-1
nano /opt/sandbox/authelia/configuration.yml
cd /opt/sandbox && docker compose restart authelia
```

**Scenario 2: Caddy misconfiguration (HTTPS broken)**
```
# In DO Console:
nano /opt/sandbox/caddy/Caddyfile
cd /opt/sandbox && docker compose restart caddy
# If totally broken:
cd /opt/sandbox && docker compose down && docker compose up -d
```

**Scenario 3: Firewall blocks everything**
```
# In DO Console:
ufw status
ufw allow 80/tcp
ufw allow 443/tcp
# Or reset entirely:
ufw disable && ufw reset
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
ufw allow from 10.100.0.0/16
ufw --force enable
```

**Scenario 4: Everything is broken, nuke and rebuild**
```
# From DO panel (iPhone browser):
1. Destroy the hub droplet
2. Create new droplet with same cloud-init user data
3. Reassign Reserved IP to new droplet
4. Wait for cloud-init, then visit the domain
5. Complete setup wizard again
# Your code is in GitHub. The Reserved IP survives. DNS doesn't change.
```

**Scenario 5: Lost access to DO account**
```
# Use DO recovery codes (THIS IS WHY YOU MUST SAVE THEM)
# If no recovery codes: contact DO support for account recovery
# This is the last resort. Everything else is recoverable from DO Console.
```

### Breakglass Checklist (Things That Must Always Be True)

- [ ] DO recovery codes saved in at least 2 places
- [ ] DO account email is accessible
- [ ] DO account has 2FA enabled
- [ ] Reserved IP exists and is attached to hub
- [ ] DNS A record points to Reserved IP
- [ ] This git repo is pushed to GitHub as backup
- [ ] iCloud Keychain enabled (for WebAuthn passkey sync/backup)

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

## Security Modes (Replaces VPN-Only Toggle)

The original design had a VPN-only toggle. This has been redesigned because
the user can't use WireGuard as a daily driver (corporate WiFi, iPhone-only).
See DEC-014 and DEC-023.

### Three Security Modes

**Normal Mode** (daily driver):
- Ports 80, 443 open to internet → dashboard accessible from any IP
- Port 22 open to internet → SSH available for emergencies
- Authentication: Password + Face ID (WebAuthn)
- This is how you'll use the system 99% of the time
- Looks like visiting any normal website

**Restricted Mode** (extra security):
- Ports 80, 443 open **only to allowlisted IPs**
- Dashboard has "Add my current IP" button (detects your IP, adds to allowlist)
- SSH open to internet (breakglass)
- Good for: when you want to limit who can even see the login page
- Implementation: UFW rules with specific source IPs

**Lockdown Mode** (maximum security / idle):
- Ports 80, 443 **blocked** from all internet traffic
- Port 22 open to internet (breakglass)
- Only accessible via DO Console
- Good for: when you're done for the day and don't want the system exposed
- Re-enable via DO Console: `ufw allow 80/tcp && ufw allow 443/tcp`

### Implementation

```bash
# Normal mode (default)
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Restricted mode
ufw delete allow 80/tcp
ufw delete allow 443/tcp
ufw allow from <your-ip> to any port 80
ufw allow from <your-ip> to any port 443
# Repeat for each allowlisted IP

# Lockdown mode
ufw delete allow 80/tcp
ufw delete allow 443/tcp
# Remove any per-IP rules too
```

### Safety Measures

- **Switching TO Restricted**: Dashboard auto-adds your current IP first.
  You can't lock yourself out by switching to Restricted while connected.
- **Switching TO Lockdown**: Confirmation dialog:
  "This will disable ALL web access. You can only re-enable via
  DigitalOcean Console. Are you sure?"
- **SSH always open**: Port 22 stays open in all modes as a breakglass.
  (Consider restricting SSH to VPC + allowlisted IPs in Restricted mode.)
- **Mode displayed on dashboard**: Current mode shown prominently so you
  always know what state you're in.

### WireGuard (Optional, Phase 5+)

WireGuard remains in the design as an OPTIONAL enhancement for Phase 5+.
It's not required for daily operation. If you install the WireGuard app
on your iPhone, you could use it as an additional security layer:
- Connect via WireGuard tunnel from iPhone
- Switch to Restricted mode with only WireGuard subnet allowlisted
- Now even the login page is hidden from the internet

But this is optional and not part of the core security model.

---

## Firewall Policy

### Current (V1) — Normal Mode

```
INBOUND:
  22/tcp    from 0.0.0.0/0      # SSH (breakglass)
  80/tcp    from 0.0.0.0/0      # HTTP → redirect to HTTPS
  443/tcp   from 0.0.0.0/0      # HTTPS (primary access)
  1-65535   from 10.100.0.0/16  # All from VPC

OUTBOUND:
  all       to 0.0.0.0/0        # Everything out
```

### Target (V2) — Restricted Mode

```
INBOUND:
  22/tcp    from 0.0.0.0/0      # SSH (breakglass, always open)
  80/tcp    from <allowlist>     # HTTP from allowed IPs only
  443/tcp   from <allowlist>     # HTTPS from allowed IPs only
  1-65535   from 10.100.0.0/16  # VPC

OUTBOUND:
  all       to 0.0.0.0/0
```

### Target (V2) — Lockdown Mode

```
INBOUND:
  22/tcp    from 0.0.0.0/0      # SSH (breakglass, always open)
  1-65535   from 10.100.0.0/16  # VPC

OUTBOUND:
  all       to 0.0.0.0/0
```

Note: SSH remains open in all modes as the ultimate breakglass path.
DO Console also works regardless of firewall rules (it's out-of-band).

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
