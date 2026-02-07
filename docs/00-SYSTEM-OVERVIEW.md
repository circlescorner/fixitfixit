# System Overview: Virtual Dev Desktop

**Document Status**: Living document — versioned in git, updated as system evolves
**Owner**: circlescorner
**Domain**: circlescorner.xyz

---

## What This Is

A personal, on-demand development platform that replaces a local workstation with
cloud-spawned infrastructure. Instead of a physical desktop running dev tools, you
get a single always-on control hub at a public domain, protected by real
multi-factor authentication, that lets you:

- See and manage Docker sandbox containers from a web dashboard
- Spin up and tear down cloud VMs with one click
- Control networking between all your resources
- Roll back any configuration change with git-style versioning
- Toggle between public web access and VPN-only lockdown

Everything lives behind your domain (circlescorner.xyz). No third-party logins,
no vendor lock-in for identity. Your keys, your passwords, your infrastructure.

## Why It Exists

1. **No local hardware dependency** — dev environments spawn into existence when
   you need them and disappear when you don't. You pay for compute only while
   it's running.

2. **Single pane of glass** — one URL shows you the state of all your containers,
   VMs, networks, and projects. No SSH-hopping between machines to figure out
   what's running.

3. **Isolation without friction** — each project gets its own container or VM.
   Breaking one thing doesn't break everything. Rollback is always available.

4. **Self-hosted identity** — you control authentication end-to-end. No Google,
   no GitHub OAuth gates. Hardware key + password on your own domain.

5. **Platform for building platforms** — this isn't just a dev box. It's the
   foundation for deploying personal AI tools, experimental services, and
   anything else that needs compute and a network.

## Who It's For

Currently: one person (you), operating primarily from an iPhone 16 on
corporate WiFi. No dedicated workstation. No VPN client for daily use.
Everything must work from Safari with no plugins, certificates, or special
software. Built as if it could serve others, so the architecture is modular
and documented enough that someone else could deploy their own instance,
or you could extend it to multi-user.

## What It Controls

### Today (V1 — current state of code in this repo)

| Resource         | What                                     | Where                     |
|------------------|------------------------------------------|---------------------------|
| Hub droplet      | Always-on 1vCPU/1GB running Caddy +      | DigitalOcean, sandbox-vpc |
|                  | Authelia + Dashboard                      |                           |
| box1–box4        | Docker containers with fixed IPs          | Hub, 172.30.0.11–14       |
| On-demand VMs    | Spawned/destroyed from dashboard          | DigitalOcean, sandbox-vpc |
| VPC              | Private network 10.100.0.0/16             | DigitalOcean              |
| Firewall         | SSH+HTTP+HTTPS public, all ports in VPC   | DigitalOcean              |
| DNS              | A + wildcard records for the domain       | DigitalOcean (optional)   |

### Tomorrow (V2 — what this documentation is planning toward)

| Resource            | What                                           |
|---------------------|------------------------------------------------|
| WireGuard VPN       | Tunnel for VPN-only mode + secrets access       |
| WebAuthn/FIDO2      | Hardware key authentication (replace TOTP)      |
| Config versioning   | Git-backed rollback for all system configs      |
| Project persistence | Named project volumes with snapshot/restore     |
| Changelog system    | Structured record of every system mutation      |
| VPN toggle          | Public ↔ VPN-only mode switch from dashboard    |

## Core Design Principles

### 1. You must never be locked out
Every authentication and access mechanism must have a documented breakglass
procedure. SSH access to the hub must always work independently of the web
auth layer. If Authelia dies, you can still get in via SSH and fix it.

### 2. Every change is reversible
Configuration changes go through git. Infrastructure changes go through
Terraform. Container changes go through versioned compose files. If something
breaks, you can always see what changed and roll it back.

### 3. The dashboard is the truth
If it's not visible on the dashboard, it doesn't exist to the operator. Every
resource, every network connection, every running process that matters should
be surfaced in the web UI.

### 4. Modular over monolithic
Each component (auth, proxy, dashboard, containers, VPN) runs independently.
You can swap Caddy for nginx, Authelia for something else, DigitalOcean for
AWS. The interfaces between components are documented.

### 5. Simple over clever
If a shell script does the job, use a shell script. If a Docker container
is overkill, use a systemd service. The system should be understandable by
reading the files in this repo, not by understanding a framework.

### 6. Document the why, not just the what
Every architectural decision gets logged with the reasoning. When future-you
(or future-AI) asks "why is it like this?", the answer should be in the repo.

## Project References

These are the initial projects this platform will support:

| Project           | URL                                                  | Purpose                    |
|-------------------|------------------------------------------------------|----------------------------|
| UI-TARS-desktop   | https://github.com/bytedance/UI-TARS-desktop         | AI desktop automation      |
| claude-mem        | https://github.com/thedotmack/claude-mem             | Claude persistent memory   |
| superpowers       | https://github.com/obra/superpowers                  | AI capability extensions   |

Plus your own current stable projects, which need persistent storage with full
rollback.

## Cost Model

### Fixed Monthly Costs

| Component                | Monthly Cost | Notes                           |
|--------------------------|-------------|----------------------------------|
| Hub (s-1vcpu-1gb)        | $6.00       | Always on                        |
| Hub backups              | $1.20       | Automated weekly snapshots        |
| Reserved IP (attached)   | $0.00       | Free when attached to a droplet   |
| **Total fixed**          | **$7.20**   |                                  |

### Variable Costs (workers)

| Worker Size              | Hourly Cost | For 6hrs/day | For 4hrs/week |
|--------------------------|-------------|-------------|---------------|
| s-1vcpu-1gb              | $0.009      | $1.17/mo    | $0.16/mo      |
| s-2vcpu-4gb (recommended)| $0.036      | $4.64/mo    | $0.62/mo      |
| s-4vcpu-8gb (heavy)      | $0.071      | $9.16/mo    | $1.22/mo      |

### Budget Target: $15/month

Using s-2vcpu-4gb workers (recommended for most dev work):
- Hub: $7.20/mo (fixed)
- 1 worker @ 6hr/weekday: $4.64/mo
- Occasional burst (4 workers, 4hr/week): $2.48/mo
- Snapshots (~2 hibernated workers): $3.00/mo
- **Total: ~$14.32/mo** (within budget)

Using s-4vcpu-8gb workers (heavy workloads):
- Hub: $7.20/mo
- 1 worker @ 6hr/weekday: $9.16/mo
- Occasional burst: $4.88/mo
- **Total: ~$21.24/mo** (over budget, use sparingly)

### Setup Cost
Initial deployment: $0 (first droplet billed hourly from creation).
The $25 setup budget provides headroom for trial-and-error rebuilds.

## File Map

```
fixitfixit/
├── docs/                        # <-- You are here. System definition documents.
│   ├── SYSTEM-OVERVIEW.md       # This file
│   ├── ARCHITECTURE.md          # Technical architecture
│   ├── SECURITY-MODEL.md        # Authentication, secrets, access control
│   ├── EVOLUTION-PLAN.md        # Phased build plan
│   ├── CHANGE-MANAGEMENT.md     # Rollback, changelog, versioning
│   ├── OPERATIONS-RUNBOOK.md    # Day-to-day operations and recovery
│   ├── AI-COLLABORATION-GUIDE.md# How to work with AI on this system
│   ├── DECISIONS-LOG.md         # Architecture decision records
│   └── OPEN-QUESTIONS.md        # Unresolved questions and choices
├── terraform/                   # Infrastructure-as-code
├── infra/                       # Cloud-init bootstrapping
├── dashboard/                   # Web UI + API
└── scripts/                     # Helper scripts
```
