# Decisions Log

**Document Status**: Append-only — never delete entries, only add new ones
**Purpose**: Record every architectural and design decision with reasoning,
so future-you (or future-AI) understands why the system is the way it is.

---

## Format

Each decision follows this template:

```
### DEC-NNN: [Short title]
**Date**: YYYY-MM-DD
**Status**: Accepted / Superseded by DEC-XXX / Rejected
**Context**: What situation prompted this decision?
**Decision**: What did we decide?
**Reasoning**: Why this option over alternatives?
**Alternatives considered**: What else was on the table?
**Consequences**: What does this decision imply going forward?
```

---

## Decisions

### DEC-001: Use DigitalOcean as primary cloud provider
**Date**: 2026-02-05
**Status**: Accepted
**Context**: Need a cloud provider for the always-on hub and on-demand workers.
**Decision**: DigitalOcean with VPC networking.
**Reasoning**: Simple API, predictable pricing ($6/mo minimum), good Terraform
provider, VPC for private networking between droplets. User already has a DO
account.
**Alternatives considered**:
- AWS: More services but significantly more complex. Pricing is harder to predict.
- Hetzner: Cheaper but smaller ecosystem. Could be a future alternative.
- Self-hosted: Requires hardware investment and always-on power/internet.
**Consequences**: Cloud-specific code uses DO API. Terraform uses DO provider.
VPC uses DO's network fabric. If migrating, the provider abstraction layer
(Phase 7) will need a new implementation.

---

### DEC-002: Use Caddy as reverse proxy
**Date**: 2026-02-05
**Status**: Accepted
**Context**: Need HTTPS termination with automatic certificate management.
**Decision**: Caddy v2 with automatic Let's Encrypt.
**Reasoning**: Automatic HTTPS with zero configuration. Built-in forward_auth
for Authelia. Simple Caddyfile syntax. Supports wildcard certs with DNS
challenge.
**Alternatives considered**:
- nginx: More configurable but manual cert management (certbot). More complex config.
- Traefik: Good Docker integration but more complex configuration model.
**Consequences**: Caddyfile is the proxy config format. forward_auth syntax is
Caddy-specific. Wildcard certs use Caddy's DNS module for DigitalOcean.

---

### DEC-003: Use Authelia for authentication
**Date**: 2026-02-05
**Status**: Accepted
**Context**: Need a self-hosted authentication gateway with 2FA. No third-party
identity providers (no Google, GitHub, etc.).
**Decision**: Authelia with file-based user backend.
**Reasoning**: Self-contained, supports TOTP and WebAuthn, works with Caddy's
forward_auth, single-binary deployment, SQLite storage. Does not require an
external database or identity provider.
**Alternatives considered**:
- Authentik: More features (full IdP, SAML, LDAP) but heavier. Requires PostgreSQL.
  Overkill for single-user.
- Keycloak: Enterprise-grade, extremely heavy. Requires JVM + PostgreSQL. Wrong scale.
- Basic auth: Too weak. No 2FA support.
- Custom auth: Don't build auth yourself. Use a battle-tested solution.
**Consequences**: Authentication flow is Authelia's. WebAuthn and TOTP support
come from Authelia's feature set. User management is file-based (no database admin).

---

### DEC-004: Use TOTP for initial 2FA, plan migration to WebAuthn
**Date**: 2026-02-05 (initial), 2026-02-06 (migration planned)
**Status**: Accepted (TOTP as temporary, WebAuthn as target)
**Context**: V1 uses TOTP only. User correctly identified that TOTP's shared
secret model is weaker than hardware-bound authentication.
**Decision**: Deploy with TOTP initially (V1). Add WebAuthn in Phase 4.
Keep TOTP as emergency fallback.
**Reasoning**: TOTP works out of the box. WebAuthn requires a physical
authenticator (YubiKey, biometric device) that the user may not have yet.
Starting with TOTP gets the system running. WebAuthn is a config change in
Authelia, not a component replacement.
**Alternatives considered**:
- Client certificates (mutual TLS): Very strong but painful UX (install certs
  on every device). Considered as optional additional layer, not primary.
- SSH key challenge: Possible but non-standard for web auth. WireGuard VPN
  serves this purpose better.
- No 2FA: Unacceptable for an internet-facing system.
**Consequences**: Phase 4 adds WebAuthn. User needs to acquire a WebAuthn
device before Phase 4. TOTP remains as backup method.

---

### DEC-005: Use WireGuard for VPN
**Date**: 2026-02-06
**Status**: Accepted
**Context**: Need VPN access for private-only mode and secure tunnel access.
**Decision**: WireGuard on a separate subnet (10.200.0.0/24).
**Reasoning**: Minimal code (4000 lines of kernel code), fast, one config file,
built into Linux kernel since 5.6. No complex PKI like OpenVPN. No account
required like Tailscale.
**Alternatives considered**:
- Tailscale: Easier setup but requires Tailscale account. Adds vendor dependency.
  Could be considered later as a complementary tool.
- OpenVPN: Legacy, complex, slower, requires certificate management.
- Nebula (Slack's mesh VPN): Interesting for multi-node but adds complexity.
  Could be Phase 8+ consideration for mesh networking.
- SSH tunnels: Workable for single ports but not a real VPN. Can't route
  traffic for the Docker subnet through an SSH tunnel easily.
**Consequences**: Port 51820/udp must always be open (even in VPN-only mode).
WireGuard keys are a new secret to manage. Client app needed on user's device
(available for all platforms). VPN-only toggle modifies UFW rules.

---

### DEC-006: Use file-based configuration instead of database
**Date**: 2026-02-05
**Status**: Accepted
**Context**: System needs to store configs, user data, and session data.
**Decision**: Files (YAML, JSON) and SQLite where needed. No external database.
**Reasoning**: Files are readable, diffable, git-trackable. A $6/month droplet
doesn't have resources for PostgreSQL or MySQL. SQLite handles Authelia's
session needs without a server process. Docker compose files are YAML already.
**Alternatives considered**:
- PostgreSQL: Required by Authentik/Keycloak, but not by Authelia. Adds
  memory/CPU overhead and another thing to manage.
- etcd/Consul: For distributed config. Overkill for single-node.
- Environment variables only: Not flexible enough for complex configs.
**Consequences**: All config is on the filesystem. Git can track it. Backups
are file copies. No database administration needed. Trade-off: no concurrent
write safety (fine for single-user).

---

### DEC-007: Use Terraform for infrastructure management
**Date**: 2026-02-05
**Status**: Accepted
**Context**: Need to create/manage cloud resources reproducibly.
**Decision**: Terraform with DigitalOcean provider.
**Reasoning**: Declarative, state-tracked, plan-before-apply workflow.
Infrastructure as code in the repo. destroy + apply = full rebuild.
**Alternatives considered**:
- Pulumi: Code-based (Python/JS) instead of HCL. More flexible but less
  standardized. Could be future option.
- DO CLI (doctl): Imperative, no state tracking. Can't plan or diff.
- Ansible: Configuration management, not infrastructure provisioning.
  Could complement Terraform for hub configuration (Phase 8+).
**Consequences**: Terraform state file is critical (must be backed up).
Infrastructure changes go through `terraform plan` then `terraform apply`.
Adding new resource types means writing HCL.

---

### DEC-008: Dashboard built with Flask + vanilla JavaScript
**Date**: 2026-02-05
**Status**: Accepted
**Context**: Need a web UI for controlling the system.
**Decision**: Flask backend, vanilla JS frontend. No framework.
**Reasoning**: Flask is minimal and the dashboard API is simple REST.
Vanilla JS avoids build tooling (no webpack, no npm, no node_modules).
The dashboard is a control panel, not a web application — it doesn't need
React/Vue/Svelte.
**Alternatives considered**:
- FastAPI: Better async support, auto-docs. Could migrate if API grows.
- React/Vue: Overkill for a control panel. Adds build complexity.
- htmx: Interesting middle ground. Could enhance the dashboard later without
  going full SPA.
**Consequences**: Frontend is plain HTML/CSS/JS. No build step. Dashboard
deploys by copying files. Adding interactivity means writing vanilla JS or
considering htmx later.

---

### DEC-009: Git-based change tracking on the hub
**Date**: 2026-02-06
**Status**: Accepted
**Context**: Changes to config files on the hub need to be tracked and
reversible. User wants git-style rollback for everything.
**Decision**: Initialize a git repo in `/opt/sandbox/` on the hub. Commit
before and after every config change.
**Reasoning**: Git is already installed on the hub. It's the simplest way
to get diffs, history, and revert capability. The dashboard calls
`git commit` as part of its config change workflow.
**Alternatives considered**:
- etcd with versioned keys: Too heavy for this use case.
- File snapshots (cp -a): Works but no diff capability, no selective revert.
- Database changelog only: Loses the actual file diffs.
**Consequences**: `/opt/sandbox/` is a git repo. Dashboard needs shell
access to run git commands. Config history is browseable via `git log`.
Sensitive files (secrets) must be in `.gitignore`.

---

### DEC-010: Phased evolution instead of big-bang deployment
**Date**: 2026-02-06
**Status**: Accepted
**Context**: System has many features planned (VPN, WebAuthn, changelog,
project persistence, provider abstraction). Building everything at once
is risky and complex.
**Decision**: 9 phases, each leaving the system in a working state.
**Reasoning**: Each phase is independently deployable and testable. If
Phase 3 breaks, Phase 2 still works. This prevents the "build everything
then nothing works and you don't know why" problem.
**Alternatives considered**:
- Big-bang: Build everything, deploy once. High risk of compounding errors.
- Minimal viable product: Deploy only Phase 1-2, plan the rest later.
  This is essentially what we're doing, but with a roadmap so we know
  where we're heading.
**Consequences**: Progress is incremental but visible. Each phase has exit
criteria. Documentation must be updated with each phase.

---

*Add new decisions below this line. Use the next sequential DEC number.*
