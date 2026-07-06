#!/usr/bin/env bash
# Test script to verify devpod setup
# Run from host: ./test-setup.sh [knowledge|dev]
# Spins up pod, tests it, closes it, reports results.
set -uo pipefail

TEMPLATE="${1:-knowledge}"
REPO_URL="https://github.com/v1xp/devpods-templates"

# Map template name to devcontainer path
case "$TEMPLATE" in
  knowledge|k)
    DEVCONTAINER_PATH="src/knowledge/.devcontainer/devcontainer.json"
    TEMPLATE_NAME="knowledge"
    ;;
  dev|d)
    DEVCONTAINER_PATH="src/dev/.devcontainer/devcontainer.json"
    TEMPLATE_NAME="dev"
    ;;
  *)
    echo "Usage: $0 [knowledge|dev]"
    exit 1
    ;;
esac

WORKSPACE="devpod-test-${TEMPLATE_NAME}-$(date +%s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() {
  echo -e "${RED}✗${NC} $1"
  ERRORS=$((ERRORS + 1))
}
warn() { echo -e "${YELLOW}!${NC} $1"; }

ERRORS=0

echo "=== DevPod Setup Test ==="
echo "Template: $TEMPLATE_NAME"
echo "Workspace: $WORKSPACE"
echo ""

# 1. Spin up pod
echo "--- Spinning up pod ---"
UP_OUTPUT=$(devpod up "$REPO_URL" --devcontainer-path "$DEVCONTAINER_PATH" --dotfiles github.com/v1xp-org/dotfiles-devpods.git 2>&1)
if [ $? -eq 0 ]; then
  pass "Pod created"
  # Extract workspace name from output
  WORKSPACE=$(echo "$UP_OUTPUT" | grep -oP 'Workspace\s+\K\S+' | head -1)
  if [ -z "$WORKSPACE" ]; then
    # Try to get the last created workspace
    WORKSPACE=$(devpod list 2>/dev/null | tail -1 | awk '{print $1}')
  fi
  echo "Workspace name: $WORKSPACE"
else
  echo "$UP_OUTPUT"
  fail "Pod creation failed"
  echo -e "\n${RED}Cannot continue without a running pod${NC}"
  exit 1
fi

# 2. Run checks inside pod
echo ""
echo "--- Running checks inside pod ---"
CHECKS=$(devpod ssh "$WORKSPACE" -- bash -s << 'CHECKSCRIPT'
# Docker
if [ -S /var/run/docker.sock ]; then
  if docker info >/dev/null 2>&1; then
    echo "PASS:Docker socket accessible"
  else
    echo "WARN:Docker socket exists but daemon not reachable (expected for knowledge pod)"
  fi
else
  echo "WARN:Docker socket not mounted"
fi

# GPG
if [ -d ~/.gnupg ] && [ -d ~/.gnupg/private-keys-v1.d ]; then
  echo "PASS:GPG home directory exists with private keys"
else
  echo "FAIL:GPG home directory missing or no private keys imported"
fi

SUBKEY=$(gpg --list-secret-subkeys --keyid-format long 2>/dev/null | grep "ssb" | head -1 | awk '{print $2}')
if [ -n "$SUBKEY" ]; then
  echo "PASS:Signing subkey found: $SUBKEY"
else
  echo "WARN:No signing subkey found"
fi

if gpgconf --list-components 2>/dev/null | grep -q gpg-agent; then
  echo "PASS:GPG agent available"
else
  echo "FAIL:GPG agent not found"
fi

# Git
if git config --global commit.gpgsign 2>/dev/null | grep -q true; then
  echo "PASS:Git commit signing enabled"
else
  echo "FAIL:Git commit signing not enabled"
fi

SIGNING_KEY=$(git config --global user.signingkey 2>/dev/null)
if [ -n "$SIGNING_KEY" ]; then
  echo "PASS:Git signing key set: $SIGNING_KEY"
else
  echo "FAIL:Git signing key not configured"
fi

EMAIL=$(git config --global user.email 2>/dev/null)
if [ -n "$EMAIL" ]; then
  echo "PASS:Git email set: $EMAIL"
else
  echo "WARN:Git email not set"
fi

NAME=$(git config --global user.name 2>/dev/null)
if [ -n "$NAME" ]; then
  echo "PASS:Git name set: $NAME"
else
  echo "WARN:Git name not set"
fi

# SSH
if [ -d ~/.ssh ] && ls ~/.ssh/id_* >/dev/null 2>&1; then
  echo "PASS:SSH keys found"
else
  echo "WARN:No SSH keys found"
fi

if [ -f ~/.ssh/config ]; then
  echo "PASS:SSH config exists"
else
  echo "WARN:SSH config not created"
fi

# Env
if [ -f ~/.devpod-env.sh ]; then
  echo "PASS:devpod env file exists"
else
  echo "WARN:devpod env file not found"
fi

if grep -q 'devpod-env' ~/.bashrc 2>/dev/null; then
  echo "PASS:.bashrc sources devpod env"
else
  echo "WARN:.bashrc does not source devpod env"
fi

# Dotfiles
if [ -d ~/.config/nvim ] || [ -d ~/.config/tmux ]; then
  echo "PASS:Dotfiles applied"
else
  echo "WARN:Dotfiles not applied"
fi

if command -v stow >/dev/null 2>&1; then
  echo "PASS:stow available"
else
  echo "WARN:stow not found"
fi
CHECKSCRIPT
)

# Parse results
while IFS= read -r line; do
  case "$line" in
    PASS:*) pass "${line#PASS:}" ;;
    FAIL:*) fail "${line#FAIL:}" ;;
    WARN:*) warn "${line#WARN:}" ;;
  esac
done <<< "$CHECKS"

# 3. Delete pod
echo ""
echo "--- Cleaning up ---"
if devpod delete "$WORKSPACE" --force 2>&1; then
  pass "Pod deleted"
else
  warn "Pod deletion failed (manual cleanup may be needed)"
fi

# 4. Summary
echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed!${NC}"
else
  echo -e "${RED}$ERRORS error(s) found${NC}"
fi

exit "$ERRORS"
