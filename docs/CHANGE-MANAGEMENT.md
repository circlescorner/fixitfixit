# Change Management

**Document Status**: Living document
**Purpose**: Define how every change to the system is tracked, reviewed,
and rolled back when things break.

---

## The Problem This Solves

You said: "I want full rollback capabilities" and "I lock myself out and
have to destroy the whole thing."

Every change to this system should be:
1. **Visible** — you can see what changed
2. **Traceable** — you can see when and why it changed
3. **Reversible** — you can undo it

---

## Three Layers of Change Tracking

### Layer 1: Git (Source Code & Documentation)

**What it tracks**: Everything in this repository.
- Terraform configs
- Cloud-init templates
- Dashboard code
- Documentation (these docs)
- Scripts

**How it works**:
- Every change is a git commit with a message explaining why
- Branches for experimental changes
- `git log` shows full history
- `git diff` shows what changed
- `git revert <commit>` undoes a specific change
- `git checkout <commit> -- <file>` restores a single file

**Workflow**:
```
1. Edit files locally
2. git add <specific files>
3. git commit -m "What changed and why"
4. git push origin <branch>
5. Deploy to hub (./scripts/deploy-dashboard.sh or terraform apply)
```

**Branching strategy** (simple):
```
main          ← stable, deployed, known-working
├── feature/* ← new features in progress
├── fix/*     ← bug fixes
└── exp/*     ← experiments (may be thrown away)
```

### Layer 2: On-Hub Config Git (Live Configuration)

**What it tracks**: Configuration files on the running hub.
- `/opt/sandbox/docker-compose.yml`
- `/opt/sandbox/caddy/Caddyfile`
- `/opt/sandbox/authelia/configuration.yml`
- `/opt/sandbox/sandbox/docker-compose.yml`
- `/opt/sandbox/wireguard/wg0.conf` (added in Phase 3)

**How it works**:
- A git repository lives at `/opt/sandbox/.git`
- Before any config change (from dashboard or manual SSH edit), the
  current state is committed
- After the change, the new state is committed
- This creates a before/after pair for every change

**Git hook (pre-change)**:
```bash
#!/bin/bash
# /opt/sandbox/scripts/pre-change.sh
# Called by dashboard before any config modification
cd /opt/sandbox
git add -A
git diff --cached --quiet && exit 0
git commit -m "Snapshot before: $1"
```

**Git hook (post-change)**:
```bash
#!/bin/bash
# /opt/sandbox/scripts/post-change.sh
# Called by dashboard after any config modification
cd /opt/sandbox
git add -A
git diff --cached --quiet && exit 0
git commit -m "Applied: $1"
```

**Rollback from dashboard**:
```bash
# Revert last change
cd /opt/sandbox && git revert --no-edit HEAD
# Then restart affected service
docker compose restart <service>
```

### Layer 3: Changelog (Structured Action Log)

**What it tracks**: Every action performed through the dashboard.
Not just config changes, but operational actions too.

**Entry format**:
```json
{
  "id": "chg-20260206-001",
  "timestamp": "2026-02-06T14:30:00Z",
  "action": "container.image_change",
  "target": "box1",
  "actor": "admin",
  "source": "dashboard_api",
  "details": {
    "old_image": "ubuntu:24.04",
    "new_image": "node:20",
    "reason": "Setting up Node.js development"
  },
  "config_commit_before": "abc1234",
  "config_commit_after": "def5678",
  "reversible": true,
  "rollback_steps": [
    "PUT /api/sandbox/config {\"slot\": 1, \"image\": \"ubuntu:24.04\"}",
    "POST /api/containers/sandbox-box1/restart"
  ]
}
```

**Action types**:
| Action                     | Target       | Reversible | Notes                    |
|----------------------------|--------------|------------|--------------------------|
| `container.start`          | container    | Yes        | Stop to reverse          |
| `container.stop`           | container    | Yes        | Start to reverse         |
| `container.restart`        | container    | Yes        | No-op reversal           |
| `container.image_change`   | container    | Yes        | Change back to old image |
| `container.network_change` | container    | Yes        | Reconnect/disconnect     |
| `sandbox.up`               | all boxes    | Yes        | sandbox.down to reverse  |
| `sandbox.down`             | all boxes    | Yes        | sandbox.up to reverse    |
| `droplet.create`           | droplet      | Yes        | Destroy to reverse       |
| `droplet.destroy`          | droplet      | No         | Data is gone             |
| `config.caddy_change`      | caddy        | Yes        | Git revert + restart     |
| `config.authelia_change`   | authelia     | Yes        | Git revert + restart     |
| `vpn.toggle_mode`          | firewall     | Yes        | Toggle back              |
| `vpn.add_peer`             | wireguard    | Yes        | Remove peer              |
| `project.snapshot`         | project      | N/A        | Additive, no reversal    |
| `project.restore`          | project      | Yes        | Re-restore previous snap |
| `system.phase_upgrade`     | system       | Depends    | See phase rollback notes |

**Storage**: JSON-lines file at `/opt/sandbox/changelog/changelog.jsonl`
One JSON object per line. Easy to parse, easy to grep, easy to append.

**Viewing**:
- Dashboard "Changelog" tab with filterable table
- `jq` on the command line for advanced queries:
  ```bash
  # Last 10 changes
  tail -10 /opt/sandbox/changelog/changelog.jsonl | jq .

  # All container image changes
  jq 'select(.action == "container.image_change")' changelog.jsonl

  # Changes in last 24 hours
  jq 'select(.timestamp > "2026-02-05T14:30:00Z")' changelog.jsonl
  ```

---

## Rollback Strategies by Component

### Terraform (Infrastructure)

```bash
# See what Terraform thinks has changed
cd terraform && terraform plan

# Rollback infrastructure to previous state
git log --oneline terraform/
git checkout <commit> -- terraform/
terraform apply

# Nuclear option: destroy and rebuild
terraform destroy && terraform apply
```

**State file**: `terraform.tfstate` is critical. If lost, Terraform
doesn't know what exists. Keep a backup.
Consider using a remote backend (DO Spaces, S3) in a later phase.

### Docker Compose (Containers)

```bash
# On hub via SSH
cd /opt/sandbox

# See config history
git log --oneline sandbox/docker-compose.yml

# Revert to previous config
git checkout HEAD~1 -- sandbox/docker-compose.yml
docker compose -f sandbox/docker-compose.yml up -d

# Or use the on-hub git revert
git revert HEAD
docker compose -f sandbox/docker-compose.yml up -d
```

### Caddy (Reverse Proxy)

```bash
cd /opt/sandbox
git log --oneline caddy/Caddyfile
git checkout HEAD~1 -- caddy/Caddyfile
docker compose restart caddy
```

### Authelia (Authentication)

```bash
cd /opt/sandbox
git log --oneline authelia/configuration.yml
git checkout HEAD~1 -- authelia/configuration.yml
docker compose restart authelia
```

**WARNING**: If you break Authelia config, you lose web dashboard access.
Always have an SSH session open before changing Authelia config.

### WireGuard (VPN)

```bash
cd /opt/sandbox
git log --oneline wireguard/wg0.conf
git checkout HEAD~1 -- wireguard/wg0.conf
wg syncconf wg0 /opt/sandbox/wireguard/wg0.conf
```

---

## Commit Message Convention

For this repository (source code):
```
<type>: <short description>

<optional longer description>

Refs: <issue or decision number>
```

Types:
- `feat` — new feature or capability
- `fix` — bug fix
- `docs` — documentation update
- `infra` — Terraform or cloud-init changes
- `security` — security-related change
- `refactor` — code restructure, no behavior change

For on-hub config git:
```
<action>: <what changed>
```

Examples:
- `Snapshot before: image change box1`
- `Applied: image change box1 to node:20`
- `Snapshot before: caddy wildcard route update`
- `Applied: caddy wildcard route update`

---

## What Gets Backed Up and How

| Item                     | Backup Method                      | Frequency     |
|--------------------------|------------------------------------|---------------|
| This repo                | git push to GitHub                 | Every commit  |
| On-hub config git        | git push to private remote (later) | Daily or manual|
| Terraform state          | Copy to local + DO Spaces (later)  | After apply   |
| Project data             | Snapshot to /opt/sandbox/backups/  | Before changes|
| Authelia DB              | Copy sqlite3 file                  | Daily          |
| SSH keys                 | Manual backup to secure location   | Once + verify |
| WireGuard keys           | Included in config git             | With config   |

---

## Emergency Recovery Checklist

If the system is completely broken:

```
1. Can you SSH to the hub?
   YES → Fix it from SSH. Check docker logs, check configs.
   NO  → Go to step 2.

2. Can you reach DO web console?
   YES → Log in, check droplet console. Fix SSH config.
   NO  → Go to step 3.

3. Can you access your DigitalOcean account?
   YES → Destroy the hub droplet. terraform apply to rebuild.
   NO  → Contact DigitalOcean support for account recovery.

4. After rebuilding:
   - terraform apply (creates hub from code)
   - set-password.sh (reset Authelia password)
   - SSH in, update users.yml
   - docker compose restart authelia
   - Verify web login
   - Verify SSH breakglass
```

This should never get past step 1 if the breakglass checklist
(see SECURITY-MODEL.md) is maintained.
