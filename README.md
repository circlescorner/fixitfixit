# Dev Sandbox

An isolated development sandbox on DigitalOcean with:

- **Always-on hub** — small droplet running reverse proxy, 2FA auth, and dashboard
- **4 Docker containers** — controlled via docker-compose from the dashboard
- **On-demand droplets** — spin up/destroy extra VMs from the dashboard, pre-networked via VPC
- **HTTPS** — automatic TLS via Caddy + Let's Encrypt
- **2FA** — Authelia with TOTP (Google Authenticator, Authy, etc.)

## Architecture

```
Internet
  |
  v
[Caddy reverse proxy] :443 (auto HTTPS)
  |
  v
[Authelia 2FA gate] -- blocks unauthenticated requests
  |
  v
[Dashboard app] :8000
  |
  +--> Docker sandbox containers (box1-4) on 172.30.0.0/24
  |
  +--> DigitalOcean API --> on-demand droplets in VPC 10.100.0.0/16
```

All resources share a VPC (`10.100.0.0/16`) so containers on the hub and extra droplets can talk to each other over private networking.

## Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [DigitalOcean account](https://digitalocean.com) + API token
- A domain name pointed at DigitalOcean DNS (or manually set A records)
- SSH key pair

## Quick Start

```bash
# 1. Copy and fill in your config
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your DO token, domain, email, etc.

# 2. Generate Authelia JWT secret
openssl rand -hex 32
# Paste into terraform.tfvars as authelia_jwt_secret

# 3. Run setup
./scripts/setup.sh

# 4. Apply infrastructure
cd terraform && terraform apply

# 5. Set your Authelia password
./scripts/set-password.sh 'YourSecurePassword'
# Then SSH into the hub and update /opt/sandbox/authelia/users.yml

# 6. Open your browser
# https://your-domain.com
# You'll be prompted for username (admin) + password + TOTP setup
```

## Dashboard Features

The web dashboard at `https://your-domain.com` provides:

### Container Management
- Start/stop/restart each of the 4 sandbox containers
- Start/stop all containers at once
- Change Docker images per slot (e.g., swap ubuntu for node, python, etc.)
- View container logs in real-time

### Network Visibility
- See all Docker networks and which containers are connected
- Connect/disconnect containers from networks via API

### Droplet Provisioning
- Spin up new DigitalOcean droplets with one click
- Pre-configured sizes from 1vCPU/1GB to 4vCPU/8GB
- Auto-joined to the sandbox VPC for private networking
- Destroy droplets when done

## File Structure

```
.
├── terraform/
│   ├── main.tf                  # Hub droplet, VPC, firewall, DNS
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # IPs, URLs
│   ├── terraform.tfvars.example # Template config
│   └── modules/droplet/         # Reusable module for on-demand VMs
├── infra/
│   └── cloud-init.yml           # Hub bootstrap (Docker, Caddy, Authelia)
├── dashboard/
│   ├── app.py                   # Flask API + control plane
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── templates/index.html     # Dashboard UI
│   └── static/
│       ├── css/style.css
│       └── js/dashboard.js
├── scripts/
│   ├── setup.sh                 # Initial setup + terraform init
│   ├── set-password.sh          # Generate Authelia password hash
│   └── deploy-dashboard.sh      # Push dashboard updates to hub
└── README.md
```

## API Reference

All endpoints require Authelia authentication (automatic via forward auth).

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/containers` | List sandbox containers |
| POST | `/api/containers/<name>/start` | Start a container |
| POST | `/api/containers/<name>/stop` | Stop a container |
| POST | `/api/containers/<name>/restart` | Restart a container |
| GET | `/api/containers/<name>/logs` | Get container logs |
| POST | `/api/containers/<name>/network` | Connect/disconnect network |
| POST | `/api/sandbox/up` | Start all sandbox containers |
| POST | `/api/sandbox/down` | Stop all sandbox containers |
| GET | `/api/sandbox/config` | Get compose config |
| PUT | `/api/sandbox/config` | Update container image |
| GET | `/api/droplets` | List DO droplets |
| POST | `/api/droplets` | Create new droplet |
| DELETE | `/api/droplets/<id>` | Destroy droplet |
| GET | `/api/networks` | List Docker networks |

## Networking

| Network | Range | Purpose |
|---------|-------|---------|
| `sandbox_net` | `172.30.0.0/24` | Docker bridge for the 4 sandbox containers |
| `sandbox_frontend` | auto | Caddy + Authelia + Dashboard |
| VPC | `10.100.0.0/16` | Private networking between all droplets |

Container IPs are fixed: `172.30.0.11` through `172.30.0.14` (box1-box4).

## Costs

- Hub (`s-1vcpu-1gb`): ~$6/month
- Each on-demand droplet: $6-48/month depending on size (destroy when not in use)
