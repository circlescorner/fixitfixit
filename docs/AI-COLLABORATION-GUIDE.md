# AI Collaboration Guide

**Document Status**: Living document
**Purpose**: Define how you and an AI assistant (Claude, or any future LLM)
work together on this system, including known limitations, guardrails, and
patterns that prevent compounding mistakes.

---

## Why This Document Exists

You asked: "design around your understanding limitations that will limit
your ability to evolve this system with me."

AI assistants have real limitations that, if not designed around, will
cause problems. This document names them explicitly and describes the
mitigation for each.

---

## Known AI Limitations

### 1. No Access to Running Infrastructure

**The limitation**: I can edit files in this repository. I cannot SSH to your
hub, check if containers are running, verify DNS is resolving, or confirm
that a change I suggested actually works.

**The risk**: I might suggest a Caddy config change that has a syntax error.
You deploy it. Caddy crashes. I don't know it crashed.

**Mitigation**:
- **You are the deployment verifier.** After any change, you deploy and
  confirm it works before we move on.
- **Use a checklist** after every deployment. Example:
  - [ ] Change deployed
  - [ ] Service restarted
  - [ ] Web dashboard still loads
  - [ ] SSH still works
  - [ ] No errors in logs
- **Report back to me** what happened. "It works" or "It broke, here's
  the error." I need your feedback to avoid repeating mistakes.

### 2. No Persistent Memory Across Conversations

**The limitation**: Each new conversation starts without knowledge of
previous conversations, unless context is provided.

**The risk**: I might suggest reverting a change we already tried and
rejected. I might not know what phase the system is currently in. I might
re-introduce a bug we already fixed.

**Mitigation**:
- **This documentation is the persistent memory.** Keep it updated.
  When we make a decision, log it in DECISIONS-LOG.md.
- **The EVOLUTION-PLAN.md tracks current phase.** Update the "Current
  Phase" line at the top when you advance.
- **The changelog tracks what happened.** I can read it to understand
  recent system state.
- **Start each new conversation with context**:
  ```
  "We're working on the virtual dev desktop in fixitfixit/.
  Current phase: Phase 3 (WireGuard).
  Last thing we did: added WireGuard server config.
  Current issue: client can't connect, getting handshake timeout."
  ```
  This 4-line summary saves significant back-and-forth.
- **The memory file at `/root/.claude/projects/-home-user-fixitfixit/memory/`**
  provides some cross-conversation persistence. I'll write key learnings there.

### 3. No Real-Time Observation

**The limitation**: I can't watch logs stream, monitor network traffic,
or observe the system's behavior over time.

**The risk**: Intermittent issues (works sometimes, fails sometimes) are
hard to debug through me alone.

**Mitigation**:
- **Copy-paste relevant logs** into our conversation when debugging.
- **Describe the symptom precisely**: "Works on first load, fails on
  refresh" is more useful than "it doesn't work."
- **The changelog system** (Phase 6) helps by creating a timeline of
  events that we can correlate with symptoms.

### 4. I Can Make Confident-Sounding Mistakes

**The limitation**: I may suggest a configuration that looks correct but
has a subtle error. I present information with the same tone whether I'm
certain or guessing.

**The risk**: You deploy a broken config because I sounded sure.

**Mitigation**:
- **Always test in a reversible way.** The pre-change snapshot (Phase 2)
  exists specifically for this. Commit before changing, so you can revert.
- **I'll flag uncertainty when I'm aware of it.** But I may not always
  catch my own mistakes.
- **For critical changes** (Authelia, firewall, SSH), use this protocol:
  1. I suggest the change
  2. You review it (does it make sense?)
  3. You make a snapshot/commit
  4. You deploy with an SSH session open as breakglass
  5. You verify
  6. You report back

### 5. Knowledge Cutoff

**The limitation**: My training data has a cutoff. Software versions,
best practices, and API changes after that cutoff may not be reflected.

**The risk**: I might suggest deprecated configurations or miss new
features.

**Mitigation**:
- **Check version-specific docs** for critical components:
  - Authelia: https://www.authelia.com/configuration/
  - Caddy: https://caddyserver.com/docs/
  - WireGuard: https://www.wireguard.com/
  - Terraform DO provider: https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs
- **Pin versions** in your configs (you're already doing this with
  `caddy:2` and Terraform provider `~> 2.34`).
- **If something doesn't work as I described**, the tool may have changed.
  Check the official docs.

### 6. I Can't Handle Secrets Safely

**The limitation**: Secrets pasted into our conversation are in the
conversation history. I should never have your actual API tokens, passwords,
or private keys.

**The risk**: If secrets appear in conversation, they could be exposed
through conversation history or logging.

**Mitigation**:
- **Never paste actual secrets to me.** Use placeholders like
  `<your-do-token>` and I'll write configs with those placeholders.
- **Secrets stay in terraform.tfvars** (gitignored) and on the hub.
- **I can generate commands** that create secrets (like `openssl rand`
  or `wg genkey`), but the output goes to your terminal, not to me.

### 7. I May Over-Engineer

**The limitation**: Given the chance, I'll add error handling, abstractions,
and features that aren't needed yet.

**The risk**: The system becomes complex and hard to understand, which is
the opposite of what you want.

**Mitigation**:
- **Push back when I over-build.** "Just the minimum for this phase" is
  a valid and useful instruction.
- **The phase system exists to prevent scope creep.** Each phase has
  specific deliverables. Don't let me (or yourself) jump ahead.
- **Principle: if you can't explain it, it's too complex.** Every
  component should be understandable from its config file.

---

## Collaboration Patterns

### Pattern 1: Start Conversations With State

Before asking me to do anything, give me the current state:

```
Current phase: [number]
Last completed work: [summary]
Current problem: [description]
Relevant logs: [paste if applicable]
```

### Pattern 2: One Phase at a Time

Don't ask me to "add WebAuthn and WireGuard and project volumes" in one
conversation. Each phase is a separate unit of work:

1. We plan phase N
2. You deploy phase N
3. You verify phase N works
4. We plan phase N+1

### Pattern 3: Review Before Deploy

For any non-trivial change:
1. I produce the change (file edits, config changes)
2. You review (does this look right? does it match the plan?)
3. You commit (git add + commit with message)
4. You deploy (rsync, terraform apply, docker restart)
5. You verify (does it work? any errors?)
6. You report back

### Pattern 4: Document Decisions Immediately

When we decide something (use WebAuthn over client certs, use WireGuard
over Tailscale, etc.), log it in DECISIONS-LOG.md **during the conversation**.
Don't defer it.

### Pattern 5: Use This Repo As the Source of Truth

If there's a conflict between what I say in conversation and what's in the
docs, the docs should win (unless we're explicitly updating them). The
docs represent the agreed-upon plan.

### Pattern 6: Red/Green Testing

Before making a change:
1. Verify the system works (green state)
2. Make the change
3. Verify the system still works (green state)

If step 3 fails, revert. Then we debug why.

---

## What I Can and Can't Do

### I Can
- Read and write files in this repository
- Suggest configurations, code changes, and scripts
- Explain how things work and why
- Plan multi-step changes with rollback points
- Review your work and catch potential issues
- Search the web for current documentation
- Remember context within a single conversation
- Write to the memory file for cross-conversation persistence

### I Cannot
- Access your DigitalOcean account or API
- SSH to your hub or any droplet
- Verify that a deployed change works
- Manage your actual secrets
- Monitor your system in real-time
- Guarantee that a configuration is correct without testing
- Know what happened between conversations (unless you tell me or I read it from files)

---

## How to Give Me Effective Feedback

**Good feedback** (helps me help you):
- "The Caddy config you suggested gives this error: [paste error]"
- "WireGuard connects but I can't reach 10.200.0.1"
- "This works but the dashboard takes 10 seconds to load"
- "I don't understand why we need X. Explain the tradeoff."

**Less helpful feedback** (I'll still try, but it's harder):
- "It doesn't work"
- "Something is wrong"
- "Fix it"

The more specific the feedback, the more targeted my response.

---

## Anti-Patterns to Avoid

### 1. Deploying without understanding
If I suggest a config change and you don't understand what it does, **ask**.
Deploying configs you don't understand is how you end up locked out.

### 2. Skipping verification
After every change, check that the system works. Don't stack 5 changes
and then check. One change, one verification.

### 3. Working outside the phase plan
The phases exist to keep complexity manageable. If you get an idea for
Phase 7 while working on Phase 2, write it down in EVOLUTION-PLAN.md
under Phase 7. Don't implement it now.

### 4. Not updating docs
If we make a decision that changes the architecture, the docs must be
updated in the same commit. Stale docs are worse than no docs because
they mislead.

### 5. Copying configs from the internet without understanding
Stack Overflow and blog posts are useful but often stale or
context-dependent. If you find a config snippet, bring it to me and we'll
evaluate it together against your specific setup.

---

## Cross-Conversation Continuity Checklist

At the end of every conversation where we make changes:

- [ ] EVOLUTION-PLAN.md updated with current phase status
- [ ] DECISIONS-LOG.md updated with any decisions made
- [ ] OPEN-QUESTIONS.md updated (questions answered → removed, new questions → added)
- [ ] Code changes committed with descriptive message
- [ ] Memory file updated with key learnings (if applicable)
- [ ] You know the next step (what to do in the next conversation)
