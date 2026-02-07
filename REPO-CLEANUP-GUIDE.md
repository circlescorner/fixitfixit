# Repository Cleanup & Reorganization

## Current Problem

Your `/docs` folder has too many files that overlap:
- PHASE-1-DEPLOYMENT.md
- DEPLOYMENT-INSTRUCTIONS.md  
- PHASE-1-READINESS-SUMMARY.md
- QUICK-REFERENCE.md
- HOW-TO-SYNC-TO-GIT.md

These should be consolidated.

---

## Recommended Structure

```
fixitfixit/
├── README.md                    # Project overview + quick start
├── docs/
│   ├── 00-SYSTEM-OVERVIEW.md    # What this is, why it exists
│   ├── 01-ARCHITECTURE.md       # Technical design
│   ├── 02-SECURITY-MODEL.md     # Auth, secrets, access control
│   ├── 03-DEPLOYMENT.md         # How to deploy (combines all deployment docs)
│   ├── 04-OPERATIONS.md         # Day-to-day operations
│   ├── DECISIONS-LOG.md         # Architecture decisions (keep as-is)
│   └── AI-COLLABORATION-GUIDE.md # How to work with AI (keep as-is)
├── infra/
│   └── cloud-init-phase1.yml    # Bootstrap script for hub
├── dashboard/
│   ├── app.py
│   ├── Dockerfile
│   └── requirements.txt
├── scripts/                     # Helper scripts (if any)
└── terraform/                   # Future IaC (currently unused)
```

---

## Files to DELETE

These are redundant or temporary:

### From `/docs`:
- **DELETE** `PHASE-1-DEPLOYMENT.md` (merge into 03-DEPLOYMENT.md)
- **DELETE** `DEPLOYMENT-INSTRUCTIONS.md` (merge into 03-DEPLOYMENT.md)
- **DELETE** `PHASE-1-READINESS-SUMMARY.md` (was just a summary)
- **DELETE** `QUICK-REFERENCE.md` (merge key info into README.md)
- **DELETE** `HOW-TO-SYNC-TO-GIT.md` (one-time use, not needed in repo)
- **DELETE** `EVOLUTION-PLAN.md` (outdated by actual deployment)
- **DELETE** `CHANGE-MANAGEMENT.md` (covered in OPERATIONS)
- **DELETE** `cloud-init-phase1.yml` (belongs in /infra, not /docs)

### Keep:
- **00-SYSTEM-OVERVIEW.md** (rename from SYSTEM-OVERVIEW.md)
- **01-ARCHITECTURE.md** (rename from ARCHITECTURE.md)
- **02-SECURITY-MODEL.md** (rename from SECURITY-MODEL.md)
- **03-DEPLOYMENT.md** (NEW - consolidates all deployment docs)
- **04-OPERATIONS.md** (rename from OPERATIONS-RUNBOOK.md)
- **DECISIONS-LOG.md** (keep as-is)
- **AI-COLLABORATION-GUIDE.md** (keep as-is)

---

## NEW: 03-DEPLOYMENT.md (Consolidated)

This single file replaces:
- PHASE-1-DEPLOYMENT.md
- DEPLOYMENT-INSTRUCTIONS.md
- QUICK-REFERENCE.md

**Structure:**
```markdown
# Deployment Guide

## Quick Start
[Summary of steps - 5 bullets]

## Prerequisites
- DO account with 2FA + recovery codes
- Reserved IP setup
- DNS configured

## Step-by-Step Deployment
### 1. Create VPC
### 2. Create Hub Droplet
### 3. Assign Reserved IP
### 4. Wait for Cloud-Init
### 5. Complete Setup Wizard

## Troubleshooting
[Common issues + fixes]

## What You Built
[Infrastructure summary]

## Next Steps
[Phase 1b preview]
```

---

## NEW: README.md (Updated)

Currently your README.md probably has basic project info. Update it:

```markdown
# Virtual Dev Desktop - Sandbox Hub

Personal cloud-based development platform with web-based control panel.

## Quick Start

1. **Clone repo**: `git clone <your-repo-url>`
2. **Deploy hub**: Follow [docs/03-DEPLOYMENT.md](docs/03-DEPLOYMENT.md)
3. **Access**: https://circlescorner.xyz

## What This Is

On-demand development infrastructure controlled from a web dashboard.
Spin up containers and VMs, manage networking, rollback configurations.
Everything behind your own domain with real 2FA.

## Documentation

- [System Overview](docs/00-SYSTEM-OVERVIEW.md) - What and why
- [Architecture](docs/01-ARCHITECTURE.md) - Technical design
- [Security Model](docs/02-SECURITY-MODEL.md) - Auth and secrets
- **[Deployment Guide](docs/03-DEPLOYMENT.md)** - **Start here**
- [Operations Guide](docs/04-OPERATIONS.md) - Day-to-day use
- [Decisions Log](docs/DECISIONS-LOG.md) - Why things are this way
- [AI Collaboration](docs/AI-COLLABORATION-GUIDE.md) - Working with Claude

## Current Status

**Phase 1**: Hub deployment with authentication
- Caddy reverse proxy
- Authelia 2FA (password + TOTP/Face ID)
- Web dashboard
- 4 sandbox containers

**Monthly cost**: ~$9.60 ($8 hub + $1.60 backups)

## Tech Stack

- **Cloud**: DigitalOcean
- **OS**: Ubuntu 24.04
- **Reverse Proxy**: Caddy
- **Auth**: Authelia
- **Dashboard**: Flask + Docker API
- **Containers**: Docker + Compose

## License

[Your license here]
```

---

## How to Reorganize

### Step 1: Rename files

```bash
cd docs/
mv SYSTEM-OVERVIEW.md 00-SYSTEM-OVERVIEW.md
mv ARCHITECTURE.md 01-ARCHITECTURE.md
mv SECURITY-MODEL.md 02-SECURITY-MODEL.md
mv OPERATIONS-RUNBOOK.md 04-OPERATIONS.md
```

### Step 2: Create consolidated deployment doc

I'll provide this as a separate file.

### Step 3: Delete redundant files

```bash
cd docs/
rm PHASE-1-DEPLOYMENT.md
rm DEPLOYMENT-INSTRUCTIONS.md
rm PHASE-1-READINESS-SUMMARY.md
rm QUICK-REFERENCE.md
rm HOW-TO-SYNC-TO-GIT.md
rm EVOLUTION-PLAN.md
rm CHANGE-MANAGEMENT.md
rm cloud-init-phase1.yml  # This belongs in /infra
```

### Step 4: Move cloud-init to correct location

```bash
# Make sure clean version is in /infra
cp /path/to/cloud-init-phase1-CLEAN.yml infra/cloud-init-phase1.yml
```

### Step 5: Update README.md

Replace current README with the updated version above.

### Step 6: Commit

```bash
git add -A
git commit -m "Reorganize documentation - consolidate deployment docs

- Renamed docs with number prefixes for order
- Created single 03-DEPLOYMENT.md (replaces 5 separate files)
- Deleted redundant/temporary docs
- Updated README with better quick start
- Moved cloud-init to /infra where it belongs"
git push
```

---

## Result

**Before**: 14 files in /docs (confusing, overlapping)
**After**: 7 files in /docs (clean, organized, numbered)

Each doc has a clear purpose. No overlap. Easy to navigate.

---

## What's Next

Once you reorganize:
1. Use the CLEAN cloud-init file to redeploy
2. Your repo will be much easier to maintain
3. Future phases just update the existing docs
