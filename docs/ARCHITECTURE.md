# Architecture

**Document Status**: Living document — versioned in git
**Last significant context**: V1 codebase exists, V2 is being planned

---

## Current Architecture (V1)

### Network Topology

```
┌─────────────────────────────── Internet ───────────────────────────────┐
│                                                                        │
│   User's Browser ──── HTTPS :443 ───┐                                  │
│                                      │                                  │
│              ┌───────────────────────▼──────────────────────────────┐   │
│              │  DigitalOcean VPC: 10.100.0.0/16                    │   │
│              │                                                      │   │
│              │  ┌─── Hub Droplet (sandbox-hub) ─────────────────┐  │   │
│              │  │                                                │  │   │
│              │  │  Caddy (:80/:443)                              │  │   │
│              │  │    │                                           │  │   │
│              │  │    ▼                                           │  │   │
│              │  │  Authelia (:9091) ── password + TOTP           │  │   │
│              │  │    │                                           │  │   │
│              │  │    ▼                                           │  │   │
│              │  │  Dashboard (:8000) ── Flask app                │  │   │
│              │  │    │          │                                │  │   │
│              │  │    │          ├── Docker socket (read-only)    │  │   │
│              │  │    │          └── DigitalOcean API             │  │   │
│              │  │    ▼                                           │  │   │
│              │  │  sandbox_net: 172.30.0.0/24                    │  │   │
│              │  │    ├── box1  172.30.0.11                       │  │   │
│              │  │    ├── box2  172.30.0.12                       │  │   │
│              │  │    ├── box3  172.30.0.13                       │  │   │
│              │  │    └── box4  172.30.0.14                       │  │   │
│              │  │                                                │  │   │
│              │  └────────────────────────────────────────────────┘  │   │
│              │                                                      │   │
│              │  ┌─── Worker Droplet (on-demand) ────────────────┐  │   │
│              │  │  10.100.x.x (auto-assigned by VPC)            │  │   │
│              │  │  Docker, UFW, SSH                               │  │   │
│              │  └────────────────────────────────────────────────┘  │   │
│              │                                                      │   │
│              └──────────────────────────────────────────────────────┘   │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Component Breakdown

#### Caddy (Reverse Proxy)
- **Image**: `ghcr.io/caddyserver/caddy:2`
- **Role**: TLS termination, automatic HTTPS via Let's Encrypt, forward auth
  to Authelia, reverse proxy to dashboard
- **Config location (on hub)**: `/opt/sandbox/caddy/Caddyfile`
- **Source of truth (in repo)**: Embedded in `infra/cloud-init.yml`
- **Networks**: `sandbox_frontend`
- **Ports exposed**: 80, 443

#### Authelia (Authentication)
- **Image**: `authelia/authelia:latest`
- **Role**: Username/password + TOTP verification. Every request to the
  dashboard goes through forward_auth.
- **Config location (on hub)**: `/opt/sandbox/authelia/configuration.yml`
- **User database**: `/opt/sandbox/authelia/users.yml` (file-based, argon2id hashes)
- **Session storage**: SQLite at `/opt/sandbox/authelia/db.sqlite3`
- **Networks**: `sandbox_frontend`
- **Current auth factors**: Password (argon2id) + TOTP (30s period)

#### Dashboard (Flask App)
- **Build**: Custom Dockerfile in `dashboard/`
- **Role**: Web UI + REST API for managing containers, networks, droplets
- **Config location (on hub)**: `/opt/sandbox/dashboard/`
- **Environment**: `DOMAIN`, `DO_TOKEN`, `VPC_SUBNET`
- **Access**: Docker socket (read-only mount), DigitalOcean API via token
- **Networks**: `sandbox_frontend` + `sandbox_net`
- **Port**: 8000 (internal, proxied through Caddy)

#### Sandbox Containers (box1–box4)
- **Default image**: `ubuntu:24.04`
- **Config**: Separate compose file at `/opt/sandbox/sandbox/docker-compose.yml`
- **Network**: `sandbox_net` (172.30.0.0/24), fixed IPs .11–.14
- **Command**: `sleep infinity` (kept alive for interactive use)
- **Swappable**: Image can be changed per slot via dashboard API

#### Worker Droplets (on-demand)
- **Created via**: Dashboard API → DigitalOcean API
- **Bootstrap**: Cloud-init installs Docker, UFW, opens VPC ports
- **Network**: Auto-assigned IP within VPC 10.100.0.0/16
- **Access**: SSH from internet, all ports from VPC
- **Lifecycle**: Created and destroyed from dashboard

### Data Flow

```
Browser request
  → DNS resolves circlescorner.xyz to hub public IP
  → Caddy receives HTTPS request
  → Caddy calls Authelia forward_auth endpoint
    → If unauthenticated: redirect to Authelia login portal
    → If authenticated: Authelia returns 200 with user headers
  → Caddy proxies to Dashboard (:8000)
  → Dashboard serves HTML or processes API call
    → Container ops: Docker SDK via socket
    → Droplet ops: DigitalOcean REST API
  → Response back through Caddy to browser
```

### What's Missing in V1

| Gap                           | Impact                                           |
|-------------------------------|--------------------------------------------------|
| TOTP-only 2FA                 | No hardware-bound factor. TOTP seed is copyable. |
| No VPN                        | Everything is public-facing. No private mode.     |
| No config versioning on hub   | Changes to files on hub aren't tracked.           |
| No rollback mechanism         | Broken config = manual SSH fix or rebuild.        |
| No changelog                  | No record of what changed and why.                |
| No secrets management         | DO token in env vars, JWT secret in plaintext.    |
| No backup/snapshot            | Losing the hub means rebuilding from scratch.     |
| No project persistence        | Container data is ephemeral.                      |
| SSH open to world             | Port 22 accepts connections from any IP.          |

---

## Planned Architecture (V2)

### Network Topology (Target)

```
┌────────────────────────────── Internet ────────────────────────────────┐
│                                                                        │
│   User's Browser ──── HTTPS :443 ─────┐                                │
│   User's Device ───── WireGuard :51820 ┤                                │
│                                        │                                │
│              ┌─────────────────────────▼────────────────────────────┐   │
│              │  DigitalOcean VPC: 10.100.0.0/16                    │   │
│              │                                                      │   │
│              │  ┌─── Hub Droplet ───────────────────────────────┐   │   │
│              │  │                                                │   │   │
│              │  │  WireGuard (:51820/udp) ─ VPN tunnel          │   │   │
│              │  │    │                                           │   │   │
│              │  │  Caddy (:80/:443)                              │   │   │
│              │  │    │                                           │   │   │
│              │  │  Authelia (:9091)                              │   │   │
│              │  │    │ password + WebAuthn/FIDO2                 │   │   │
│              │  │    │ (+ client cert optional)                  │   │   │
│              │  │    ▼                                           │   │   │
│              │  │  Dashboard (:8000)                             │   │   │
│              │  │    ├── Docker socket                           │   │   │
│              │  │    ├── DigitalOcean API                        │   │   │
│              │  │    ├── Config git repo (local)                 │   │   │
│              │  │    └── Changelog database                      │   │   │
│              │  │                                                │   │   │
│              │  │  sandbox_net: 172.30.0.0/24                    │   │   │
│              │  │    ├── box1–box4 (as before)                   │   │   │
│              │  │    └── project volumes (persistent)            │   │   │
│              │  │                                                │   │   │
│              │  │  WireGuard subnet: 10.200.0.0/24              │   │   │
│              │  │    └── hub = 10.200.0.1                        │   │   │
│              │  │    └── your device = 10.200.0.2                │   │   │
│              │  │                                                │   │   │
│              │  └────────────────────────────────────────────────┘   │   │
│              │                                                      │   │
│              └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

### New Components

#### WireGuard VPN
- **Purpose**: Private tunnel to hub. Enables VPN-only mode where public
  HTTP/HTTPS is blocked and all access goes through the tunnel.
- **Port**: 51820/udp (always open in firewall)
- **Subnet**: 10.200.0.0/24 (separate from VPC and Docker)
- **Hub IP**: 10.200.0.1
- **Client IP**: 10.200.0.2 (your device)
- **Config managed by**: Dashboard (generate/rotate keys from UI)
- **Why WireGuard**: Minimal attack surface, fast, one config file, built
  into Linux kernel. No complex PKI.

#### WebAuthn/FIDO2 (replacing TOTP)
- **Purpose**: Hardware-bound second factor. The private key never leaves
  your physical device (YubiKey, phone biometric, laptop fingerprint).
- **Why not TOTP**: TOTP secret is a shared secret — if someone gets the
  QR code or seed, they can generate codes from anywhere. WebAuthn
  private keys are device-bound and use challenge-response. No shared
  secret to steal.
- **Authelia support**: Authelia supports WebAuthn natively. Configuration
  change, not a component replacement.
- **Fallback**: Keep TOTP as emergency backup, but primary auth is WebAuthn.

#### Config Versioning (on-hub git)
- **Purpose**: Every config file change on the hub is committed to a local
  git repository so you can see diffs and revert.
- **Scope**: `/opt/sandbox/` — compose files, Caddyfile, Authelia config,
  dashboard settings.
- **Mechanism**: Dashboard commits to local git before applying changes.
  Git log becomes the changelog.
- **Push to remote**: Optional — sync to private GitHub/Gitea repo.

#### Secrets Management
- See SECURITY-MODEL.md for full design.
- Summary: Secrets stored encrypted on hub, decrypted at runtime.
  No secrets in git. VPN tunnel for any remote secret operations.

### Interface Boundaries

These are the seams where components can be swapped:

```
┌───────────────┐     ┌─────────────────┐
│ Reverse Proxy │◄───►│ Auth Provider   │
│ (Caddy)       │     │ (Authelia)      │
│               │     │                 │
│ Interface:    │     │ Interface:      │
│ forward_auth  │     │ HTTP 9091       │
│ HTTP header   │     │ forward-auth    │
│ passthrough   │     │ endpoint        │
└───────┬───────┘     └─────────────────┘
        │
        ▼
┌───────────────┐     ┌─────────────────┐
│ Dashboard     │◄───►│ Cloud Provider  │
│ (Flask)       │     │ (DigitalOcean)  │
│               │     │                 │
│ Interface:    │     │ Interface:      │
│ REST API      │     │ REST API v2     │
│ /api/*        │     │ Bearer token    │
└───────┬───────┘     └─────────────────┘
        │
        ▼
┌───────────────┐     ┌─────────────────┐
│ Container     │     │ VPN             │
│ Runtime       │     │ (WireGuard)     │
│ (Docker)      │     │                 │
│               │     │ Interface:      │
│ Interface:    │     │ UDP 51820       │
│ Docker socket │     │ wg0 interface   │
│ compose CLI   │     │ peer configs    │
└───────────────┘     └─────────────────┘
```

To swap DigitalOcean for AWS: replace the Cloud Provider module.
To swap Docker for Podman: replace the Container Runtime module.
To swap Caddy for nginx: replace the Reverse Proxy + update forward_auth.
To swap Authelia for Authentik: replace Auth Provider + update forward_auth.

### File Layout on Hub (Target)

```
/opt/sandbox/
├── .git/                          # Local git repo tracking all configs
├── docker-compose.yml             # Core services (Caddy, Authelia, Dashboard)
├── caddy/
│   └── Caddyfile
├── authelia/
│   ├── configuration.yml
│   ├── users.yml
│   └── db.sqlite3
├── dashboard/
│   ├── app.py
│   ├── Dockerfile
│   ├── templates/
│   └── static/
├── sandbox/
│   └── docker-compose.yml         # box1–box4
├── wireguard/
│   ├── wg0.conf                   # Server config
│   └── peers/
│       └── device1.conf           # Client config (downloadable)
├── projects/
│   ├── project-a/                 # Persistent project data
│   └── project-b/
├── backups/
│   └── snapshots/                 # Config snapshots before changes
└── changelog/
    └── entries/                   # Structured change records
```

### Networking Summary

| Network          | Range            | Purpose                            |
|------------------|------------------|------------------------------------|
| VPC              | 10.100.0.0/16    | DigitalOcean private inter-droplet |
| sandbox_net      | 172.30.0.0/24    | Docker bridge for box1–box4        |
| sandbox_frontend | auto-assigned    | Caddy + Authelia + Dashboard       |
| WireGuard        | 10.200.0.0/24    | VPN tunnel (hub ↔ your device)     |

### Port Map

| Port       | Protocol | Source       | Destination | Service     |
|------------|----------|--------------|-------------|-------------|
| 22         | TCP      | Internet*    | Hub         | SSH         |
| 80         | TCP      | Internet*    | Hub → Caddy | HTTP→HTTPS  |
| 443        | TCP      | Internet*    | Hub → Caddy | HTTPS       |
| 51820      | UDP      | Internet     | Hub → WG    | WireGuard   |
| 1–65535    | TCP/UDP  | VPC          | Hub         | VPC traffic |

*In VPN-only mode, ports 80/443 are blocked from internet. Only
accessible through WireGuard tunnel.

Note: Port 51820 (WireGuard) should always be open even in VPN-only mode,
otherwise you can't establish the tunnel to access anything else.
