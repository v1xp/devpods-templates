#!/usr/bin/env bash
# Host-side setup — run once to create ~/.devpod-keys/
# Usage: ./setup-host.sh
set -euo pipefail

KEYS_DIR="$HOME/.devpod-keys"

echo "=== DevPod Keys Setup ==="
echo ""

# Check for existing GPG key
KEYS=$(gpg --list-secret-keys --keyid-format long 2>/dev/null | grep -c "^sec" || true)
if [ "$KEYS" -eq 0 ]; then
  echo "No GPG secret key found."
  echo "Run: gpg --full-generate-key"
  echo "Then re-run this script."
  exit 1
fi

# Select key if multiple
if [ "$KEYS" -gt 1 ]; then
  echo "Multiple GPG keys found:"
  gpg --list-secret-keys --keyid-format long | grep "^sec"
  echo ""
  read -rp "Enter key fingerprint: " FINGERPRINT
else
  FINGERPRINT=$(gpg --list-secret-keys --keyid-format long | grep "^sec" | awk '{print $2}' | cut -d'/' -f2)
  echo "Using key: $FINGERPRINT"
fi

# Create directories
mkdir -p "$KEYS_DIR/gpg"
mkdir -p "$KEYS_DIR/ssh"

# Export public key
echo "Exporting public key..."
gpg --export "$FINGERPRINT" > "$KEYS_DIR/gpg/pubring.gpg"

# Export subkeys only (no master)
echo "Exporting signing subkey..."
gpg --export-secret-subkeys "$FINGERPRINT" > "$KEYS_DIR/gpg/subkeys.gpg"

# Copy SSH keys
if [ -d "$HOME/.ssh" ]; then
  echo "Copying SSH keys..."
  cp "$HOME/.ssh/id_*" "$KEYS_DIR/ssh/" 2>/dev/null || true
fi

# Create env.sh template
if [ ! -f "$KEYS_DIR/env.sh" ]; then
  echo "Creating env.sh template..."
  cat > "$KEYS_DIR/env.sh" << 'ENVEOF'
# DevPod environment variables
# Add your secrets here, e.g.:
# export API_KEY=your_key_here
# export AWS_REGION=us-east-1
#
# Git identity (used by dotfiles install)
export GIT_USER_EMAIL="you@example.com"
export GIT_USER_NAME="Your Name"
ENVEOF
fi

# Lock down permissions
chmod 700 "$KEYS_DIR"
chmod 600 "$KEYS_DIR/gpg/"* "$KEYS_DIR/ssh/"* "$KEYS_DIR/env.sh" 2>/dev/null || true

echo ""
echo "Done! Directory structure:"
find "$KEYS_DIR" -type f
echo ""
echo "Next steps:"
echo "  1. Edit $KEYS_DIR/env.sh to add your secrets"
echo "  2. Use the templates when creating devpods"
