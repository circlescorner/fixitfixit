# Open Questions

**Document Status**: Living document — remove questions as they're answered,
add new ones as they arise. Move answered questions to the "Resolved" section
at the bottom.

---

## Questions Still Open

**None at this time** — all critical questions have been answered.
Ready to begin Phase 1.

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

---

### Q14-RESOLVED: DO Recovery Codes
**Date resolved**: 2026-02-07
**Answer**: User confirmed DO recovery codes will be saved before Phase 1
deployment. This is the critical backup mechanism if DO 2FA fails.
**Logged in**: Action item confirmed

---

### Q15-RESOLVED: Reserved IP
**Date resolved**: 2026-02-07
**Answer**: User has Reserved IP attached to a DO droplet, so it's free
($0/month when attached). Will keep it and use it for the hub — provides
stable DNS and eliminates need to update DNS records when rebuilding.
**Logged in**: DEC-025

---

### Q16-RESOLVED: Cloudflare
**Date resolved**: 2026-02-07
**Answer**: Interested in Cloudflare but will defer to Phase 8. For now,
DO DNS + Caddy HTTPS is sufficient. Cloudflare architecture will be
planned in advance but not implemented until later phases.
**Logged in**: DEC-026

---

### Q17-RESOLVED: atl1 availability
**Date resolved**: 2026-02-07
**Answer**: atl1 region confirmed with these premium Intel options
available (all under 3-droplet limit initially):
- $8/mo: 1GB/1CPU (hub candidate)
- $16/mo: 2GB/1CPU
- $24/mo: 2GB/2CPU
- $32/mo: 4GB/2CPU (recommended worker size)
- $48/mo: 8GB/2CPU (heavy workload option)

Will use atl1 as primary region with nyc1 as fallback if capacity issues
arise.
**Logged in**: DEC-027
