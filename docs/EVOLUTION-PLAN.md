# Evolution Plan

**Document Status**: Living document — phases are updated as work progresses
**Current Phase**: Phase 0 complete. Phase 1 ready to begin.
**Last updated**: 2026-02-06 — major redesign for mobile-first (DEC-012)

---

## Guiding Constraints

1. Every phase must leave the system in a **working, recoverable state**. No phase
   should introduce a change that can't be rolled back to the previous phase.
2. **No local tools required.** Everything deploys and operates from a web browser
   (iPhone Safari). No Terraform, SSH, or CLI on the user's device.
3. **The user must never be locked out.** Every phase verifies that breakglass
   access (DO Console) works.
4. **Budget: $15/month operating target.** Use s-2vcpu-4gb workers by default.

---

## Phase 0: Documentation & Design (COMPLETE)

**Goal**: Define the system in enough detail that it can be built incrementally
without losing coherence.

**Deliverables**:
- [x] SYSTEM-OVERVIEW.md
- [x] ARCHITECTURE.md (revised for mobile-first)
- [x] SECURITY-MODEL.md (revised for Face ID auth)
- [x] EVOLUTION-PLAN.md (this document, revised)
- [x] CHANGE-MANAGEMENT.md
- [x] OPERATIONS-RUNBOOK.md (revised for DO panel deployment)
- [x] AI-COLLABORATION-GUIDE.md
- [x] DECISIONS-LOG.md (DEC-001 through DEC-024)
- [x] OPEN-QUESTIONS.md (13 questions resolved, 4 new ones)

**Exit criteria**: User has read docs, questions answered, design matches intent.

---

## Phase 1: Bootstrap Hub From DO Panel + WebAuthn Setup

**Goal**: Deploy the always-on hub from the DigitalOcean web panel using only
a browser (iPhone or any device). System self-configures. User completes
setup through a web wizard. Face ID enrolled as primary authentication.

### Prerequisites (user actions — no code, just clicking)

- [ ] **CRITICAL**: Save DigitalOcean recovery codes
  (DO panel → Account → Security → download/screenshot recovery codes)
- [ ] Verify DNS: circlescorner.xyz A record points to your Reserved IP
  (DO panel → Networking → Domains → circlescorner.xyz)
- [ ] If no A record exists, create one: `@` → your Reserved IP
- [ ] Also create wildcard: `*` → same Reserved IP

### Deployment Steps (all from browser)

1. **Create VPC** (if not exists):
   - DO panel → Networking → VPC → Create VPC
   - Name: `sandbox-vpc`
   - Region: `atl1` (or `nyc1` if atl1 unavailable)
   - IP range: `10.100.0.0/16`

2. **Create Hub Droplet**:
   - DO panel → Droplets → Create Droplet
   - Region: `atl1` (same as VPC)
   - Image: Ubuntu 24.04
   - Size: `s-1vcpu-1gb` ($6/month)
   - VPC: `sandbox-vpc`
   - Authentication: SSH key (create or select existing)
   - Enable Backups: Yes ($1.20/month)
   - User Data: Paste the cloud-init script (see below)
   - Tags: `sandbox`, `hub`

3. **Assign Reserved IP**:
   - DO panel → Networking → Reserved IPs
   - Reassign your existing Reserved IP to the new hub droplet

4. **Wait for cloud-init** (~3-5 minutes):
   - Cloud-init installs packages, pulls repo, starts services
   - You can check progress via DO Console:
     DO panel → Droplets → sandbox-hub → Console
     ```
     tail -f /var/log/cloud-init-output.log
     ```
   - When `/opt/sandbox/status` contains "ready", it's done

5. **Visit https://circlescorner.xyz**:
   - You should see the first-time setup wizard
   - If you see an Authelia login instead, the wizard hasn't been
     implemented yet — see the temporary setup procedure below

6. **Complete setup**:
   - Enter your DigitalOcean API token
   - Set your admin password
   - Enroll Face ID (WebAuthn) as your 2FA method
   - Optionally enroll TOTP as backup

7. **Verify breakglass**:
   - Open DO Console (DO panel → Droplets → sandbox-hub → Console)
   - Verify you can get a root shell
   - This is your emergency access if the web dashboard breaks

### Cloud-Init Script (User Data)

This is what gets pasted into the "User Data" field when creating the droplet.
It will be generated and maintained in the repo at `infra/cloud-init-v2.yml`.

The script must:
- Install Docker, git, curl, jq, ufw, and dependencies
- Configure UFW (SSH + HTTP + HTTPS + VPC traffic)
- Clone this repo from GitHub
- Build and start all Docker containers (Caddy, Authelia, Dashboard)
- Set up Docker networks (sandbox_frontend, sandbox_net)
- Start sandbox containers (box1-box4)
- Write "ready" to /opt/sandbox/status when complete

### Temporary Setup Procedure (Until Setup Wizard Is Built)

The V1 code doesn't have a setup wizard. Until that's built, first-time
setup requires DO Console:

1. Open DO Console for the hub
2. Generate password hash:
   ```bash
   docker run --rm authelia/authelia:latest \
     authelia crypto hash generate argon2 --password 'YourPassword'
   ```
3. Edit users file:
   ```bash
   nano /opt/sandbox/authelia/users.yml
   ```
   Replace the CHANGE_ME line with the generated hash
4. Generate JWT secret:
   ```bash
   openssl rand -hex 32
   ```
   Edit the Authelia config to use this secret
5. Set your DO token in the dashboard environment:
   ```bash
   nano /opt/sandbox/docker-compose.yml
   ```
   Replace `${do_token}` with your actual token
6. Restart services:
   ```bash
   cd /opt/sandbox && docker compose down && docker compose up -d
   ```
7. Visit https://circlescorner.xyz and log in

**This is the inelegant part.** The setup wizard (Phase 1b) eliminates
this DO Console requirement for future deployments.

### Phase 1b: Setup Wizard

**Goal**: Replace the manual DO Console setup with a browser-based wizard.

**Code changes needed**:
1. Dashboard detects "first boot" (no admin password set)
2. Shows setup wizard instead of redirect to Authelia
3. Wizard collects: DO token, admin email, admin password
4. Wizard generates JWT secret and configures Authelia
5. Wizard prompts WebAuthn enrollment (Face ID)
6. Wizard enables Authelia protection
7. Future visits go through normal auth flow

This eliminates the need for DO Console during initial setup.

### Cost for Phase 1

| Item                      | Monthly Cost |
|---------------------------|-------------|
| Hub (s-1vcpu-1gb)         | $6.00       |
| Backups                   | $1.20       |
| Reserved IP (attached)    | $0.00       |
| **Total**                 | **$7.20**   |

### Rollback

- If everything breaks: Destroy the droplet from DO panel. DNS still
  points to Reserved IP. Create new droplet, assign Reserved IP, paste
  cloud-init again. Everything rebuilds from code in git.
- The hub is disposable. The code is in GitHub. The Reserved IP survives.

### Exit Criteria

- [ ] Hub droplet running in atl1 (or nyc1 fallback)
- [ ] https://circlescorner.xyz loads the dashboard
- [ ] Login works (password + TOTP initially, Face ID after wizard)
- [ ] Container management works (start/stop box1-box4)
- [ ] DO Console breakglass verified
- [ ] DO recovery codes saved
- [ ] Dashboard is mobile-responsive (usable on iPhone)

---

## Phase 2: WebAuthn (Face ID) + Config Versioning

**Goal**: Replace TOTP with Face ID authentication. Add git-based config
tracking on the hub so all changes are reversible.

### WebAuthn Setup
1. Update Authelia config to enable WebAuthn:
   ```yaml
   webauthn:
     disable: false
     display_name: CirclesCorner
     attestation_conveyance_preference: indirect
     user_verification: preferred
     timeout: 60s
   ```
2. Restart Authelia
3. Log in with password + TOTP
4. Go to Authelia settings → Register WebAuthn device
5. iPhone Face ID prompt → approve
6. Test: log out, log in with password + Face ID
7. Keep TOTP as backup

### Config Versioning
1. Initialize git in `/opt/sandbox/` on hub (via DO Console or dashboard):
   ```bash
   cd /opt/sandbox && git init
   git add docker-compose.yml caddy/ authelia/configuration.yml sandbox/
   git commit -m "Initial config state"
   ```
2. Add pre/post change hooks to dashboard
3. Add "Config History" view to dashboard (git log)
4. Add "Revert" button (git revert)

### Rollback
- WebAuthn: Remove config block, restart Authelia → falls back to TOTP
- Config git: If it breaks, SSH via DO Console and revert

### Exit Criteria
- [ ] Face ID login works from iPhone Safari
- [ ] TOTP still works as backup
- [ ] Config changes create git commits
- [ ] Config history viewable from dashboard
- [ ] Revert works from dashboard

---

## Phase 3: Budget Controller + Smart Hibernation

**Goal**: Cost visibility and automatic worker lifecycle management.

### Budget Controller
1. Add DO billing API integration to dashboard
2. Display real-time monthly spend on dashboard home
3. Cost estimator: before spawning a worker, show projected cost
4. Monthly budget setting with alerts at 50/75/90/100%
5. Recommended default worker size: s-2vcpu-4gb ($0.036/hr)

### Smart Hibernation
1. Track worker activity (API calls, SSH connections, dashboard interactions)
2. Inactivity detection: after configurable period (default 3min), notify
3. Dashboard notification: "Worker X inactive. Extend (2-60min) or hibernate?"
4. If no response after 2min: create DO snapshot → destroy droplet
5. Dashboard shows hibernated workers with "Wake Up" button
6. Wake up: create droplet from snapshot → assign to VPC → ready in ~2min
7. Snapshot costs ~$1.50/month per 25GB snapshot

### Cost Display (always visible on dashboard)
```
Budget: $15.00/month
Spent:  $8.40 (56%)
┣━━━━━━━━━━━━━━━░░░░░░░░░░┫

Running: Hub ($6/mo) + Worker-1 ($0.036/hr)
Hibernated: Worker-2 (snapshot: $1.50/mo)
Estimated month-end: $12.80
```

### Rollback
- Budget controller: Display-only, doesn't break anything
- Hibernation: Snapshots are additive. If restore fails, snapshot persists.

### Exit Criteria
- [ ] Budget displayed on dashboard
- [ ] Cost estimator shows before spawning
- [ ] Inactivity warning appears
- [ ] Worker hibernates (snapshot + destroy) on timeout
- [ ] Worker restores from snapshot (wake up)
- [ ] Monthly spend stays within budget

---

## Phase 4: Security Modes + Changelog

**Goal**: Add security mode switching and structured action logging.

### Security Modes
1. **Normal**: HTTPS from any IP (daily driver)
2. **Restricted**: HTTPS from allowlisted IPs only
   - "Add my current IP" button on dashboard
   - IP allowlist stored in config (git-tracked)
3. **Lockdown**: No web access, DO Console only
   - Confirmation: "You will lose web access. Use DO Console to re-enable."

Implementation: Dashboard manages UFW rules on the hub.

### Changelog
1. Every dashboard action logged in structured format (JSON-lines)
2. Changelog tab in dashboard: filterable, searchable
3. "Undo" button for reversible actions
4. Changelog entries include config git commit references

### Rollback
- Security modes: UFW rule changes, reversible from DO Console
- Changelog: Additive data, no system impact if deleted

### Exit Criteria
- [ ] All three security modes work
- [ ] "Add my current IP" works for Restricted mode
- [ ] Changelog records every dashboard action
- [ ] Undo works for reversible actions
- [ ] Switching to Lockdown + back works via DO Console

---

## Phase 5: Project Persistence + WireGuard (Optional)

**Goal**: Named project volumes with snapshot/restore. Optional WireGuard
for when user has a VPN-capable device.

### Project Persistence
1. Create project management in dashboard
2. Named Docker volumes mounted to containers
3. Snapshot/restore via dashboard
4. Projects survive container restarts and hub rebuilds

### WireGuard (Optional)
1. Install WireGuard on hub
2. Generate server + client configs
3. Dashboard: manage peers, download configs, show QR codes
4. Not required for daily operation — enhancement for extra security
   when on a personal device

### Rollback
- Projects: Data on disk, survives component failures
- WireGuard: Can be stopped without affecting web access

### Exit Criteria
- [ ] Projects persist across container restart
- [ ] Project snapshot/restore works
- [ ] (Optional) WireGuard connects from iPhone WG app

---

## Phase 6: Provider Abstraction

**Goal**: Abstract cloud-provider-specific code so the system can run on
different infrastructure.

### Steps
1. Define CloudProvider interface in dashboard
2. Extract DigitalOcean-specific code into DOProvider class
3. Add provider selection to dashboard config
4. Document interface for future providers (AWS, Hetzner, local)

### Rollback
- Abstraction doesn't change behavior. Revert to direct API calls if broken.

### Exit Criteria
- [ ] Dashboard works through provider interface
- [ ] Adding a new provider = implementing one class

---

## Phase 7: Advanced Features (Future)

These are not prioritized yet. They're here so the design accounts for them.

### GPU Workers
- Spawn GPU-enabled droplets for AI workloads
- Dashboard shows GPU utilization

### Kubernetes Clustering
- k3s (lightweight) on workers
- Dashboard as control plane
- Docker workloads run in k3s

### Multi-User
- Per-user auth and container namespaces
- RBAC from dashboard

### Self-Hosted Git (Gitea)
- git.circlescorner.xyz
- Potential secrets management interface
- All repos on your infrastructure

### Monitoring & Alerting
- System health dashboard widget
- Alert on: disk full, container crash, auth failures

### Automated Backups
- Daily config snapshots
- Project volume backups
- Backup rotation

### Web Terminal
- Browser-based terminal in dashboard (like DO Console but built-in)
- Eliminates last reason to use DO Console for daily work

---

## Modularity Strategy

### What "Modular" Means for This System

Every component is replaceable without rewriting the whole system.
The interfaces between components are the key:

| Component        | Interface                    | Can Be Replaced With     |
|------------------|------------------------------|--------------------------|
| Cloud provider   | REST API (provider class)    | AWS, Hetzner, local VM   |
| Container runtime| Docker socket + compose CLI  | Podman, k3s              |
| Reverse proxy    | HTTP forward_auth + proxy    | nginx, Traefik           |
| Auth provider    | HTTP forward-auth endpoint   | Authentik, Keycloak      |
| VPN (optional)   | WireGuard interface + config | Tailscale, Nebula        |
| DNS              | A/AAAA records               | Cloudflare, Route53      |
| TLS              | ACME (Let's Encrypt)         | Any ACME provider        |

### What Stays Constant

- The **dashboard** is the control plane
- The **config-as-code** approach: files + git + deployable from scratch
- The **network model**: private mesh between resources, public gated by auth
- The **mobile-first** access pattern: everything works from a phone browser

### Adapting to Self-Hosted / Local

To run this on a local machine or home server instead of DigitalOcean:
1. Replace DO API calls with local hypervisor API (Proxmox, libvirt)
2. Replace DO VPC with a local bridge network
3. Replace DO firewall with local iptables/nftables
4. Replace DO DNS with local DNS or hosts file
5. Keep everything else: Caddy, Authelia, Dashboard, Docker
