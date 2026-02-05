#!/usr/bin/env bash
# Rsync the dashboard code to the hub and restart.
# Usage: ./deploy-dashboard.sh <hub-ip>
set -euo pipefail

HUB_IP="${1:?Usage: $0 <hub-ip>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Deploying dashboard to $HUB_IP..."

rsync -avz --delete \
  "$ROOT_DIR/dashboard/" \
  "root@${HUB_IP}:/opt/sandbox/dashboard/"

echo "==> Rebuilding and restarting dashboard container..."
ssh "root@${HUB_IP}" "cd /opt/sandbox && docker compose up -d --build dashboard"

echo "==> Done. Dashboard updated on $HUB_IP"
