# Deployment Guide

**Last Updated**: 2026-02-07  
**Phase**: 1 (Hub + Authentication)  
**Time**: 15-20 minutes  
**Cost**: $9.60/month

---

## Quick Start

1. Add wildcard DNS record in DigitalOcean
2. Create hub droplet with cloud-init script
3. Assign Reserved IP to hub
4. Complete web-based setup wizard
5. Log in with password + 2FA

---

## Prerequisites

Before deploying, ensure you have:

- [x] **DigitalOcean account** with 2FA enabled
- [x] **Recovery codes saved** (DO Panel → Account → Security)
- [x] **Reserved IP** (free when attached to droplet)
- [x] **Domain** (circlescorner.xyz) pointing to DO nameservers
- [x] **DO API token** (generate during setup)

---

## Step 1: Configure DNS

### 1.1: Add Wildcard Record

1. Go to https://cloud.digitalocean.com/networking/domains
2. Click **circlescorner.xyz**
3. Click **"Add Record"** → **"A"**
4. **Hostname**: `*` (asterisk only)
5. **Will Direct To**: Select your Reserved IP
6. **TTL**: 300
7. Click **"Create Record"**

### 1.2: Verify DNS

You should now have:
```
@    →  <reserved-ip>    # Root domain
*    →  <reserved-ip>    # All subdomains
```

---

## Step 2: Create VPC (If Needed)

If you don't already have `sandbox-vpc`:

1. Go to https://cloud.digitalocean.com/networking/vpc
2. Click **"Create VPC Network"**
3. **Name**: `sandbox-vpc`
4. **Region**: `Atlanta (atl1)`
5. **IP Range**: `10.100.0.0/16`
6. Click **"Create VPC Network"**

---

## Step 3: Create Hub Droplet

### 3.1: Start Creation

1. Go to https://cloud.digitalocean.com/droplets
2. Click **"Create"** → **"Droplets"**

### 3.2: Configure

**Region**: Atlanta (atl1) *or NYC1 if unavailable*

**Image**: Ubuntu 24.04 (LTS) x64

**Size**: $8/mo Premium Intel
- 1 GB RAM / 1 vCPU
- 35 GB SSD

**VPC Network**: sandbox-vpc

**SSH Key**: Select your existing key (or generate one)

**Backups**: ✅ Enable (+$1.60/mo)

**Hostname**: `sandbox-hub`

**Tags** (optional): `sandbox`, `hub`, `production`

### 3.3: Add Cloud-Init Script

1. Expand **"Advanced Options"**
2. Check **"Add Initialization scripts"**
3. Open `infra/cloud-init-phase1.yml` from this repo
4. **Select ALL** and copy
5. **Paste** into "User Data" box
6. Verify it starts with `#cloud-config`

### 3.4: Create

**Review**: 
- Region: atl1
- Size: $8/mo
- VPC: sandbox-vpc
- User data: ✅ Pasted

**Click**: "Create Droplet"

**Wait**: 1-2 minutes for droplet creation

---

## Step 4: Assign Reserved IP

1. Go to https://cloud.digitalocean.com/networking/reserved-ips
2. Find your Reserved IP
3. Click **"More"** → **"Reassign"**
4. Select **"sandbox-hub"**
5. Click **"Assign Reserved IP"**

**DNS now points to your new hub.**

---

## Step 5: Monitor Cloud-Init (3-5 minutes)

### 5.1: Access Console

1. DO Panel → **sandbox-hub** → **"Access"** → **"Launch Droplet Console"**
2. Browser terminal opens
3. Log in as `root` (with SSH key or DO-emailed password)

### 5.2: Watch Progress

```bash
tail -f /var/log/cloud-init-output.log
```

**You'll see**: Package installation, Docker setup, container builds

**When done**: `Cloud-init v. XX.X finished...`

Press **Ctrl+C** to exit

### 5.3: Verify

```bash
cat /opt/sandbox/status
```
**Should output**: `ready`

```bash
docker ps
```
**Should show 7 containers**:
- sandbox-caddy-1
- sandbox-authelia-1  
- sandbox-dashboard-1
- sandbox-box1
- sandbox-box2
- sandbox-box3
- sandbox-box4

---

## Step 6: Get Setup Token

Still in DO Console:

```bash
cat /opt/sandbox/setup-token.txt
```

**Copy this entire string** (32 hex characters)

Example: `7f3a92b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9`

---

## Step 7: Unlock Web Access (2 Hours)

Still in DO Console:

```bash
systemctl start setup-unlock
```

**Output**:
```
Unlocking ports 80/443 for 2 hours...
Ports unlocked until 2026-02-07T12:34:56-06:00
Complete setup at https://circlescorner.xyz before this time
```

**Ports 80 and 443 are now open for 2 hours.**

You can close DO Console now (keep tab available if needed).

---

## Step 8: Complete Setup Wizard

### 8.1: Visit Domain

On any device (iPhone, PC, etc):

1. Go to: **https://circlescorner.xyz**
2. If certificate warning: wait 60 seconds and refresh

**You should see**: "Sandbox Hub Setup" wizard

### 8.2: Fill Out Form

**Setup Token**  
Paste the token from Step 6

**Admin Email**  
Your email (becomes your username)  
Example: `your@email.com`

**Admin Password**  
Strong password you'll memorize  
This is your login password

**DigitalOcean API Token**  
Generate one now:
1. Open new tab: https://cloud.digitalocean.com/account/api/tokens
2. Click **"Generate New Token"**
3. Name: `Sandbox Hub API`
4. Scopes: ✅ Read, ✅ Write
5. Click **"Generate Token"**
6. **COPY IMMEDIATELY** (shown once)
7. Paste into wizard

**Click**: "Complete Setup"

### 8.3: Wait for Processing

The wizard will:
- Validate token
- Generate password hash (~10 seconds)
- Configure Authelia
- Update dashboard environment
- Restart services
- Delete setup token

**You'll see**: "Setup Complete!"

**Redirect**: Auto-redirects to Authelia login in 5 seconds

---

## Step 9: First Login

### 9.1: Enter Credentials

**Username**: The email you provided  
**Password**: The password you set

Click **"Sign in"**

### 9.2: Enroll 2FA

**You'll see**: "Two-Factor Authentication" page

**Choose method**:

**Option A: One-Time Password (TOTP)** ← Recommended for Phase 1
1. Click "One-Time Password"
2. Scan QR code with authenticator app
3. Enter 6-digit code
4. Click "Continue"

**Option B: Security Key (WebAuthn/Face ID)** ← Phase 1b will improve this
1. Click "Security Key"
2. Follow Face ID prompts on iPhone

### 9.3: You're In!

**Dashboard shows**:
- "Sandbox Hub Dashboard"
- "Setup complete!"
- Status: Caddy, Authelia, Dashboard, Containers [OK]

🎉 **Phase 1 deployment complete!**

---

## Verification Checklist

After deployment, verify:

- [ ] https://circlescorner.xyz loads (valid HTTPS)
- [ ] Login works (email + password + 2FA)
- [ ] Dashboard shows "Setup complete!"
- [ ] `docker ps` shows 7 containers (via DO Console)
- [ ] Mobile-friendly (readable on iPhone)
- [ ] DO Console breakglass access works

---

## What You Built

### Infrastructure

- **Hub Droplet**: sandbox-hub in atl1
  - Ubuntu 24.04
  - 1 GB RAM / 1 vCPU
  - $8/month
- **Backups**: Weekly snapshots (+$1.60/month)
- **Reserved IP**: Attached to hub (free)
- **VPC**: sandbox-vpc (free)
- **DNS**: circlescorner.xyz + wildcard (free)

**Total Cost**: $9.60/month

### Services

- **Caddy**: Reverse proxy with auto-HTTPS (Let's Encrypt)
- **Authelia**: Authentication (password + TOTP/WebAuthn)
- **Dashboard**: Flask web control panel
- **Sandbox Containers**: box1-box4 (Ubuntu 24.04)

### Security

- **HTTPS**: Valid certificate from Let's Encrypt
- **Password**: Argon2id hash (secure storage)
- **2FA**: TOTP or WebAuthn Face ID
- **Firewall**: SSH (22) + HTTP (80) + HTTPS (443) + VPC
- **Breakglass**: DO Console + SSH

---

## Troubleshooting

### "Can't access circlescorner.xyz"

**Check**:
1. DNS: https://dnschecker.org (enter circlescorner.xyz)
2. Reserved IP assigned: DO Panel → Reserved IPs
3. Ports unlocked: `systemctl status setup-unlock` (DO Console)
4. Caddy running: `docker ps | grep caddy` (DO Console)

**Fix**:
```bash
# In DO Console:
systemctl start setup-unlock
```

### "Certificate error"

**Wait 60 seconds** - Let's Encrypt takes time

Still failing?
```bash
# In DO Console:
docker logs sandbox-caddy-1
```
Look for ACME/Let's Encrypt errors

### "Invalid setup token"

**Token is case-sensitive**

Get it again:
```bash
# In DO Console:
cat /opt/sandbox/setup-token.txt
```
Copy-paste directly (no typos)

### "Setup timed out (2 hours expired)"

**Unlock again**:
```bash
# In DO Console:
systemctl start setup-unlock
```
New 2-hour window starts

### "Docker containers not running"

**Restart**:
```bash
# In DO Console:
cd /opt/sandbox && docker compose restart
```

Check logs:
```bash
docker compose logs
```

### "Complete failure - start over"

**Nuclear option**:
1. DO Panel → Destroy sandbox-hub
2. Create new droplet (repeat Step 3)
3. Reassign Reserved IP (repeat Step 4)
4. Proceed from Step 5

**You don't lose**: Reserved IP, DNS, or repo code

---

## Next Steps

### Phase 1b (Immediate)

Coming in next update:
- Proper Face ID enrollment from dashboard
- Responsive mobile UI improvements
- Container start/stop controls
- Worker droplet spawning

### Phase 2

Future enhancements:
- Config versioning (git on hub)
- Budget tracker
- Smart hibernation
- Security modes (Normal/Restricted/Lockdown)

---

## Support

**Documentation**:
- [System Overview](00-SYSTEM-OVERVIEW.md)
- [Architecture](01-ARCHITECTURE.md)
- [Security Model](02-SECURITY-MODEL.md)
- [Operations](04-OPERATIONS.md)

**DigitalOcean**:
- Docs: https://docs.digitalocean.com
- Support: https://cloud.digitalocean.com/support

**Breakglass**:
- DO Console: Always works (requires DO login)
- SSH: Port 22 always open (requires private key)
