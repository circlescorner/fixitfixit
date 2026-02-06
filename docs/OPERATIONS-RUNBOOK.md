# Operations Runbook

**Document Status**: Living document — update when you learn a new procedure
**Purpose**: Step-by-step instructions for operating, maintaining, and
recovering the system. Written so you can follow them at 3am when
something is broken and you're stressed.

---

## Table of Contents

1. [First-Time Deployment](#first-time-deployment)
2. [Daily Operations](#daily-operations)
3. [Common Tasks](#common-tasks)
4. [Troubleshooting](#troubleshooting)
5. [Recovery Procedures](#recovery-procedures)
6. [Maintenance Schedule](#maintenance-schedule)

---

## First-Time Deployment

### Prerequisites Checklist

Before you start, you need:

- [ ] DigitalOcean account with billing set up
- [ ] DigitalOcean API token (create at https://cloud.digitalocean.com/account/api/tokens)
- [ ] A domain name (you have circlescorner.xyz)
- [ ] DNS pointed at DigitalOcean nameservers, OR you'll set A records manually
- [ ] Terraform installed (`terraform --version` should work)
- [ ] SSH key pair (`ls ~/.ssh/id_ed25519` should show a file)
- [ ] This repo cloned to your local machine

### Step-by-Step Deployment

```bash
# 1. Copy the example config
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# 2. Generate secrets
# JWT secret for Authelia:
openssl rand -hex 32
# Copy the output

# 3. Edit terraform.tfvars
# Fill in these values:
#   do_token          = "your-digitalocean-api-token"
#   domain            = "circlescorner.xyz"
#   admin_email       = "your-email@example.com"
#   authelia_jwt_secret = "the-hex-string-from-step-2"
#   manage_dns        = true  (if using DO DNS)

# 4. Run setup
./scripts/setup.sh
# This checks prerequisites, generates SSH key if needed, runs terraform init

# 5. Review what Terraform will create
cd terraform
terraform plan
# You should see: 1 VPC, 1 SSH key, 1 firewall, 1 droplet, optionally DNS records
# If it looks right:

# 6. Apply
terraform apply
# Type "yes" when prompted
# Wait for it to complete (usually 1-2 minutes)
# Note the outputs: hub_ip, dashboard_url

# 7. Wait for cloud-init to finish (the hub is installing packages)
# Check by SSHing in:
ssh root@<hub_ip>
# If you get "Connection refused", wait 30 seconds and try again
# Once in:
cat /opt/sandbox/status
# When it says "ready", cloud-init is done

# 8. Set your Authelia password
# Back on your local machine:
./scripts/set-password.sh 'YourSecurePassword'
# This outputs an argon2id hash. Copy it.

# 9. Update the user database on the hub
ssh root@<hub_ip>
nano /opt/sandbox/authelia/users.yml
# Replace the CHANGE_ME_GENERATE_A_HASH line with your hash
# The line should look like:
#   password: "$argon2id$v=19$m=65536,t=3,p=4$<your-actual-hash>"
# Save and exit (Ctrl+X, Y, Enter)

# 10. Restart Authelia to pick up the new password
cd /opt/sandbox && docker compose restart authelia

# 11. Open your browser
# Go to https://circlescorner.xyz
# Log in: username "admin", your password
# You'll be prompted to set up TOTP (scan QR code with authenticator app)
# Enter the 6-digit code

# 12. Verify the dashboard loads
# You should see the container management interface

# 13. VERIFY BREAKGLASS (do this now, not later)
# Open a new terminal:
ssh root@<hub_ip>
# If this works, your breakglass is confirmed.
# Also test the DO web console:
# Browser → cloud.digitalocean.com → Droplets → sandbox-hub → Console
```

### Post-Deployment Checklist

- [ ] Dashboard loads at https://circlescorner.xyz
- [ ] TOTP enrollment completed
- [ ] SSH access confirmed from your machine
- [ ] DO web console access confirmed
- [ ] SSH private key backed up to second location
- [ ] terraform.tfvars is NOT in git (check: `git status` should not show it)

---

## Daily Operations

### Starting Your Dev Session

1. Open https://circlescorner.xyz
2. Log in (password + TOTP/WebAuthn)
3. Check the dashboard: are your containers running? Any alerts?
4. Start the containers you need (if they're stopped)
5. Start working

### Ending Your Dev Session

1. **If you want containers to keep running**: Just close the browser. Done.
2. **If you want to save money/resources**: Stop containers you don't need.
3. **If you have on-demand droplets**: Destroy them if you're done.
   Each running droplet costs money per hour.
4. **Never destroy the hub** unless you're done for a long time.
   The hub is $6/month whether it's idle or busy.

### Checking System Health

From the dashboard:
- Green status indicators = containers running
- Red/grey = containers stopped or errored
- Check "Networks" section: all expected networks present?
- Check "Droplets" section: any unexpected droplets?

From SSH:
```bash
ssh root@<hub_ip>

# Check all Docker containers
docker ps -a

# Check Docker disk usage
docker system df

# Check system resources
df -h          # Disk space
free -h        # Memory
uptime         # Load average

# Check service logs
docker logs sandbox-caddy-1 --tail 20
docker logs sandbox-authelia-1 --tail 20
docker logs sandbox-dashboard-1 --tail 20
```

---

## Common Tasks

### Change a Container's Image

**From dashboard**: Click "Configure" on the container card → select
new image → click "Apply" → container restarts with new image.

**From CLI**:
```bash
ssh root@<hub_ip>
cd /opt/sandbox

# Edit the sandbox compose file
nano sandbox/docker-compose.yml
# Change the image for the box you want

# Apply
docker compose -f sandbox/docker-compose.yml up -d
```

### Spin Up an On-Demand Droplet

**From dashboard**: Click "New Droplet" → enter name → select size → Create.
Wait ~60 seconds for it to boot and initialize.

**Verify networking**:
```bash
# From the hub, ping the new worker's VPC IP
ssh root@<hub_ip>
ping <worker_private_ip>
```

### Destroy an On-Demand Droplet

**From dashboard**: Click "Destroy" on the droplet card → Confirm.

**This is irreversible.** Any data on the droplet is gone. Make sure
you've saved anything important first.

### SSH to a Worker Droplet

```bash
# From your local machine (if SSH port is open from internet):
ssh root@<worker_public_ip>

# From the hub (always works, uses VPC):
ssh root@<worker_private_ip>
```

### View Container Logs

**From dashboard**: Click "Logs" on the container card.

**From CLI**:
```bash
ssh root@<hub_ip>
docker logs sandbox-box1 --tail 100 -f
# -f follows live output. Ctrl+C to stop.
```

### Update the Dashboard Code

```bash
# On your local machine, after making changes to dashboard/:
./scripts/deploy-dashboard.sh <hub_ip>
# This rsync's the code and rebuilds the Docker image
```

### Change Authelia Password

```bash
# On your local machine:
./scripts/set-password.sh 'NewPassword'
# Copy the hash

# On the hub:
ssh root@<hub_ip>
nano /opt/sandbox/authelia/users.yml
# Replace the password hash
cd /opt/sandbox && docker compose restart authelia
```

---

## Troubleshooting

### "I can't reach the website"

```
1. Is the hub running?
   → Check: DigitalOcean dashboard → Droplets → sandbox-hub → Status
   → If off: Power On from DO dashboard

2. Is DNS pointing to the hub?
   → Check: dig circlescorner.xyz
   → Should return the hub's public IP
   → If wrong: update DNS records (DO DNS panel or your registrar)

3. Is Caddy running?
   → SSH to hub: docker ps | grep caddy
   → If not running: cd /opt/sandbox && docker compose up -d caddy
   → Check logs: docker logs sandbox-caddy-1

4. Is Authelia running?
   → SSH to hub: docker ps | grep authelia
   → If not running: cd /opt/sandbox && docker compose up -d authelia
   → Check logs: docker logs sandbox-authelia-1

5. Is the firewall blocking?
   → SSH to hub: ufw status
   → Should show 80/tcp ALLOW, 443/tcp ALLOW
   → If missing: ufw allow 80/tcp && ufw allow 443/tcp
```

### "I can SSH but the web login doesn't work"

```
1. Is Authelia returning errors?
   → docker logs sandbox-authelia-1 --tail 50
   → Look for: "invalid credentials", "configuration error"

2. Did you set the password hash correctly?
   → Check: cat /opt/sandbox/authelia/users.yml
   → The hash should start with $argon2id$v=19$

3. Is the TOTP code wrong?
   → Make sure your phone's clock is correct (TOTP is time-sensitive)
   → Try waiting for the next code cycle (30 seconds)

4. Are you banned by rate limiting?
   → Authelia bans after 3 failed attempts for 5 minutes
   → Wait 5 minutes, or:
   → docker restart sandbox-authelia-1 (resets the ban)
```

### "Containers won't start"

```
1. Check Docker disk space:
   → docker system df
   → If disk is full: docker system prune (removes unused images/containers)

2. Check specific container:
   → docker logs sandbox-box1
   → Look for: image pull errors, OOM killed, port conflicts

3. Check compose file syntax:
   → cd /opt/sandbox/sandbox && docker compose config
   → This validates the YAML. If it errors, fix the syntax.

4. Network issues:
   → docker network ls
   → sandbox_net should exist
   → If missing: docker network create --subnet=172.30.0.0/24 sandbox_net
```

### "I changed something and now everything is broken"

```
1. What did you change? Check the changelog:
   → /opt/sandbox/changelog/changelog.jsonl (if Phase 6 is deployed)
   → Or: cd /opt/sandbox && git log --oneline (if Phase 2 is deployed)

2. Revert the last config change:
   → cd /opt/sandbox && git diff HEAD~1
   → cd /opt/sandbox && git checkout HEAD~1 -- <file-that-changed>
   → docker compose restart <affected-service>

3. If you don't know what changed:
   → cd /opt/sandbox && docker compose down
   → cd /opt/sandbox && docker compose up -d
   → This restarts everything with current configs

4. Nuclear option:
   → cd /opt/sandbox && docker compose down
   → git checkout HEAD~5 -- .  # go back 5 changes
   → docker compose up -d
```

### "I locked myself out of Authelia"

See SECURITY-MODEL.md → Lockout Prevention. Short version:
```bash
ssh root@<hub_ip>
# Reset password:
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'NewPassword'
# Copy hash into /opt/sandbox/authelia/users.yml
cd /opt/sandbox && docker compose restart authelia
```

---

## Recovery Procedures

### Full System Rebuild (Nuclear Option)

When to use: everything is so broken that fixing in place isn't worth it.

```bash
# From your local machine
cd terraform

# Destroy existing infrastructure
terraform destroy
# Type "yes"
# This deletes the hub, firewall, VPC, DNS records, everything

# Rebuild
terraform apply
# Type "yes"
# Wait for hub to boot and cloud-init to complete

# Re-set password
./scripts/set-password.sh 'YourPassword'

# SSH in and configure
ssh root@<new-hub-ip>
# Update users.yml with password hash
nano /opt/sandbox/authelia/users.yml
cd /opt/sandbox && docker compose restart authelia

# Deploy latest dashboard code
./scripts/deploy-dashboard.sh <new-hub-ip>
```

**What you keep**: All code (in git), all documentation, all Terraform configs.
**What you lose**: Container data (unless backed up), Authelia session data,
TOTP enrollment (you'll re-enroll), any manual changes on the hub that
weren't in git.

### Partial Recovery — Single Service

```bash
ssh root@<hub_ip>
cd /opt/sandbox

# Restart just one service
docker compose restart caddy      # proxy issues
docker compose restart authelia   # auth issues
docker compose restart dashboard  # dashboard issues

# Rebuild dashboard from scratch
docker compose build --no-cache dashboard
docker compose up -d dashboard
```

### DNS Emergency — Can't Resolve Domain

If DNS breaks, you can access the dashboard directly by IP:
1. SSH to hub
2. Get the Caddy container to serve on the IP address (temporary):
   ```bash
   # Add to Caddyfile temporarily:
   # :80 { reverse_proxy dashboard:8000 }
   docker compose restart caddy
   ```
3. Access http://<hub-ip> directly (no HTTPS, no auth — temporary only)
4. Fix DNS
5. Remove the temporary Caddyfile entry

---

## Maintenance Schedule

### Weekly
- [ ] Check disk space: `df -h` on hub
- [ ] Check Docker disk: `docker system df`
- [ ] Review Authelia logs for failed login attempts
- [ ] Verify SSH access works
- [ ] Destroy any on-demand droplets you're not using

### Monthly
- [ ] Run `apt update && apt upgrade` on hub (security patches)
- [ ] Update Docker images: `docker compose pull` in `/opt/sandbox`
- [ ] Review firewall rules: `ufw status`
- [ ] Check that backups exist and are recent
- [ ] Review changelog for patterns (are you making the same mistake?)

### Quarterly
- [ ] Rotate DigitalOcean API token
- [ ] Review Authelia user configuration
- [ ] Test full rebuild procedure (on a test domain/project)
- [ ] Review and update these docs based on actual experience

### On Change
- [ ] After any config change: verify the system still works
- [ ] After any Authelia change: verify you can still log in
- [ ] After any firewall change: verify SSH still works
- [ ] After any phase upgrade: run through the exit criteria
