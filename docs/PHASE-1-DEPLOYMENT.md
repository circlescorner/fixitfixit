# Phase 1 Deployment Guide

**Status**: Ready to execute
**Date**: 2026-02-07
**Prerequisites completed**: All critical questions answered

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Initial Setup Security Model](#initial-setup-security-model)
3. [Deployment Steps](#deployment-steps)
4. [Cross-Device Authentication Explained](#cross-device-authentication-explained)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Rollback Procedures](#rollback-procedures)

---

## Pre-Deployment Checklist

Complete these before creating the hub droplet:

- [ ] **CRITICAL**: Save DigitalOcean recovery codes
  - Go to cloud.digitalocean.com → Account → Security
  - Generate and download/screenshot recovery codes
  - Store somewhere safe (NOT only on your phone)
  
- [ ] Verify DNS configuration:
  - circlescorner.xyz A record → points to your Reserved IP
  - `*`.circlescorner.xyz A record → points to same Reserved IP
  - TTL: 300 seconds (5 minutes) for quick failover
  
- [ ] Verify region availability:
  - Log into DO panel
  - Try Create Droplet → Atlanta (atl1)
  - Confirm s-1vcpu-1gb ($8/mo) is available
  - If not available, fallback to NYC1
  
- [ ] Have your iPhone 16 ready with Safari
  - Face ID enabled and working
  - Not required for initial setup, but needed for Phase 1b

---

## Initial Setup Security Model

### Your Concern: "Exposing the system briefly while unsecured?"

**You're absolutely correct to be cautious.** Here's how we handle it:

### Option A: Two-Stage Bootstrap (RECOMMENDED)

**Stage 1: Locked-Down First Boot (2-3 minutes)**
```yaml
# Cloud-init creates the system but does NOT expose it to the web yet
# UFW is configured to block 80/443 until you explicitly unlock it
```

**Process:**
1. Droplet boots with UFW blocking all web traffic
2. System self-configures (Docker, containers, etc.)
3. You access via DO Console to verify everything is ready
4. You generate initial admin password hash via DO Console
5. You configure Authelia with the hash
6. You manually enable UFW rules for 80/443
7. NOW the system is exposed — but already fully secured

**Advantage**: Zero window of vulnerability. System is never exposed while
insecure.

**Disadvantage**: Requires DO Console access for first-time setup (about
5-10 minutes of terminal work).

### Option B: Auto-Setup Wizard with Time-Limited Token (SIMPLER)

**Process:**
1. Cloud-init generates a random 32-character setup token
2. Token is written to `/opt/sandbox/setup-token.txt`
3. System starts with UFW allowing 80/443
4. First visitor to https://circlescorner.xyz sees setup wizard
5. Wizard requires the setup token (which you retrieve via DO Console)
6. Token is valid for 60 minutes, then auto-expires
7. After setup completes, token is deleted and wizard is disabled

**The security window:**
- **60 minutes** where someone COULD access the setup page
- But they need the random token, which is only visible via DO Console
- Token is 32 characters of random hex (like: `7f3a...b9c2`)
- After 60 minutes OR after setup completes, wizard is permanently disabled

**Advantage**: Simpler — no manual Authelia configuration needed.

**Risk**: Theoretical 60-minute window where an attacker who somehow
guessed the token could hijack your setup. In practice, the token has
2^128 possible values, making guessing impossible.

### Option C: Hybrid Approach (MOST SECURE + SIMPLE)

**Process:**
1. Cloud-init blocks 80/443 initially
2. Cloud-init writes setup token to `/opt/sandbox/setup-token.txt`
3. You access DO Console, read the token, note it down
4. You run a single command in DO Console: `systemctl start setup-unlock`
5. This enables UFW rules for 80/443 for **exactly 60 minutes**
6. You visit the domain, enter the token, complete setup
7. After setup OR after 60 minutes, ports auto-lock again (if not needed)
8. Normal operations (with Authelia protection) work from then on

**Advantage**: 
- No vulnerability window until YOU explicitly unlock it
- Token is time-limited and single-use
- You control when exposure begins

**This is the recommended approach.**

---

## Deployment Steps

### Step 1: Create VPC (if doesn't exist)

**DO Panel → Networking → VPC → Create VPC**
- Name: `sandbox-vpc`
- Region: `atl1` (or `nyc1` if unavailable)
- IP range: `10.100.0.0/16`
- Description: "Private network for sandbox infrastructure"

### Step 2: Generate Cloud-Init Script

The cloud-init script is in the repo at `infra/cloud-init-phase1.yml`.

**What it does:**
1. Installs Docker, git, curl, jq, ufw
2. Configures UFW (initially blocks 80/443 for security)
3. Clones this GitHub repo to `/opt/sandbox`
4. Builds and starts Docker containers:
   - Caddy (reverse proxy)
   - Authelia (authentication)
   - Dashboard (Flask app)
   - box1-box4 (sandbox containers)
5. Generates random setup token
6. Creates systemd service for time-limited unlock
7. Writes "ready" to `/opt/sandbox/status`

### Step 3: Create Hub Droplet

**DO Panel → Droplets → Create Droplet**

**Configuration:**
- **Region**: atl1 (or nyc1 fallback)
- **Image**: Ubuntu 24.04 LTS x64
- **Size**: s-1vcpu-1gb ($8/mo)
  - 1 vCPU, 1GB RAM, 35GB SSD
  - Perfect for the hub (always-on control plane)
- **VPC**: sandbox-vpc
- **Authentication**: Select your SSH key (or create one)
  - **IMPORTANT**: Save the private key in a secure location
- **Additional options**:
  - [x] Enable backups (+$1.60/mo)
  - [ ] IPv6 (optional, not required)
  - [ ] Monitoring (free, optional)
- **User Data**: Paste contents of `infra/cloud-init-phase1.yml`
- **Hostname**: sandbox-hub
- **Tags**: sandbox, hub, production

**Click "Create Droplet"**

### Step 4: Assign Reserved IP

**DO Panel → Networking → Reserved IPs**
1. Find your existing Reserved IP
2. Click "More → Assign to Droplet"
3. Select: sandbox-hub
4. Confirm

DNS now points to your new hub.

### Step 5: Wait for Cloud-Init

This takes 3-5 minutes. You can monitor progress:

**DO Panel → Droplets → sandbox-hub → Console** (the "Access" dropdown)

In the console:
```bash
# Check cloud-init status
tail -f /var/log/cloud-init-output.log

# When you see "Cloud-init complete", check:
cat /opt/sandbox/status
# Should say: "ready"
```

### Step 6: Retrieve Setup Token

Still in DO Console:
```bash
cat /opt/sandbox/setup-token.txt
```

Copy this token. It looks like: `7f3a92b1c4d5e6f7a8b9c0d1e2f3a4b5`

### Step 7: Unlock Web Access (Time-Limited)

Still in DO Console:
```bash
systemctl start setup-unlock
```

This opens ports 80/443 for **exactly 60 minutes**. A countdown file is
created at `/opt/sandbox/unlock-expires-at.txt`.

### Step 8: Complete Setup Wizard

On your iPhone (or any device):

1. Open Safari
2. Go to: https://circlescorner.xyz
3. You'll see the first-time setup wizard

**Wizard prompts:**
- **Setup Token**: Paste the token from Step 6
- **Admin Email**: Your email (used as username)
- **Admin Password**: Strong password (you'll memorize this)
- **Confirm Password**: Same password
- **DigitalOcean API Token**: Your DO token with read/write access
  - Generate this at: DO Panel → API → Tokens → Generate New Token
  - Name it: "Sandbox Hub Token"
  - Scopes: Read + Write
  - Copy the token immediately (it won't be shown again)

Click **"Complete Setup"**

The wizard will:
1. Hash your password with Argon2id
2. Configure Authelia with your credentials
3. Store the DO token in the dashboard environment
4. Delete the setup token
5. Disable the wizard permanently
6. Redirect you to the login page

### Step 9: First Login (Password-Only)

You're now at the Authelia login page.

**Enter:**
- Username: your email
- Password: the password you just set

Click **"Sign in"**

You're now at the dashboard! 🎉

**Note**: Face ID (WebAuthn) enrollment happens in Phase 1b, which is the
very next step after this completes.

### Step 10: Enroll Face ID (Phase 1b — Immediate Follow-Up)

Once logged in to the dashboard:

1. Click your profile icon (top right)
2. Click "Security Settings"
3. Click "Enroll Face ID"
4. Safari will show the WebAuthn prompt
5. **On iPhone**: Face ID prompt appears → look at phone → done
6. **On work PC** (cross-device flow):
   - Click "Enroll Face ID"
   - Browser shows "Use your phone"
   - Scan QR code with iPhone camera
   - Face ID prompt on iPhone → verify
   - PC browser: "Enrolled successfully"

Now Face ID is your primary 2FA method.

### Step 11: Test Face ID Login

1. Log out from the dashboard
2. Log in again:
   - Enter password
   - Face ID prompt appears
   - Verify with Face ID
   - You're in

**Optionally**: Enroll TOTP as backup
1. Security Settings → "Enroll TOTP Backup"
2. Scan QR code with authenticator app
3. Enter code to confirm

---

## Cross-Device Authentication Explained

### The Vision: "Login from any PC, verify with iPhone"

You asked for this specifically:
> "I need a way I can login from any computer, that will trigger some
> mechanism for me to verify and complete the process from my phone, which
> generates a code I can type into the PC browser."

**Good news: WebAuthn does exactly this out of the box.**

### How It Works (Technical)

1. **You're at a random PC** (work, library, friend's house)
2. Go to circlescorner.xyz, enter your password
3. Browser shows: "Second factor required"
4. Click **"Use your phone as authenticator"**
5. **QR code appears** on the PC screen
6. **Scan with iPhone camera** (just like scanning a regular QR code)
7. **Safari opens automatically** with a WebAuthn prompt
8. **Face ID prompt** appears on your iPhone
9. **Verify with Face ID**
10. iPhone transmits cryptographic signature back to the PC
11. **PC browser: "Authenticated"** → you're logged in

**What's happening behind the scenes:**
- The QR code contains a Bluetooth pairing signal
- Your iPhone and the PC establish a short-range BLE connection
- The authentication challenge is sent from PC → iPhone via BLE
- Your iPhone signs the challenge with its private key (after Face ID)
- Signature is sent back: iPhone → PC → server
- Server verifies the signature and grants access

**Privacy/Security notes:**
- The private key **never leaves your iPhone**
- The PC only sees a cryptographic signature (can't be reused)
- Bluetooth is only active during the 10-second auth process
- No data about your Face ID or biometrics is transmitted
- The connection is end-to-end encrypted

### Alternative: TOTP Code (If Bluetooth Unavailable)

If the PC has Bluetooth disabled (some corporate machines do):

1. Enter password on PC
2. Click "Use TOTP backup" instead of WebAuthn
3. Open authenticator app on iPhone
4. Copy the 6-digit code
5. Type it into the PC browser
6. You're in

This is why we enroll TOTP as a backup.

### What If You Lose Your iPhone?

**Option 1**: Use TOTP from another device
- If you backed up your authenticator app (Authy, 1Password)
- Or if you have TOTP on a second device

**Option 2**: Use iCloud Keychain (if enabled)
- Your WebAuthn credential syncs to your other Apple devices
- Log in from iPad or Mac with Face ID or Touch ID

**Option 3**: DO Console breakglass
- Access the hub via DO Console
- Reset your password manually
- Generate new password hash
- Update Authelia users.yml
- Log in with new password
- Re-enroll Face ID

**This is why saving DO recovery codes is CRITICAL.**

---

## Post-Deployment Verification

After setup completes, verify these:

- [ ] https://circlescorner.xyz loads (HTTPS with valid certificate)
- [ ] Login works with password + Face ID
- [ ] Dashboard home page shows:
  - 4 sandbox containers (box1-box4) — status: Running
  - Hub droplet info (IP, region, size)
  - "Create Worker" button visible
- [ ] DO Console access works:
  - DO Panel → sandbox-hub → Console
  - Get a root prompt
  - Type: `docker ps` → see all containers running
- [ ] Mobile responsiveness:
  - Dashboard usable on iPhone (no tiny text, buttons work)
  - Face ID enrollment works from iPhone Safari
  - Navigation menu accessible

### Expected State After Phase 1

**Running infrastructure:**
- 1 droplet: sandbox-hub (atl1, s-1vcpu-1gb, $8/mo)
- 1 Reserved IP: attached to hub (free when attached)
- 1 VPC: sandbox-vpc (free)
- 1 DNS zone: circlescorner.xyz at DO (free)

**Backups enabled:**
- Daily hub backups (+$1.60/mo)
- Retention: 4 weekly backups

**Total monthly cost: ~$9.60**

**Services running on hub:**
- Caddy: HTTPS reverse proxy
- Authelia: Authentication (password + WebAuthn)
- Dashboard: Flask control panel
- 4 sandbox containers: Ubuntu 24.04, idle

**Authentication configured:**
- Password (Argon2id hash)
- Face ID (WebAuthn, iPhone Secure Enclave)
- TOTP backup (optional, recommended)

**Breakglass access:**
- DO Console (requires DO account + recovery codes)
- SSH (requires private key, port 22 open)

---

## Rollback Procedures

### Scenario 1: Setup fails during cloud-init

**Symptoms**: Status never shows "ready", cloud-init-output.log has errors

**Fix:**
1. DO Panel → Destroy droplet
2. Fix the cloud-init.yml script
3. Create new droplet with updated script
4. Reassign Reserved IP

**No data lost** — code is in GitHub.

### Scenario 2: Setup wizard doesn't appear

**Fix via DO Console:**
```bash
# Check setup-token exists
cat /opt/sandbox/setup-token.txt

# Check UFW status
ufw status

# If ports are blocked:
systemctl start setup-unlock

# Check setup wizard is enabled
docker logs sandbox-dashboard-1
```

### Scenario 3: Can't access DO Console

**Symptoms**: DO account locked, 2FA not working

**Fix:**
1. Use DO recovery codes (this is why Q14 was critical)
2. Log into DO account with recovery code
3. Access Console
4. Fix whatever broke

**If you don't have recovery codes**: Contact DO support with account
verification info. This will take days.

### Scenario 4: Face ID enrollment fails

**Temporary workaround**: Use TOTP only
- Enroll TOTP as backup
- Use TOTP codes for now
- Debug Face ID enrollment later (check Authelia logs)

**Permanent fix**: Investigate Authelia WebAuthn config
```bash
# Via DO Console:
docker logs sandbox-authelia-1
# Look for WebAuthn-related errors
```

### Scenario 5: Everything is completely broken

**Nuclear option:**
1. DO Panel → Destroy hub droplet
2. Reserved IP remains (still points to circlescorner.xyz)
3. Create brand new droplet with fresh cloud-init
4. Reassign Reserved IP
5. Start over from Step 8 (setup wizard)

**Your safety net:**
- Code is in GitHub
- Reserved IP survives
- DNS config survives
- Only lost data: anything created in the dashboard that wasn't saved

---

## Next Steps After Phase 1

Once Phase 1 is verified and working:

**Phase 1b (immediate follow-up):**
- Face ID enrollment (if not done yet)
- Mobile UI polish (ensure full desktop functionality on iPhone)
- Dashboard mobile testing

**Phase 2 (next major step):**
- Config versioning (git on hub)
- Config history view in dashboard
- Rollback capability from dashboard

**Phase 3 (cost control):**
- Budget tracker
- Smart hibernation for workers
- Cost estimator before spawning

**Phase 4 (security):**
- Security mode switcher (Normal/Restricted/Lockdown)
- IP allowlisting
- Changelog and undo

You're following the system perfectly. Your questions showed excellent
attention to security details. Ready to begin Phase 1 deployment.
