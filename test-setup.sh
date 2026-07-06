#!/usr/bin/env bash
# Test script to verify devpod setup
# Run inside the pod: ./test-setup.sh
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "${YELLOW}!${NC} $1"; }

ERRORS=0

echo "=== DevPod Setup Test ==="
echo ""

# 1. Docker socket
echo "--- Docker ---"
if [ -S /var/run/docker.sock ]; then
  if docker info >/dev/null 2>&1; then
    pass "Docker socket accessible"
  else
    fail "Docker socket exists but daemon not reachable"
  fi
else
  warn "Docker socket not mounted (not required for dev template)"
fi

# 2. GPG
echo ""
echo "--- GPG ---"
if [ -d ~/.gnupg ] && [ -d ~/.gnupg/private-keys-v1.d ]; then
  pass "GPG home directory exists with private keys"
else
  fail "GPG home directory missing or no private keys imported"
fi

if gpg --list-secret-subkeys --keyid-format long 2>/dev/null | grep -q "ssb"; then
  SUBKEY=$(gpg --list-secret-subkeys --keyid-format long 2>/dev/null | grep "ssb" | head -1 | awk '{print $2}')
  pass "Signing subkey found: $SUBKEY"
else
  warn "No signing subkey found (using primary key or none)"
fi

if gpgconf --list-components 2>/dev/null | grep -q gpg-agent; then
  pass "GPG agent is available"
else
  fail "GPG agent not found"
fi

# 3. Git
echo ""
echo "--- Git ---"
if git config --global commit.gpgsign 2>/dev/null | grep -q true; then
  pass "Git commit signing enabled"
else
  fail "Git commit signing not enabled"
fi

SIGNING_KEY=$(git config --global user.signingkey 2>/dev/null)
if [ -n "$SIGNING_KEY" ]; then
  pass "Git signing key set: $SIGNING_KEY"
else
  fail "Git signing key not configured"
fi

EMAIL=$(git config --global user.email 2>/dev/null)
if [ -n "$EMAIL" ]; then
  pass "Git email set: $EMAIL"
else
  warn "Git email not set (set GIT_USER_EMAIL in env.sh)"
fi

NAME=$(git config --global user.name 2>/dev/null)
if [ -n "$NAME" ]; then
  pass "Git name set: $NAME"
else
  warn "Git name not set (set GIT_USER_NAME in env.sh)"
fi

# 4. SSH
echo ""
echo "--- SSH ---"
if [ -d ~/.ssh ] && ls ~/.ssh/id_* >/dev/null 2>&1; then
  pass "SSH keys found in ~/.ssh/"
else
  warn "No SSH keys found in ~/.ssh/ (check ~/.ssh-host mount)"
fi

if [ -f ~/.ssh/config ]; then
  pass "SSH config exists"
else
  warn "SSH config not created"
fi

# 5. Env vars
echo ""
echo "--- Environment ---"
if [ -f ~/.devpod-env.sh ]; then
  pass "devpod env file exists"
else
  warn "devpod env file not found"
fi

if grep -q 'devpod-env' ~/.bashrc 2>/dev/null; then
  pass ".bashrc sources devpod env"
else
  warn ".bashrc does not source devpod env"
fi

# 6. Dotfiles
echo ""
echo "--- Dotfiles ---"
if [ -d ~/.config/nvim ] || [ -d ~/.config/tmux ]; then
  pass "Dotfiles applied (nvim/tmux config found)"
else
  warn "Dotfiles not applied (no nvim/tmux config)"
fi

if command -v stow >/dev/null 2>&1; then
  pass "stow is available"
else
  warn "stow not found"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed!${NC}"
else
  echo -e "${RED}$ERRORS error(s) found${NC}"
fi

exit "$ERRORS"
