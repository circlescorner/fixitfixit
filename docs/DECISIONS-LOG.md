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

### DEC-011: DNS via DigitalOcean, domain at Namecheap
**Date**: 2026-02-06
**Status**: Accepted
**Context**: Need to understand DNS chain for the system.
**Decision**: Namecheap holds the domain, nameservers point to DigitalOcean.
DNS records (A, wildcard) are managed in DO panel and programmatically via
DO API. No Terraform for DNS — hub self-manages its DNS records on boot.
**Reasoning**: User already has this setup working. Changing nameservers or
registrars adds risk for no benefit. DO API can create/update DNS records
from the hub itself, removing the need for local Terraform.
**Alternatives considered**:
- Cloudflare DNS: User mentioned hearing about it but never got it working.
  Adds another account, another potential lockout point. Skip for now.
- Terraform-managed DNS: Requires local machine with Terraform. User doesn't
  have a local machine. Hub must self-manage.
**Consequences**: Hub cloud-init sets up DNS records via DO API on boot.
Reserved IP (if kept) makes this simpler — DNS never changes.

---

### DEC-012: Mobile-first, iPhone-primary design
**Date**: 2026-02-06
**Status**: Accepted — SUPERSEDES assumptions in DEC-007 and DEC-005
**Context**: User revealed they primarily operate from an iPhone 16 on
corporate WiFi. No trusted PC. Sometimes uses work PCs, public computers,
or friends' machines where they cannot install software.
**Decision**: The entire system is designed mobile-first. Everything must
work from Safari on iPhone with no plugins, apps, VPN clients, or
certificates required for daily operation.
**Reasoning**: The user's actual day-to-day is their phone. Designing for
a workstation they don't have guarantees friction and failure. A web-based
control panel over normal HTTPS is the only reliable access path.
**Alternatives considered**:
- Workstation-based design (original plan): Requires Terraform, SSH clients,
  WireGuard client. User doesn't have a workstation.
- iPad/tablet: User didn't mention one. iPhone is the constant.
**Consequences**:
- Terraform removed as user prerequisite (runs inside infrastructure, not locally)
- SSH removed as primary access method (breakglass via DO Console only)
- WireGuard demoted from requirement to optional enhancement
- All management via web dashboard on normal HTTPS (port 443)
- Dashboard UI must be mobile-responsive
- Deployment via DO web panel, not local CLI tools

---

### DEC-013: WebAuthn via iPhone Face ID as primary 2FA
**Date**: 2026-02-06
**Status**: Accepted — SUPERSEDES DEC-004
**Context**: User needs 2FA that works on iPhone in standard Safari browser
with no additional hardware or software.
**Decision**: WebAuthn with iPhone Face ID (passkey) as primary 2FA.
Authelia supports this natively. TOTP as emergency backup only.
**Reasoning**: iPhone Face ID is a WebAuthn authenticator built into Safari.
The private key is stored in the Secure Enclave (hardware). Login flow:
type password → Face ID prompt → authenticated. Looks like a normal website
login. No app to install. No code to type. No hardware to carry.

This is actually STRONGER than a YubiKey for the user's scenario:
- Face ID = biometric (something you are) + device possession (something you have)
- Private key in Secure Enclave, cannot be extracted
- Phishing-resistant (bound to the domain)
- Works on corporate WiFi — looks like normal HTTPS traffic

**Alternatives considered**:
- YubiKey: Strong but requires USB port. User often on PCs they can't
  plug into. iPhone USB-C + YubiKey 5C is possible but adds friction.
- TOTP only: Shared secret weakness user correctly identified.
- SMS: SIM-swapping attacks. Also costs money per message.
- Email magic links: Workable fallback, added as emergency option.
**Consequences**: WebAuthn enrollment happens during first-time setup.
Face ID prompt on every login. TOTP kept as backup. If user gets a new
phone, they need to re-enroll (or restore from iCloud Keychain passkey sync).

---

### DEC-014: Normal HTTPS only — no VPN requirement for daily use
**Date**: 2026-02-06
**Status**: Accepted — MODIFIES DEC-005
**Context**: User accesses from corporate WiFi where unusual traffic protocols
would be noticed by IT. Needs the system to look like a normal website visit.
**Decision**: Daily access is through standard HTTPS on port 443. No VPN,
no unusual ports, no special protocols required. WireGuard remains in the
system as an optional enhancement for when user has a device that supports
it, but is NOT required for any core functionality.
**Reasoning**: WireGuard traffic is UDP on port 51820 — visibly different
from normal web traffic. Corporate firewalls may block it. Corporate IT
may flag it. The user needs circlescorner.xyz to look like any other website.
**Alternatives considered**:
- WireGuard-over-HTTPS (stunnel/wstunnel): Wraps WG in HTTPS. Adds
  complexity and another moving part.
- Tailscale: Uses DERP relays over HTTPS when direct UDP fails. Could
  work but adds vendor dependency.
**Consequences**: VPN-only toggle redesigned. Security modes are now:
- Normal: HTTPS from any IP, password + Face ID
- Restricted: HTTPS from allowlisted IPs only
- Lockdown: No web access, DO Console only
WireGuard moved from Phase 3 to Phase 5+ (optional enhancement).

---

### DEC-015: SSH as breakglass only, DO Console as emergency access
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User keeps locking themselves out via SSH misconfigurations.
Has SSH keys in iPhone notes (insecure). Wants to avoid SSH dependency.
**Decision**: SSH is configured on the hub for emergency breakglass only.
Primary access is web dashboard. Emergency access is DigitalOcean web
console (browser-based terminal). SSH keys managed by cloud-init, not by
the user manually.
**Reasoning**: The user's lockout pattern is: make SSH more secure → lock
self out → destroy and rebuild. Breaking this cycle means making SSH
irrelevant for daily operations. DO Console provides a browser-based
terminal that requires only DO account login — works from iPhone.
**Alternatives considered**:
- No SSH at all: Possible but removes a useful diagnostic tool. Keep it
  available, just don't depend on it.
- SSH via dashboard: Add a web-based terminal to the dashboard. Good idea
  for Phase 3+ but not Phase 1.
**Consequences**: cloud-init sets up SSH with a generated key pair. The
public key is stored in the DO account. The user rarely needs to use SSH
directly. If they do, DO Console provides it without any local SSH client.

---

### DEC-016: Region atl1 primary, nyc1 fallback
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User is in central US, closest to Atlanta.
**Decision**: Deploy to `atl1` if available. If resource types are
unavailable, fall back to `nyc1`.
**Reasoning**: Lower latency to nearest region. Atlanta is ~200ms closer
than NYC for central US users. The system should detect and report
availability issues.
**Alternatives considered**: nyc1 (reliable, well-established, always available).
**Consequences**: Cloud-init and dashboard API calls specify region. Must
handle the case where atl1 doesn't have the requested droplet size. Dashboard
should show a "fallback to nyc1" option when atl1 creation fails.

---

### DEC-017: Smart hibernation instead of destruction
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User wants auto-shutdown to save money but NEVER wants to lose
work. "The system must never destroy unless it can be restored."
**Decision**: Workers use snapshot-then-power-off instead of destroy. Process:
1. Inactivity detected (3min) → Dashboard notifies user
2. No response after 2min → Create DO snapshot of the droplet
3. Power off the droplet (stops hourly billing for compute, but powered-off
   droplets still cost the full monthly rate on DO)
4. Actually: snapshot → destroy → restore from snapshot when needed

**IMPORTANT DO BILLING NOTE**: Powered-off droplets are billed the same as
running ones. To actually stop charges, the droplet must be DESTROYED.
Snapshots cost $0.06/GB/month. A 25GB disk snapshot = $1.50/month.
This is much cheaper than a running droplet.

**Workflow**: Active → Warn → Snapshot → Destroy → (later) Restore from snapshot

**Reasoning**: DO doesn't have a "hibernate" feature. The closest equivalent
is snapshot (preserves full disk state) → destroy (stops billing) → create
from snapshot (restores exact state). This gives the "fall asleep" behavior
the user wants.
**Consequences**: Dashboard must manage snapshot lifecycle. Budget controller
must account for snapshot storage costs. Restore must be a one-click operation.
Restore time is ~1-3 minutes (create droplet from snapshot).

---

### DEC-018: Budget controller in dashboard
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User wants to stay within $15/month and needs cost visibility.
**Decision**: Dashboard includes a budget controller with:
- Monthly budget setting (default $15)
- Real-time spend tracker (pulls from DO billing API)
- Cost estimator before spawning (shows projected hourly/monthly cost)
- Spend alerts at 50%, 75%, 90%, 100% of budget
- Hard stop option: refuse to create droplets over budget
- Per-deployment cost tracking (from spawn to destroy)
**Reasoning**: Without cost visibility, it's easy to forget running resources.
The budget controller prevents surprise bills.
**Consequences**: Dashboard needs DO billing API access. Cost data displayed
prominently on the main dashboard. Recommended default size: s-2vcpu-4gb
($0.036/hr) to stay within budget.

---

### DEC-019: DO token safety — server-side only with guardrails
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User worried about accidentally exposing DO token via www.
**Decision**: Token stays server-side (Flask environment variable). Never
sent to the browser. Add safety layers:
- Confirmation dialogs for destructive actions (destroy droplet, etc.)
- Rate limiting: max 1 droplet creation per minute
- Audit log of all API actions
- 30-second undo window for creates (cancel before finalized)
**Reasoning**: The dashboard is already behind Authelia. Token is only used
by the Flask backend, never exposed to the frontend JavaScript. The added
guardrails protect against the "doing something stupid" fear.
**Alternatives considered**:
- Proxy VM: Adds $6/month cost and complexity. Overkill for single-user.
- Scoped tokens: DO doesn't support fine-grained token permissions yet.
**Consequences**: All DO API calls go through Flask backend. Frontend only
sees sanitized responses. Audit log captures every action with timestamp.

---

### DEC-020: Projects explored on-demand, no immediate hosting
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User has no projects to deploy immediately but wants the
infrastructure ready for when projects start.
**Decision**: Phase 1 deploys the control plane only. Projects (UI-TARS-desktop,
claude-mem, superpowers) explored in Phase 5 when the platform is stable.
Focus on getting the foundation right first.
**Consequences**: Phase 1 is leaner. Project-specific requirements gathered
when we reach Phase 5.

---

### DEC-021: Bare git repos initially, Gitea later
**Date**: 2026-02-06
**Status**: Accepted
**Context**: User wants self-hosted git on their domain but doesn't need
a full git server immediately.
**Decision**: Start with bare repos on the hub for config tracking. Plan
for Gitea on a dedicated worker in Phase 7+, potentially also serving as
a secrets management interface.
**Consequences**: Config versioning (Phase 2) uses local git only. Remote
push comes later with Gitea.

---

### DEC-022: Timezone America/Chicago
**Date**: 2026-02-06
**Status**: Accepted
**Decision**: Dashboard displays times in Central US timezone (America/Chicago).
Server runs in UTC. Conversion happens in the frontend.

---

### DEC-023: Security modes replace VPN-only toggle
**Date**: 2026-02-06
**Status**: Accepted — SUPERSEDES VPN-only toggle concept in SECURITY-MODEL.md
**Context**: Original design had a VPN-only toggle that blocked public HTTPS
and required WireGuard. User can't use WireGuard as daily driver (corporate WiFi).
**Decision**: Three security modes, controllable from dashboard:
1. **Normal**: HTTPS accessible from any IP. Password + Face ID required.
   This is the daily-driver mode.
2. **Restricted**: HTTPS accessible only from allowlisted IPs (e.g., your
   phone's current IP). Dashboard has "add my current IP" button.
3. **Lockdown**: No web access at all. Only DigitalOcean Console. For when
   you're done for the day and want maximum security.
**Reasoning**: These modes work entirely over standard HTTPS. No special
protocols. No corporate IT flags. The "restricted" mode is a practical
middle ground — only your current IP can access the dashboard.
**Consequences**: Firewall rules managed by dashboard. IP allowlist stored
in config. Mode displayed prominently on dashboard. Mode change requires
confirmation dialog ("Are you sure? You'll need DO Console to undo lockdown.")

---

### DEC-024: No local prerequisites — bootstrap from DO panel only
**Date**: 2026-02-06
**Status**: Accepted — SUPERSEDES DEC-007 (Terraform as requirement)
**Context**: User has no local machine. iPhone only. Cannot run Terraform,
scripts, or CLI tools locally.
**Decision**: The entire system bootstraps from the DigitalOcean web panel.
The user creates a droplet and pastes a cloud-init script. Cloud-init pulls
the repo from GitHub and self-configures. First-time setup completes via
the web dashboard (setup wizard).

**Bootstrap flow**:
1. User logs into DO panel (iPhone browser)
2. Creates VPC (if not exists) — one-time manual step in DO panel
3. Creates droplet with cloud-init user data
4. Creates/verifies DNS A record in DO panel
5. Visits https://circlescorner.xyz
6. Setup wizard: enter DO token, set password, enroll Face ID
7. Dashboard is live

**Terraform's new role**: Terraform configs remain in the repo as
documentation and for optional use when the user does have a workstation.
The hub can also run Terraform internally for worker provisioning. But
Terraform is NOT required for initial deployment.
**Consequences**: Cloud-init is the primary deployment mechanism. Dashboard
needs a first-time setup wizard. No local tools needed beyond a web browser.

---

*Add new decisions below this line. Use the next sequential DEC number.*
