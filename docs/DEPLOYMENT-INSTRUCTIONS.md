# Phase 1 Deployment - Step-by-Step Instructions

**Status**: Ready to execute NOW
**Time estimate**: 30-45 minutes total
**Your setup**: 2-hour unlock window (Option C - Hybrid Security)

---

## Overview

You'll create the hub droplet from the DigitalOcean web panel, it will self-configure, then you'll complete a web-based setup wizard. Everything happens from your browser.

---

## Step 2: Create VPC Network

**Only do this if you don't already have a VPC named `sandbox-vpc`.**

1. Go to https://cloud.digitalocean.com/networking/vpc
2. Click **"Create VPC Network"**
3. **Name**: `sandbox-vpc`
4. **Region**: `Atlanta (atl1)`
5. **IP range**: `10.100.0.0/16` (default is fine)
6. **Description**: "Private network for sandbox infrastructure"
7. Click **"Create VPC Network"**

**If you already have sandbox-vpc**: Skip this step.

---

## Step 3: Create the Hub Droplet

This is the main step. You'll create the droplet and paste in the cloud-init script.

### 3.1: Start Droplet Creation

1. Go to https://cloud.digitalocean.com/droplets
2. Click **"Create"** → **"Droplets"**

### 3.2: Choose Configuration

**Region:**
- Select **Atlanta (atl1)**
- If atl1 is unavailable, use **New York (nyc1)**

**Image:**
- Click **"OS"** tab
- Select **Ubuntu 24.04 (LTS) x64**

**Size:**
- Click **"Shared CPU"** tab (if not already selected)
- Under **"Premium Intel"**, select **$8/mo** option:
  - 1 GB RAM / 1 vCPU
  - 35 GB SSD
  - 1000 GB transfer

**VPC Network:**
- Under "Select VPC network", choose **sandbox-vpc**
- If you see "Default VPC" only, you need to create sandbox-vpc first (see Step 2)

### 3.3: Authentication

**SSH Key:**
- If you have an SSH key in DO: Select it
- If you don't: Click **"New SSH Key"**
  - You'll need to generate one - let me know if you need help with this
  - For now, you can use password auth (less secure but works)
  - **Important**: If using password, DO will email you the root password

**For this guide, I'll assume you're using an SSH key you already have.**

### 3.4: Finalize Details

**Hostname:**
- Enter: `sandbox-hub`

**Tags:**
- Add: `sandbox`, `hub`, `production` (optional but recommended)

**Enable Backups:**
- ✅ **Check this box** (+$1.60/month)
- Gives you automatic weekly snapshots

**Advanced Options** (expand this section):
- ✅ **Check "Add Initialization scripts (free)"**
- This reveals a text box called **"Enter user data here..."**

### 3.5: Paste Cloud-Init Script

**This is the critical step:**

1. Open the file I created: `infra/cloud-init-phase1.yml`
2. **Select ALL the content** (Ctrl+A or Cmd+A)
3. **Copy it** (Ctrl+C or Cmd+C)
4. **Paste it** into the "User data" text box in the DO panel

**The text box should now contain the entire cloud-init script (starts with `#cloud-config`).**

### 3.6: Review and Create

**Review your settings:**
- Region: atl1 (or nyc1)
- Image: Ubuntu 24.04 LTS
- Size: $8/mo (1GB/1CPU)
- VPC: sandbox-vpc
- Backups: Enabled
- User data: ✅ Pasted

**Monthly cost shown**: Should be ~$9.60/mo ($8 droplet + $1.60 backups)

**Click the big green "Create Droplet" button.**

---

## Step 4: Wait for Droplet Creation (1-2 minutes)

You'll see a progress bar. When it completes:
- Droplet status changes to "Active" (green dot)
- You'll see the droplet's public IP address

**Do NOT visit the IP yet** - the system is still configuring itself.

---

## Step 5: Assign Your Reserved IP

Now we attach your Reserved IP to the new droplet.

1. Go to https://cloud.digitalocean.com/networking/reserved-ips
2. Find your Reserved IP (should be listed there)
3. Click the **"More"** dropdown (three dots) → **"Reassign"**
4. Select **"sandbox-hub"** from the droplet list
5. Click **"Assign Reserved IP"**

**Your domain (circlescorner.xyz) now points to this new droplet.**

---

## Step 6: Wait for Cloud-Init (3-5 minutes)

The droplet is now running, but cloud-init is installing packages and configuring everything.

**You can monitor progress:**

1. In DO panel, go to your **sandbox-hub** droplet
2. Click **"Access"** dropdown → **"Launch Droplet Console"**
3. A browser-based terminal will open
4. Log in (if prompted):
   - Username: `root`
   - Password: Your SSH key (or the password DO emailed you)

5. Run this command to watch cloud-init progress:
   ```bash
   tail -f /var/log/cloud-init-output.log
   ```

**You'll see a lot of text scrolling.** This is normal. It's installing Docker, pulling images, building containers, etc.

**When you see:**
```
Setup complete. Read /opt/sandbox/README-FIRST-BOOT.txt for next steps.
```

**Cloud-init is done!** Press Ctrl+C to stop the tail command.

---

## Step 7: Verify System Status

Still in the DO Console, run these commands:

```bash
# Check status file
cat /opt/sandbox/status
```
**Should output:** `ready`

```bash
# Check Docker containers
docker ps
```
**Should show 6 containers running:**
- sandbox-caddy-1
- sandbox-authelia-1
- sandbox-dashboard-1
- sandbox-box1
- sandbox-box2
- sandbox-box3
- sandbox-box4

**If you see all 6 containers:** ✅ System is ready!

---

## Step 8: Retrieve Setup Token

Still in DO Console:

```bash
cat /opt/sandbox/setup-token.txt
```

**You'll see a 32-character hex string like:**
```
7f3a92b1c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9
```

**Copy this entire string.** You'll need it in the next step.

**Keep the DO Console tab open** - you'll need it for the next command.

---

## Step 9: Unlock Ports (2-Hour Window)

Still in DO Console, run:

```bash
systemctl start setup-unlock
```

**You'll see:**
```
Unlocking ports 80/443 for 2 hours...
Ports unlocked until 2026-02-07T12:34:56-06:00
Complete setup at https://circlescorner.xyz before this time
```

**Ports 80 and 443 are now open for the next 2 hours.**

You can close the DO Console now (but keep the tab available in case you need it).

---

## Step 10: Visit the Setup Wizard

**On your iPhone (or any device):**

1. Open Safari (or any browser)
2. Go to: **https://circlescorner.xyz**

**What you should see:**
- A page titled "Sandbox Hub Setup"
- A form with 4 fields

**If you see a certificate warning:**
- This is normal on first access (Let's Encrypt takes 30-60 seconds)
- Wait 1 minute and refresh
- Or click "Advanced" → "Proceed anyway"

---

## Step 11: Complete the Setup Wizard

Fill out the form:

### Setup Token
**Paste** the token from Step 8 (the 32-character hex string)

### Admin Email
Your email address (used as username)
Example: `your@email.com`

### Admin Password
A strong password you'll memorize
Example: `MySecure!Password123`

**You'll use this password to log in every time.**

### DigitalOcean API Token

You need to generate this:

1. Open a new tab: https://cloud.digitalocean.com/account/api/tokens
2. Click **"Generate New Token"**
3. **Token name**: `Sandbox Hub API`
4. **Scopes**: 
   - ✅ Read
   - ✅ Write
5. Click **"Generate Token"**
6. **IMMEDIATELY COPY THE TOKEN** - it won't be shown again!
7. Paste it into the setup wizard form

**The token looks like:** `dop_v1_abc123...xyz789`

---

## Step 12: Submit and Wait

Click **"Complete Setup"**

**The wizard will:**
1. Validate your setup token
2. Generate a password hash (takes ~10 seconds)
3. Configure Authelia with your credentials
4. Update the dashboard with your DO token
5. Restart Authelia
6. Delete the setup token
7. Show you a success message

**You'll see:** "✅ Setup Complete!"

**You'll be automatically redirected to the Authelia login page in 5 seconds.**

---

## Step 13: First Login

You're now at the Authelia login screen.

**Enter:**
- **Username**: The email you provided in the wizard
- **Password**: The password you set in the wizard

Click **"Sign in"**

**You'll see:** The Authelia "Two-Factor Authentication" page

**For now:** Click **"Not registered yet? Register now"**

**Choose a 2FA method:**
- **One-Time Password** (TOTP) - Use your phone's authenticator app
- **Security Key** (WebAuthn/Face ID) - Phase 1b will add this properly

**For Phase 1, use TOTP:**
1. Click "One-Time Password"
2. Scan the QR code with Google Authenticator, Authy, or 1Password
3. Enter the 6-digit code
4. Click "Continue"

**You're now logged in!** 🎉

---

## Step 14: Verify Dashboard

You should now see the Sandbox Dashboard:

**Expected content:**
- Title: "🎉 Sandbox Hub Dashboard"
- "Setup complete! You are authenticated via Authelia."
- Status showing: Caddy ✓, Authelia ✓, Dashboard ✓, Containers ✓

**If you see this:** Phase 1 is successfully deployed!

---

## Step 15: Post-Deployment Verification

Let's verify everything is working:

### 15.1: Check Containers (from Dashboard)

The dashboard should show Phase 1 is running. 

**To verify from DO Console:**
```bash
docker ps
```
All 7 containers should be running (caddy, authelia, dashboard, box1-4).

### 15.2: Test Mobile Access

On your iPhone:
- The dashboard should be readable (not tiny text)
- Buttons should be touch-friendly
- You should be able to scroll and navigate

### 15.3: Test Logout/Login

1. Log out from the dashboard
2. Log back in:
   - Enter your email and password
   - Enter your TOTP code
   - You should get back in

### 15.4: Verify Breakglass Access

1. Go back to DO panel
2. Open the Console for sandbox-hub
3. Verify you can get a root shell

**This is your emergency access if something breaks.**

---

## What You've Deployed

### Running Infrastructure:
- ✅ Hub droplet in atl1: $8/mo
- ✅ Backups enabled: +$1.60/mo
- ✅ Reserved IP attached: $0 (free)
- ✅ VPC network: $0 (free)
- **Total: $9.60/month**

### Services Running:
- ✅ **Caddy**: Reverse proxy with auto-HTTPS
- ✅ **Authelia**: Authentication (password + TOTP)
- ✅ **Dashboard**: Web control panel
- ✅ **4 Sandbox containers**: box1-box4 (Ubuntu 24.04)

### Security:
- ✅ HTTPS with valid Let's Encrypt certificate
- ✅ Password authentication (Argon2id hash)
- ✅ TOTP 2FA (via authenticator app)
- ✅ Ports 80/443 now stay open (protected by Authelia)
- ✅ SSH port 22 open (for breakglass)
- ✅ DO Console access verified

---

## Next Steps (Phase 1b - Immediate Follow-Up)

The next update will add:

1. **Face ID (WebAuthn)** enrollment from the dashboard
2. **Better mobile UI** (full responsive design)
3. **Container management** (start/stop/restart from dashboard)
4. **Basic worker spawning** (create on-demand droplets)

**For now:** Phase 1 core infrastructure is complete and secured.

---

## Troubleshooting

### "I can't access circlescorner.xyz"

**Check:**
1. DNS propagation: https://dnschecker.org (enter circlescorner.xyz)
2. Reserved IP is assigned to sandbox-hub (DO panel → Reserved IPs)
3. Ports are unlocked: `systemctl status setup-unlock` in DO Console
4. Caddy is running: `docker ps | grep caddy` in DO Console

### "Certificate error / Not secure"

**Wait 60 seconds and refresh.** Let's Encrypt takes time on first boot.

If it persists:
```bash
# In DO Console:
docker logs sandbox-caddy-1
```
Look for errors.

### "Invalid setup token"

**The token is case-sensitive.** Make sure you copied it exactly:
```bash
# In DO Console:
cat /opt/sandbox/setup-token.txt
```
Copy-paste it directly.

### "Setup timed out after 2 hours"

**Unlock again:**
```bash
# In DO Console:
systemctl start setup-unlock
```
You get another 2 hours.

### "Docker containers aren't running"

**Restart them:**
```bash
# In DO Console:
cd /opt/sandbox && docker compose restart
```

### "I'm completely stuck"

**Nuclear option (rebuild from scratch):**
1. DO panel → Destroy sandbox-hub droplet
2. Create a new droplet (repeat Step 3)
3. Reassign Reserved IP
4. Start over from Step 6

**Your Reserved IP and DNS survive.** You just lose this droplet.

---

## You're Done!

🎉 **Phase 1 is complete!**

You now have:
- A secure, always-on hub at your domain
- Web-based authentication with 2FA
- Container infrastructure ready for projects
- Breakglass access if anything breaks

**When you're ready for Phase 1b** (Face ID, better UI, worker spawning), let me know!
