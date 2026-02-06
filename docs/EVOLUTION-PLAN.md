# Evolution Plan

**Document Status**: Living document — phases are updated as work progresses
**Current Phase**: Phase 0 (Documentation & Design)

---

## Guiding Constraint

Every phase must leave the system in a **working, recoverable state**. No phase
should introduce a change that can't be rolled back to the previous phase. If a
phase fails midway, the system should still function at the previous phase level.

---

## Phase 0: Documentation & Design (Current)

**Goal**: Define the system in enough detail that it can be built incrementally
without losing coherence.

**Deliverables**:
- [x] SYSTEM-OVERVIEW.md
- [x] ARCHITECTURE.md
- [x] SECURITY-MODEL.md
- [x] EVOLUTION-PLAN.md (this document)
- [x] CHANGE-MANAGEMENT.md
- [x] OPERATIONS-RUNBOOK.md
- [x] AI-COLLABORATION-GUIDE.md
- [x] DECISIONS-LOG.md
- [x] OPEN-QUESTIONS.md

**Exit criteria**: You've read through all docs, answered the questions in
OPEN-QUESTIONS.md, and feel confident the design matches what you want.

---

## Phase 1: Deploy V1 As-Is + Verify SSH Breakglass

**Goal**: Get the existing code deployed and verify you can always get back in.

**Steps**:
1. Fill in `terraform/terraform.tfvars` with your values
2. Run `./scripts/setup.sh`
3. Run `cd terraform && terraform apply`
4. Run `./scripts/set-password.sh 'YourPassword'`
5. SSH to hub, update `users.yml` with the hash
6. Restart Authelia: `cd /opt/sandbox && docker compose restart authelia`
7. Verify web login works (password + TOTP)
8. **CRITICAL**: Verify SSH breakglass works:
   - Can you SSH directly? `ssh root@<hub-ip>`
   - Can you reach the hub from DO web console?
   - Document both methods and test them now.
9. **CRITICAL**: Back up your SSH private key to a second location

**Rollback**: `terraform destroy` tears everything down. `terraform apply`
rebuilds it. Your code is in git.

**Exit criteria**: Web dashboard loads, TOTP works, SSH works, breakglass
tested and documented.

---

## Phase 2: On-Hub Config Versioning

**Goal**: Every config file on the hub is tracked in a local git repo so
changes are visible and reversible.

**Steps**:
1. SSH to hub
2. Initialize git in `/opt/sandbox/`:
   ```bash
   cd /opt/sandbox
   git init
   git add docker-compose.yml caddy/ authelia/configuration.yml sandbox/
   git commit -m "Initial config state"
   ```
3. Add a pre-change snapshot script (runs before any dashboard config change):
   ```bash
   #!/bin/bash
   cd /opt/sandbox
   git add -A
   git diff --cached --quiet || git commit -m "Pre-change snapshot: $1"
   ```
4. Modify dashboard to call this script before writing config changes
5. Add a "Config History" view to the dashboard showing `git log --oneline`
6. Add a "Revert" button that runs `git revert HEAD`

**Rollback**: If the git integration breaks the dashboard, SSH in and
revert the dashboard code. Config files themselves are unchanged.

**Exit criteria**: Making a change via dashboard creates a git commit.
Config history is visible. Revert works.

---

## Phase 3: WireGuard VPN

**Goal**: Add VPN access to the hub so you can toggle to private-only mode.

**Steps**:
1. Add WireGuard to the hub's cloud-init or deploy via SSH:
   ```bash
   apt install wireguard
   wg genkey | tee /opt/sandbox/wireguard/privatekey | wg pubkey > /opt/sandbox/wireguard/publickey
   ```
2. Create server config (`wg0.conf`) — see ARCHITECTURE.md for template
3. Generate client config for your device
4. Open port 51820/udp in both UFW and DO firewall
5. Add WireGuard to Terraform firewall resource
6. Test: connect from your device, verify you can reach 10.200.0.1
7. Test: verify you can reach dashboard through tunnel (https://10.200.0.1
   or configure Caddy to serve on WG interface)
8. Add WireGuard management to dashboard:
   - Show WG status (connected peers)
   - Generate new peer configs
   - Download client config / show QR code
9. Add VPN-only toggle to dashboard (UFW rule changes)
10. **TEST THE TOGGLE**: Connect via WireGuard first, then toggle to VPN-only,
    verify you can still access everything through the tunnel

**Rollback**: If WireGuard breaks, SSH in and stop it:
`systemctl stop wg-quick@wg0`. Web access is unaffected.

**Exit criteria**: VPN connects, tunnel routes work, VPN-only toggle works,
you can still SSH when in VPN-only mode (through tunnel).

---

## Phase 4: WebAuthn/FIDO2 Authentication

**Goal**: Replace TOTP as primary second factor with hardware-bound WebAuthn.

**Prerequisites**: You need a WebAuthn-capable device:
- YubiKey (recommended, ~$25-50), OR
- Laptop with fingerprint reader / Windows Hello / Touch ID, OR
- Phone with biometrics (as a roaming authenticator)

**Steps**:
1. Update Authelia configuration to enable WebAuthn:
   ```yaml
   webauthn:
     disable: false
     display_name: CirclesCorner
     attestation_conveyance_preference: indirect
     user_verification: preferred
     timeout: 60s
   ```
2. Restart Authelia
3. Log in, go to Authelia settings, enroll your WebAuthn device
4. Test login: password + WebAuthn touch
5. Keep TOTP as backup method (don't remove it yet)
6. After confirming WebAuthn works for a week, consider making it the
   default and TOTP the fallback

**Rollback**: Remove the `webauthn` block from config, restart Authelia.
Falls back to TOTP-only. No data lost.

**Exit criteria**: Login works with hardware key. TOTP still works as
fallback. You understand the difference.

---

## Phase 5: Project Persistence + Rollback

**Goal**: Named project volumes that survive container restarts, with
snapshot/restore capability.

**Steps**:
1. Create a `projects/` directory on the hub
2. Define named Docker volumes for each project:
   ```yaml
   volumes:
     project-a-data:
       driver: local
       driver_opts:
         o: bind
         type: none
         device: /opt/sandbox/projects/project-a
   ```
3. Add project management to dashboard:
   - Create project (creates directory + volume)
   - Mount project to a box slot
   - Snapshot project (`tar czf` or `cp -a` to snapshots dir)
   - Restore from snapshot
   - List snapshots with timestamps
4. Initialize each project directory as a git repo for code versioning
5. Add "Push to remote" option (push to GitHub/Gitea via SSH)

**Rollback**: Project data persists in directories. If volume mounting
breaks, data is still on disk.

**Exit criteria**: Projects survive container restart. Snapshots work.
Restore from snapshot works.

---

## Phase 6: Changelog System

**Goal**: Every system mutation is recorded in a structured, searchable log.

**Steps**:
1. Define changelog entry format:
   ```json
   {
     "timestamp": "2026-02-06T12:00:00Z",
     "action": "container.restart",
     "target": "sandbox-box1",
     "actor": "admin",
     "source": "dashboard",
     "details": {"reason": "manual restart"},
     "config_commit": "abc123",
     "reversible": true,
     "rollback_command": "docker restart sandbox-box1"
   }
   ```
2. Add changelog middleware to dashboard (log every API call)
3. Add changelog view to dashboard:
   - Filterable by action type, target, date range
   - Each entry shows the config diff if applicable
   - "Undo" button for reversible actions
4. Store entries in a JSON-lines file or SQLite on the hub
5. Include in config git repo so the changelog itself is versioned

**Rollback**: Changelog is additive. Worst case, delete the changelog
file and it starts fresh. No system impact.

**Exit criteria**: Every dashboard action creates a changelog entry.
Entries are visible and searchable. Undo works for reversible actions.

---

## Phase 7: Modularity — Provider Abstraction

**Goal**: Abstract cloud-provider-specific code so the system can run on
different infrastructure.

**Steps**:
1. Define a **Provider Interface** in the dashboard:
   ```python
   class CloudProvider:
       def list_instances(self) -> list: ...
       def create_instance(self, name, size) -> dict: ...
       def destroy_instance(self, id) -> bool: ...
       def get_instance(self, id) -> dict: ...
   ```
2. Implement `DigitalOceanProvider` (extract from current `app.py`)
3. Add provider selection to dashboard config
4. Create stub implementations for:
   - `AWSProvider` (future)
   - `LocalDockerProvider` (for testing without cloud)
   - `HetznerProvider` (cheap EU alternative)
5. Document the provider interface in ARCHITECTURE.md

**Rollback**: Provider abstraction doesn't change behavior. If it breaks,
revert to direct DO API calls.

**Exit criteria**: Dashboard works with the provider interface.
Adding a new cloud provider means implementing one Python class.

---

## Phase 8: Advanced Features (Future)

These are not prioritized yet. They're here so the design can account
for them.

### GPU Workers
- Spawn GPU-enabled droplets (DO GPU droplets or external providers)
- Mount GPU in Docker containers
- Dashboard shows GPU utilization

### Kubernetes Clustering
- Replace/supplement Docker Compose with k3s (lightweight Kubernetes)
- Use the same dashboard as control plane
- Existing Docker workloads run in k3s via containerd

### Multi-User
- Authelia already supports multiple users in users.yml
- Add user management to dashboard
- Per-user container namespaces
- RBAC for who can create/destroy what

### Self-Hosted Git (Gitea)
- Run Gitea on the hub or a dedicated worker
- All project repos hosted on your domain
- No GitHub dependency for private code

### Monitoring & Alerting
- Prometheus + Grafana on the hub (or lightweight alternative)
- Alert on: disk full, container crash, auth failures, high CPU
- Dashboard widget for system health

### Automated Backups
- Cron job: snapshot project volumes daily
- Push Terraform state to encrypted remote backend
- Export Authelia DB to encrypted backup
- Rotate backups (keep last 7 daily, 4 weekly)

---

## Modularity Strategy

### What "Modular" Means for This System

Every component should be replaceable without rewriting the whole system.
The interfaces between components are the key:

| Component        | Interface                    | Can Be Replaced With     |
|------------------|------------------------------|--------------------------|
| Cloud provider   | REST API (provider class)    | AWS, Hetzner, local VM   |
| Container runtime| Docker socket + compose CLI  | Podman, k3s              |
| Reverse proxy    | HTTP forward_auth + proxy    | nginx, Traefik           |
| Auth provider    | HTTP forward-auth endpoint   | Authentik, Keycloak      |
| VPN              | WireGuard interface + config | Tailscale, Nebula        |
| DNS              | A/AAAA records               | Cloudflare, Route53      |
| TLS              | ACME (Let's Encrypt)         | Any ACME provider        |

### What Stays Constant

- The **dashboard** is the control plane. It talks to all other components
  through their interfaces.
- The **config-as-code** approach: everything is defined in files, tracked
  in git, deployable from scratch.
- The **network model**: private mesh between all resources, public access
  gated through auth.

### Adapting to Self-Hosted / Local

To run this on a local machine or home server instead of DigitalOcean:
1. Replace Terraform with local VM provisioning (Vagrant, libvirt, Proxmox)
2. Replace DO API calls with local hypervisor API
3. Replace DO VPC with a local bridge network
4. Replace DO firewall with local iptables/nftables
5. Keep everything else: Caddy, Authelia, Dashboard, Docker, WireGuard

The documentation should make this mapping clear for each component.
