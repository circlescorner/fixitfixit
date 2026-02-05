#!/usr/bin/env bash
# Generate an Authelia-compatible password hash and update the users file.
# Usage: ./set-password.sh <password>
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <password>"
  exit 1
fi

PASSWORD="$1"

echo "==> Generating argon2id hash..."
HASH=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$PASSWORD" 2>/dev/null | grep 'Digest:' | awk '{print $2}')

if [ -z "$HASH" ]; then
  echo "ERROR: Failed to generate hash. Is Docker running?" >&2
  exit 1
fi

echo "==> Password hash generated."
echo ""
echo "Replace the password field in authelia/users.yml with:"
echo ""
echo "  password: \"$HASH\""
echo ""
echo "Or if deploying to a live server, SSH in and edit:"
echo "  /opt/sandbox/authelia/users.yml"
