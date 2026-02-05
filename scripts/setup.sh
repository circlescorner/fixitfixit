#!/usr/bin/env bash
# Quick-start setup script for the sandbox infrastructure.
# Run this from the repo root after filling in terraform.tfvars.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Checking prerequisites..."

for cmd in terraform ssh-keygen; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not installed." >&2
    exit 1
  fi
done

# Generate SSH key if needed
KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
if [ ! -f "$KEY_PATH" ]; then
  echo "==> Generating SSH key at $KEY_PATH"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "sandbox"
fi

# Generate Authelia JWT secret if not set
if ! grep -q 'authelia_jwt_secret' "$ROOT_DIR/terraform/terraform.tfvars" 2>/dev/null; then
  echo "==> Generate an Authelia JWT secret with:"
  echo "    openssl rand -hex 32"
fi

# Terraform init + plan
echo "==> Initializing Terraform..."
cd "$ROOT_DIR/terraform"
terraform init

echo "==> Running Terraform plan..."
terraform plan

echo ""
echo "Review the plan above. To apply:"
echo "  cd terraform && terraform apply"
echo ""
echo "After apply, your dashboard will be at:"
echo "  https://\$(terraform output -raw dashboard_url)"
echo ""
echo "SSH into the hub:"
echo "  ssh root@\$(terraform output -raw hub_ip)"
