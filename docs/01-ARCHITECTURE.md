# Architecture

**Document Status**: Living document — versioned in git
**Last significant context**: V1 codebase exists. User answers revealed
iPhone-primary, no-local-workstation constraint. V2 redesigned accordingly.
See DEC-012 through DEC-024 in DECISIONS-LOG.md.

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

## Planned Architecture (V2) — Mobile-First Redesign

**Key constraint**: User operates from an iPhone on corporate WiFi.
No local workstation. No VPN client for daily use. Everything must
work through standard HTTPS in Safari. See DEC-012 for full context.

### Network Topology (Target)

```
┌────────────────────────────── Internet ────────────────────────────────┐
│                                                                        │
│   iPhone Safari ──── HTTPS :443 ──────┐                                │
│   (any browser)                        │                                │
│                                        │                                │
│              ┌─────────────────────────▼────────────────────────────┐   │
│              │  DigitalOcean VPC: 10.100.0.0/16                    │   │
│              │                                                      │   │
│              │  ┌─── Hub Droplet (sandbox-hub) ─────────────────┐  │   │
│              │  │  Region: atl1 (fallback: nyc1)                │  │   │
│              │  │  Reserved IP: attached (stable DNS)            │  │   │
│              │  │                                                │  │   │
│              │  │  Caddy (:80/:443)                              │  │   │
│              │  │    │ auto-HTTPS, Let's Encrypt                 │  │   │
│              │  │    ▼                                           │  │   │
│              │  │  Authelia (:9091)                              │  │   │
│              │  │    │ password + WebAuthn (iPhone Face ID)      │  │   │
│              │  │    │ TOTP as emergency backup                  │  │   │
│              │  │    ▼                                           │  │   │
│              │  │  Dashboard (:8000)                             │  │   │
│              │  │    ├── Docker socket                           │  │   │
│              │  │    ├── DigitalOcean API (server-side)          │  │   │
│              │  │    ├── Config git repo (local)                 │  │   │
│              │  │    ├── Budget controller                       │  │   │
│              │  │    ├── Changelog database                      │  │   │
│              │  │    └── Security mode controller                │  │   │
│              │  │                                                │  │   │
│              │  │  sandbox_net: 172.30.0.0/24                    │  │   │
│              │  │    ├── box1–box4 (swappable images)            │  │   │
│              │  │    └── project volumes (persistent)            │  │   │
│              │  │                                                │  │   │
│              │  └────────────────────────────────────────────────┘  │   │
│              │                                                      │   │
│              │  ┌─── Worker Droplet (on-demand) ────────────────┐  │   │
│              │  │  Spawned/destroyed by dashboard                │  │   │
│              │  │  Snapshot before destroy (preserve state)      │  │   │
│              │  │  Auto-hibernate on inactivity                  │  │   │
│              │  └────────────────────────────────────────────────┘  │   │
│              │                                                      │   │
│              └──────────────────────────────────────────────────────┘   │
│                                                                        │
│   Emergency access: DigitalOcean Web Console (browser-based terminal)  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Bootstrap Flow (No Local Tools Required)

The system deploys from the DigitalOcean web panel — no Terraform, no SSH,
no CLI tools. Works from iPhone Safari.

```
1. DO Panel: Create VPC "sandbox-vpc" (10.100.0.0/16) in atl1
2. DO Panel: Create droplet in that VPC with cloud-init user data
3. DO Panel: Assign Reserved IP to the droplet
4. DO Panel: Verify DNS A record (circlescorner.xyz → Reserved IP)
5. Wait ~3-5 minutes for cloud-init to complete
6. Safari: Visit https://circlescorner.xyz
7. Setup wizard: Enter DO API token, set password, enroll Face ID
8. Dashboard is live
```

The cloud-init script in User Data does all the heavy lifting:
- Installs Docker, git, packages
- Pulls this repo from GitHub
- Builds and starts all containers (Caddy, Authelia, Dashboard)
- Sets up Docker networks
- Self-configures DNS via DO API (if needed)

### New Components (V2)

#### WebAuthn/FIDO2 via iPhone Face ID
- **Purpose**: Hardware-bound second factor using iPhone's Secure Enclave
- **How it works in Safari**: Password prompt → Face ID prompt → done.
  Looks like a normal website login. No app. No hardware. No code to type.
- **Why this is strong**: Private key in Secure Enclave, cannot be extracted.
  Phishing-resistant (domain-bound). Biometric + device possession.
- **Authelia support**: Native. Configuration change only.
- **Fallback**: TOTP as emergency backup (e.g., if phone is unavailable)
- **Sync**: iCloud Keychain syncs passkeys across Apple devices

#### Setup Wizard (first-boot)
- **Purpose**: Complete system configuration from the browser
- **When it runs**: First visit to https://circlescorner.xyz after deploy
- **Collects**: DO API token, admin email, admin password
- **Generates**: Authelia JWT secret, session secrets
- **Enrolls**: WebAuthn (Face ID) as primary 2FA
- **After completion**: Wizard disables itself, normal dashboard loads

#### Security Modes (replaces VPN-only toggle)
- **Normal**: HTTPS from any IP. Password + Face ID. Daily driver.
- **Restricted**: HTTPS from allowlisted IPs only. "Add my current IP"
  button in dashboard. Good for extra security during sensitive work.
- **Lockdown**: No web access. DO Console only. For when you're done.
- Controlled from dashboard with confirmation dialogs.
- See DEC-023 for full design.

#### Budget Controller
- **Purpose**: Cost visibility and spending limits
- **Features**: Monthly budget, real-time spend, cost estimator, alerts
- **Source**: DigitalOcean billing API
- **Display**: Prominent on dashboard homepage
- See DEC-018 for full design.

#### Smart Hibernation (snapshot-then-destroy)
- **Purpose**: "Fall asleep" workers without losing state or paying idle costs
- **Flow**: Inactivity warning → snapshot → destroy → restore when needed
- **Cost**: Snapshots at $0.06/GB/month (vs $48/month for running 4vCPU/8GB)
- See DEC-017 for full design.

#### Config Versioning (on-hub git)
- **Purpose**: Every config file change committed to local git repo
- **Scope**: `/opt/sandbox/` — compose files, Caddyfile, Authelia config
- **Mechanism**: Dashboard commits before/after every change
- **Push to remote**: Optional GitHub sync

#### WireGuard VPN (OPTIONAL — not required for daily use)
- **Purpose**: Extra security layer for when user has a VPN-capable device
- **Status**: Optional enhancement (Phase 5+), not a core requirement
- **Why optional**: Corporate WiFi blocks/flags non-HTTPS traffic.
  User's daily device is iPhone on corporate networks.
- **When useful**: From personal device at home, when maximum security desired
- WireGuard app is available for iOS if the user wants to use it voluntarily

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
| WireGuard        | 10.200.0.0/24    | Optional VPN tunnel (Phase 5+)     |

### Port Map

| Port       | Protocol | Source       | Destination | Service        |
|------------|----------|--------------|-------------|----------------|
| 22         | TCP      | Internet     | Hub         | SSH (breakglass)|
| 80         | TCP      | Internet*    | Hub → Caddy | HTTP→HTTPS      |
| 443        | TCP      | Internet*    | Hub → Caddy | HTTPS (primary) |
| 1–65535    | TCP/UDP  | VPC          | Hub         | VPC traffic     |

*In "Restricted" security mode, ports 80/443 only accept traffic from
allowlisted IPs. In "Lockdown" mode, only SSH (22) and VPC remain open.

All daily access goes through port 443 (HTTPS) — looks like normal
website traffic from any network, including corporate WiFi.
