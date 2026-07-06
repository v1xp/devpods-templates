#!/usr/bin/env bash
set -euo pipefail

# 1. GPG setup — import subkey (master key never enters the pod)
if [ -d /tmp/devpod-keys/gpg ]; then
  mkdir -p ~/.gnupg
  chmod 700 ~/.gnupg
  gpg --batch --import /tmp/devpod-keys/gpg/pubring.gpg 2>/dev/null || true
  gpg --batch --import /tmp/devpod-keys/gpg/subkeys.gpg 2>/dev/null || true
  gpgconf --launch gpg-agent 2>/dev/null || true
fi

# 2. SSH setup — copy keys from devpod-keys
if [ -d /tmp/devpod-keys/ssh ]; then
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  cp /tmp/devpod-keys/ssh/id_* ~/.ssh/ 2>/dev/null || true
  chmod 600 ~/.ssh/id_* 2>/dev/null || true
fi

# 3. Env loading — copy env.sh to a writable location
if [ -f /tmp/devpod-keys/env.sh ]; then
  cp /tmp/devpod-keys/env.sh ~/.devpod-env.sh
  chmod 600 ~/.devpod-env.sh
fi

# 4. Ensure .bashrc sources devpod env (idempotent)
if [ -f ~/.devpod-env.sh ] && ! grep -q 'devpod-env' ~/.bashrc 2>/dev/null; then
  echo '[ -f ~/.devpod-env.sh ] && source ~/.devpod-env.sh' >> ~/.bashrc
fi

# 5. Dotfiles — clone from GitHub
DOTFILES_REPO="https://github.com/v1xp-org/dotfiles-devpods.git"
DOTFILES_DIR="~/.local/share/dotfiles"
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR" 2>/dev/null || true
fi
if [ -f "$DOTFILES_DIR/install.sh" ]; then
  bash "$DOTFILES_DIR/install.sh"
fi

# 6. Quick verification
echo ""
echo "=== Setup Verification ==="
if [ -d ~/.gnupg/private-keys-v1.d ]; then
  echo "✓ GPG keys imported"
else
  echo "✗ GPG keys not found"
fi
if git config --global commit.gpgsign 2>/dev/null | grep -q true; then
  echo "✓ Git signing enabled"
else
  echo "✗ Git signing not enabled"
fi
if [ -f ~/.devpod-env.sh ]; then
  echo "✓ Env loaded"
else
  echo "✗ Env not loaded"
fi
echo "==="
