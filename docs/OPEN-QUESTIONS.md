# Open Questions

**Document Status**: Living document — remove questions as they're answered,
add new ones as they arise. Move answered questions to the "Resolved" section
at the bottom.

---

## Questions Still Open

### Q14: DO Recovery Codes — ACTION REQUIRED

**Status**: BLOCKING — must be done before Phase 1 deployment

You confirmed your DO account has 2FA but you do NOT have recovery codes
saved. This is the single highest-risk item in the entire system. If you
lose DO access (phone breaks, authenticator resets), you lose everything.

**Action needed**:
1. Go to cloud.digitalocean.com → Account → Security
2. Generate and save recovery codes
3. Store them somewhere safe (screenshot in a secure note, printed paper
   in a drawer, whatever — just not ONLY on the phone that has the 2FA app)
4. Confirm this is done before we deploy

---

### Q15: Reserved IP — keep or drop?

You said you have a DO Reserved IP you're paying for. Clarification needed:

- **If it's attached to a running droplet**: It's free ($0/month)
- **If it's floating (no droplet)**: It costs $5/month

For this system, a Reserved IP is valuable — it means DNS doesn't need
updating when you rebuild the hub. But it's not strictly required since
we can programmatically update DO DNS records.

**Options**:
- a) Keep the Reserved IP, attach it to the hub ($0/month when attached).
  DNS A record points to this IP permanently. Rebuilding the hub =
  just reassign the IP.
- b) Drop the Reserved IP, use the hub's auto-assigned IP. DNS updated
  via DO API on each rebuild. Saves $5/month when you don't have a hub.

**Recommended**: (a) — the stability is worth it, and it's free when
attached.

---

### Q16: Cloudflare — interested or not?

You mentioned hearing about Cloudflare but never getting it to work.
Cloudflare could add:
- DDoS protection (free tier)
- CDN caching (free tier)
- Additional SSL/TLS layer
- IP obfuscation (hides your hub's real IP)

But it adds complexity and another account to manage. For a single-user
system, it's optional.

**Options**:
- a) Skip Cloudflare. DO DNS + Caddy HTTPS is sufficient.
- b) Add Cloudflare later as an enhancement (Phase 8+).

**Recommended**: (a) for now. One less thing to configure.

---

### Q17: Confirm atl1 availability

DigitalOcean's `atl1` (Atlanta) region has limited resource availability.
Before deploying, you should verify:
1. s-1vcpu-1gb is available in atl1 (for the hub)
2. s-4vcpu-8gb is available in atl1 (for workers)
3. s-2vcpu-4gb is available in atl1 (recommended for budget — see cost section)

**How to check**: DO panel → Create → Droplets → select atl1 → see available sizes.

If sizes are unavailable, we fall back to nyc1 as planned.

---

## Resolved Questions

### Q1-RESOLVED: Domain registrar and DNS
**Date resolved**: 2026-02-06
**Answer**: Domain at Namecheap, nameservers pointed to DigitalOcean
(ns1/ns2/ns3.digitalocean.com). DNS records managed in DO panel. Namecheap
account has 2FA. Has a Reserved IP (see Q15).
**Logged in**: DEC-011

---

### Q2-RESOLVED: Authentication device
**Date resolved**: 2026-02-06
**Answer**: iPhone 16 is the PRIMARY and often ONLY device. No trusted PC.
Frequently on corporate networks, public computers, or friends' machines.
Cannot install software or certificates on work/public computers. Must
look like normal HTTPS website traffic. Willing to install apps and buy
accessories for the iPhone.

**Critical implications**:
- WebAuthn via iPhone Face ID is the primary 2FA (built into Safari, no
  app needed, looks like a normal website)
- No VPN client requirement for daily use (WireGuard = unusual traffic on
  corporate networks)
- No client certificates (can't install on work/public PCs)
- No SSH client requirement (iPhone SSH apps exist but not the primary path)
- YubiKey recommendation withdrawn — Face ID is the authenticator
- WireGuard becomes optional, not required for daily access

**Logged in**: DEC-012, DEC-013, DEC-014

---

### Q3-RESOLVED: SSH key situation
**Date resolved**: 2026-02-06
**Answer**: Has SSH key pairs on iPhone (in saved notes — not ideal). Has
a pattern of locking himself out by making systems "too secure" and then
destroying the droplet. Considered "no SSH at all" philosophy. Interested
in a self-hosted secrets server.

**Decision**: SSH remains as breakglass only, accessible via DO web console
when needed. Not the primary access method. SSH keys will be managed
through the dashboard in a later phase. For now, DO Console is the
emergency access path.
**Logged in**: DEC-015

---

### Q4-RESOLVED: DigitalOcean region
**Date resolved**: 2026-02-06
**Answer**: `atl1` (Atlanta) preferred, `nyc1` as fallback if atl1 has
availability issues. User is in central US (closer to Atlanta than NYC).
**Logged in**: DEC-016

---

### Q5-RESOLVED: Budget and auto-destroy
**Date resolved**: 2026-02-06
**Answer**: Comprehensive budget requirements:
- $25 max setup cost, $15/month target operating cost
- Auto-destroy with smart hibernation: warn after 3min inactivity, extend
  2-60min, kill after 2min no response
- MUST snapshot/preserve state before destroy (sleep, not death)
- Budget controller in dashboard: per-deployment budget, monthly budget,
  spending tracker, cost estimator before spawning
- Max droplet size: 4vCPU/8GB
- Expected usage: 1x large worker 6hr/weekday + occasional 4x large 4hr/week
- Hub can be powered down when known to be unused for extended periods

**Budget reality** (at s-4vcpu-8gb pricing):
- Hub: $6/mo
- Workers at described usage: ~$14/mo
- Total: ~$20/mo (exceeds $15 target)

**At s-2vcpu-4gb pricing** (recommended for most work):
- Hub: $6/mo
- Workers at described usage: ~$7/mo
- Total: ~$13/mo (fits budget)
- Can still use 4vCPU/8GB for occasional heavy workloads

**Logged in**: DEC-017, DEC-018

---

### Q6-RESOLVED: Hub accessible by IP or domain
**Date resolved**: 2026-02-06
**Answer**: Chose option C initially, but given iPhone-only constraint and
no WireGuard as default, revised to: domain-only for daily use (normal
HTTPS), with DO Console as emergency backup. If Reserved IP is kept,
the IP can be used as a direct fallback if DNS breaks (Caddy can serve
both domain and IP).
**Logged in**: DEC-011

---

### Q7-RESOLVED: DO API token handling
**Date resolved**: 2026-02-06
**Answer**: User is concerned about exposing sensitive operations via www.
Wants safety net against "doing something stupid." Considered proxy VM
but that adds cost.

**Decision**: Keep token server-side (Flask environment, never sent to
browser). Add safety layers: confirmation dialogs, rate limiting on
destructive actions, audit log, undo-window for creates. Consider moving
DO API operations to a separate internal service in a later phase.
**Logged in**: DEC-019

---

### Q8-RESOLVED: Current stable projects
**Date resolved**: 2026-02-06
**Answer**: No projects to host immediately. Wants persistent project
momentum as things start working — systems should "remember where they
were" across spawn cycles. Initial projects to explore and prepare for:
- UI-TARS-desktop (bytedance) — AI desktop automation
- claude-mem (thedotmack) — Claude persistent memory
- superpowers (obra) — AI capability extensions

Dependencies to be explored when we reach Phase 5.
**Logged in**: DEC-020

---

### Q9-RESOLVED: Git hosting
**Date resolved**: 2026-02-06
**Answer**: Bare repos to start. Interested in self-hosted Gitea later,
particularly as a secrets management interface. The path: bare repos →
Gitea on a dedicated VM → potentially secrets management through Gitea.
**Logged in**: DEC-021

---

### Q10-RESOLVED: DO account backup
**Date resolved**: 2026-02-06
**Answer**: DO has 2FA, does NOT have recovery codes saved, email
"probably safe" but not certain. See Q14 — saving recovery codes is a
BLOCKING action item.
**Logged in**: Captured in Q14 (still open)

---

### Q11-RESOLVED: Access devices
**Date resolved**: 2026-02-06
**Answer**: Same as Q2. iPhone 16 primary. Occasionally work PCs, public
computers, friends' machines. No trusted PC. Everything must work in a
standard web browser with no plugins, extensions, or installed software.
**Logged in**: DEC-012

---

### Q12-RESOLVED: Timezone
**Date resolved**: 2026-02-06
**Answer**: Central US (America/Chicago, CST/CDT).
**Logged in**: DEC-022

---

### Q13-RESOLVED: VPN-only toggle behavior
**Date resolved**: 2026-02-06
**Answer**: Option A — maximum security. "As secure as reasonably
achievable."

**However**: Given iPhone-only constraint and no WireGuard as daily driver,
the concept of "VPN-only toggle" is redesigned. Instead of blocking public
HTTPS, security modes become:
- **Normal mode**: HTTPS accessible, password + Face ID required
- **Restricted mode**: HTTPS accessible only from allowlisted IPs
- **Lockdown mode**: All web access disabled, DO Console only

WireGuard remains available as an optional extra for when user has a
device that supports it.
**Logged in**: DEC-014, DEC-023
