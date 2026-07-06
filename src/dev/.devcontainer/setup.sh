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

# 5. Git config from env vars
if [ -f /tmp/devpod-keys/env.sh ]; then
  source /tmp/devpod-keys/env.sh
  if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
  fi
  if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
  fi
fi

# 6. Git signing config (after GPG import)
git config --global commit.gpgsign true

# Wait for GPG agent to be ready
for i in 1 2 3 4 5; do
  SIGNING_KEY=$(gpg --list-secret-subkeys --keyid-format long 2>/dev/null | grep "^\s*ssb" | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)
  if [ -n "$SIGNING_KEY" ]; then
    break
  fi
  sleep 1
done

# Fallback to primary key
if [ -z "$SIGNING_KEY" ]; then
  SIGNING_KEY=$(gpg --list-secret-keys --keyid-format long 2>/dev/null | grep "^sec" | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)
fi

if [ -n "$SIGNING_KEY" ]; then
  git config --global user.signingkey "$SIGNING_KEY"
fi
