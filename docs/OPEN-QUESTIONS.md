# Open Questions

**Document Status**: Living document — remove questions as they're answered,
add new ones as they arise. Move answered questions to the "Resolved" section
at the bottom.

---

## Questions I Need You to Answer

These are decisions I cannot make for you. They affect the system design
and need your input before we can proceed with certain phases.

---

### Q1: What domain registrar are you using for circlescorner.xyz?

**Why it matters**: If DNS is managed by DigitalOcean, we can use Terraform
to create DNS records automatically (`manage_dns = true`). If DNS is at
Cloudflare, Namecheap, or another registrar, you'll need to manually create
A records pointing to the hub IP, or we need to add that provider to Terraform.

**Options**:
- a) DNS is at DigitalOcean (set `manage_dns = true`)
- b) DNS is at another registrar (which one?) — manual A records
- c) DNS is at Cloudflare — could add Cloudflare Terraform provider

---

### Q2: Do you have a WebAuthn-capable device?

**Why it matters**: Phase 4 requires hardware-bound authentication. The
options are:

- **YubiKey** (~$25-50 USD): Physical USB security key. Gold standard.
  Works on any computer with a USB port. Recommended: YubiKey 5 NFC
  (also works with phones).
- **Laptop fingerprint reader**: If your laptop has one (Windows Hello,
  Touch ID), it can serve as a WebAuthn authenticator.
- **Phone biometric**: Your phone can act as a roaming authenticator
  via Bluetooth proximity, but this is more finicky.

**My recommendation**: Buy a YubiKey 5 NFC. It's $50 and it's the most
reliable, portable, and secure option. It also works for SSH key auth
(stores SSH keys on the device), which gives you a hardware-bound SSH key.

**Your answer**: Which device(s) do you have or are willing to get?

---

### Q3: What is your current SSH key situation?

**Why it matters**: SSH is the breakglass access path. I need to understand
what you have:

- Do you have an existing SSH key pair? Where? (laptop, another machine?)
- Is it backed up anywhere?
- Is it already registered with DigitalOcean?
- Do you use an SSH agent or passphrase?

If you don't have one, the setup script generates one. But you need to
understand where it is and back it up.

---

### Q4: What DigitalOcean region do you prefer?

**Why it matters**: Latency. Pick the region closest to where you physically are.

- `nyc1`, `nyc3` — New York (US East)
- `sfo3` — San Francisco (US West)
- `lon1` — London (Europe)
- `ams3` — Amsterdam (Europe)
- `sgp1` — Singapore (Asia-Pacific)
- `blr1` — Bangalore (India)
- `tor1` — Toronto (Canada)
- `fra1` — Frankfurt (Europe)
- `syd1` — Sydney (Australia)

Current default is `nyc1`. Is that correct for you?

---

### Q5: What's your budget tolerance for on-demand droplets?

**Why it matters**: The dashboard currently allows creating any size
droplet up to 4vCPU/8GB ($48/mo). Should we:

- a) Keep it as-is (you manage costs manually)
- b) Add a spending limit (max N droplets, max $ per month)
- c) Add an auto-destroy timer (droplets destroyed after N hours if
  you forget)

**Recommended**: Option (c) with a configurable default of 8 hours.
You can override per droplet. This prevents forgotten $48/month
droplets running for weeks.

---

### Q6: Do you want the hub accessible via IP address or domain only?

**Why it matters**: Currently, Caddy is configured to serve
`circlescorner.xyz` and `*.circlescorner.xyz`. If DNS breaks, you
can't reach the dashboard via the domain. Options:

- a) **Domain only** (current): Clean but fragile if DNS breaks
- b) **Domain + IP fallback**: Caddy also serves on the IP address
  (HTTP only, no TLS), with a simple auth page. Less secure but
  always reachable.
- c) **Domain + WireGuard IP**: After Phase 3, you can always reach
  the dashboard via the WireGuard IP (10.200.0.1), bypassing DNS
  entirely.

**Recommended**: (a) for now, (c) after Phase 3. The WireGuard
tunnel makes the IP fallback unnecessary.

---

### Q7: How do you want to handle the DO API token in the dashboard?

**Why it matters**: Currently, the DO API token is passed as an
environment variable to the dashboard container. This means:
- It's visible in `docker inspect`
- It's in the compose file (cloud-init embeds it)
- The dashboard has full API access to your DO account

**Options**:
- a) Keep as-is (acceptable for single-user, secured behind auth)
- b) Use a read-only token for listing, separate write token for
  creation (DO doesn't support this granularity yet, but might)
- c) Create a sub-account/team with limited permissions
- d) Proxy DO API calls through a separate service with rate limiting

**Recommended**: (a) for now. The dashboard is behind Authelia. If
Authelia is breached, the attacker has bigger problems than the DO
token. Revisit if adding multi-user support.

---

### Q8: What are your "current stable projects"?

**Why it matters**: Phase 5 (Project Persistence) needs to know what
projects need persistent storage, how much data they generate, and
what their dependencies are.

You mentioned:
- UI-TARS-desktop (AI desktop automation)
- claude-mem (Claude persistent memory)
- superpowers (AI capability extensions)

Plus "your own actual current stable projects." What are those?
What do they need?
- How much disk space?
- Do they need a database?
- Do they need GPU?
- Do they need specific OS packages?
- Do they need to be always-on or on-demand?

---

### Q9: Do you want git hosting on your domain?

**Why it matters**: You said "never leaving my domain of circlescorner.xyz"
for git operations. This implies self-hosted git. Options:

- a) **Gitea on the hub**: Lightweight, self-hosted GitHub-like interface.
  Accessible at git.circlescorner.xyz. Repos stay on your infrastructure.
- b) **Bare git repos on the hub**: No web UI, just `git push` via SSH.
  Simplest option. Use GitHub as a mirror/backup.
- c) **GitHub private repos as primary**: Use GitHub but access only via
  VPN/SSH. Simpler but data lives on GitHub.
- d) **Gitea on a dedicated worker**: Separate from the hub to keep the
  hub lightweight.

**Recommended**: Start with (b) in Phase 2 (push on-hub config to a bare
repo). Add Gitea (a or d) in Phase 8+ when you need a web UI for repos.

---

### Q10: What's your recovery email / account backup?

**Why it matters**: DigitalOcean web console is the ultimate breakglass.
If you lose access to your DO account, you lose the ability to recover.

- Is your DO account protected with 2FA?
- Do you have recovery codes saved?
- Is the account email an address you won't lose access to?

This isn't something I configure — it's something you verify and confirm.

---

### Q11: What devices will you access the dashboard from?

**Why it matters**: Affects authentication choices and VPN client setup.

- Laptop only?
- Laptop + phone?
- Multiple laptops?
- Tablet?

Each device needs:
- WebAuthn enrollment (if using YubiKey, the same key works everywhere)
- WireGuard client config (one config per device)
- Optionally: client certificate (if we go that route)

---

### Q12: Time zone preference?

**Why it matters**: Changelog timestamps, log timestamps, cron schedules
for backups. Everything is UTC by default (standard for servers), but the
dashboard could display times in your local timezone.

---

### Q13: What happens when you say "toggle public off"?

**Why it matters**: Need to define exactly what VPN-only mode means for
your workflow. When you toggle public off:

- a) Can you still SSH from the internet? (Current plan: no, SSH only via VPN)
- b) Or should SSH always be open from the internet as an escape hatch?

Option (a) is more secure. Option (b) is safer against lockout. If you
have WireGuard set up and tested, (a) is fine. If WireGuard is new to
you, keep (b) until you're confident.

**Recommended**: (b) initially. Switch to (a) after you've been using
WireGuard reliably for a month.

---

## Resolved Questions

*Move questions here when answered. Include the answer and date.*

```
### Q-RESOLVED: [question]
**Date resolved**: YYYY-MM-DD
**Answer**: [what was decided]
**Logged in**: DEC-NNN in DECISIONS-LOG.md
```
