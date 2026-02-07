# Phase 1 Deployment - Quick Reference Card

## DNS Wildcard (DONE ✓)
You added: `*` → Your Reserved IP in DO DNS

---

## Files You Need

1. **DEPLOYMENT-INSTRUCTIONS.md** ← Full step-by-step guide
2. **cloud-init-phase1.yml** ← Paste this into DO droplet creation

---

## Quick Checklist

### Before You Start:
- [✓] DO recovery codes saved
- [✓] DNS wildcard added
- [✓] Reserved IP ready
- [ ] Read DEPLOYMENT-INSTRUCTIONS.md

### Deployment Steps (Summary):
1. ✅ Create VPC: `sandbox-vpc` in atl1
2. ✅ Create Droplet:
   - Ubuntu 24.04, $8/mo size
   - Paste cloud-init-phase1.yml in User Data
   - Enable backups
3. ✅ Assign Reserved IP to new droplet
4. ⏳ Wait 3-5 min for cloud-init
5. 🔑 Get token: `cat /opt/sandbox/setup-token.txt` (DO Console)
6. 🔓 Unlock: `systemctl start setup-unlock` (DO Console)
7. 🌐 Visit: https://circlescorner.xyz
8. 📝 Complete setup wizard
9. 🎉 Login with your credentials

---

## Important Commands (DO Console)

```bash
# Watch cloud-init progress
tail -f /var/log/cloud-init-output.log

# Check if ready
cat /opt/sandbox/status

# Get setup token
cat /opt/sandbox/setup-token.txt

# Unlock ports for 2 hours
systemctl start setup-unlock

# Check Docker containers
docker ps

# Restart all services
cd /opt/sandbox && docker compose restart
```

---

## What You'll Create

**Droplet**: sandbox-hub
- Region: atl1
- Size: 1GB/1CPU ($8/mo)
- OS: Ubuntu 24.04
- VPC: sandbox-vpc
- Backups: Enabled (+$1.60/mo)

**Domain**: https://circlescorner.xyz
- Points to Reserved IP
- Auto HTTPS via Let's Encrypt

**Services**:
- Caddy (reverse proxy)
- Authelia (authentication)
- Dashboard (control panel)
- box1-box4 (sandbox containers)

---

## Security Model (Option C - Hybrid)

1. **Droplet boots**: Ports 80/443 BLOCKED
2. **You unlock**: Via DO Console (2-hour window)
3. **You setup**: Enter token + credentials via web
4. **System locks**: Token deleted, Authelia protects site
5. **Daily use**: Login with password + TOTP

**Breakglass**: DO Console always works

---

## Setup Wizard Inputs

You'll need:
1. **Setup Token**: From DO Console (`cat /opt/sandbox/setup-token.txt`)
2. **Your Email**: Becomes your username
3. **Your Password**: For logging in (strong!)
4. **DO API Token**: Generate at cloud.digitalocean.com/account/api/tokens
   - Scopes: Read + Write
   - Copy immediately (shown once)

---

## Time Estimates

- VPC creation: 10 seconds
- Droplet creation: 1-2 minutes
- Cloud-init: 3-5 minutes
- Setup wizard: 2-3 minutes
- **Total: 10-15 minutes** (if everything goes smoothly)

---

## Cost Breakdown

**Monthly**:
- Hub: $8.00
- Backups: $1.60
- Reserved IP: $0 (free when attached)
- VPC: $0 (free)
- **Total: $9.60/month**

**Hourly** (while building):
- $0.012/hour (~$0.20 for today's deployment)

---

## Success Criteria

After deployment, you should have:

✅ https://circlescorner.xyz loads (valid HTTPS)
✅ Login works (email + password + TOTP)
✅ Dashboard shows "Setup complete!"
✅ 7 Docker containers running
✅ DO Console breakglass access works
✅ Mobile-friendly (readable on iPhone)

---

## If Something Goes Wrong

**Problem**: Can't access domain
**Fix**: Check DNS at dnschecker.org, verify Reserved IP assigned

**Problem**: Certificate error
**Fix**: Wait 60 seconds, refresh (Let's Encrypt needs time)

**Problem**: Invalid setup token
**Fix**: Copy token exactly from DO Console (case-sensitive)

**Problem**: Setup timed out
**Fix**: Run `systemctl start setup-unlock` again (new 2-hour window)

**Problem**: Everything is broken
**Fix**: Destroy droplet, create new one, reassign Reserved IP, try again

---

## After Phase 1 Success

**You'll have:**
- Secure hub accessible from anywhere
- Web-based control panel
- Container infrastructure ready
- 2FA authentication working

**Next (Phase 1b):**
- Face ID enrollment
- Better mobile UI
- Container management from dashboard
- Worker droplet spawning

---

## Support Resources

- **Full Guide**: DEPLOYMENT-INSTRUCTIONS.md
- **DO Docs**: docs.digitalocean.com
- **This Project Docs**: /docs folder in your repo

---

**You're ready! Follow DEPLOYMENT-INSTRUCTIONS.md step-by-step.**
