#!/usr/bin/env bash
# git-setup.sh — stow git config, identity, optional signing and hooks

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GIT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git"
STOW_DIR="$REPO_ROOT/stow"

echo "→ Git config setup..."

# No TTY (piped/CI/VM serial): never block on identity/hooks prompts.
if [[ "${GIT_SETUP_NONINTERACTIVE:-}" != "1" && ! -t 0 ]]; then
  export GIT_SETUP_NONINTERACTIVE=1
  echo "  (stdin not a TTY → GIT_SETUP_NONINTERACTIVE=1)"
fi

sudo pacman -S --needed --noconfirm git git-delta pinentry-gnome3 2>/dev/null || \
  pacman -S --needed --noconfirm git git-delta pinentry-gnome3 2>/dev/null || true

if [[ ! -f /usr/lib/git-core/git-credential-libsecret ]]; then
  if [[ -d /usr/share/git/credential/libsecret ]]; then
    echo "→ Building git-credential-libsecret..."
    (cd /usr/share/git/credential/libsecret && sudo make) || echo "  ⚠ libsecret helper build failed; falling back to credential store."
  fi
fi

mkdir -p "$HOME/.config"
cd "$STOW_DIR" || exit 1

# Replace plain files that block stow (e.g. prior manual git config).
# Skip anything that already resolves into the stow package: when stow folded
# ~/.config/git into a single dir symlink, the files look "plain" but ARE the
# repo's tracked config, and removing them would delete them from the repo.
pkg_real="$(cd "$STOW_DIR/git/.config/git" && pwd -P)"
for f in config ignore work.conf personal.conf; do
  target="$HOME/.config/git/$f"
  [[ -e "$target" && "$(readlink -f "$target")" == "$pkg_real/"* ]] && continue
  if [[ -f "$target" && ! -L "$target" ]]; then
    cp -a "$target" "${target}.bak.$(date +%Y%m%d)" 2>/dev/null || true
    rm -f "$target"
  fi
done

if command -v stow >/dev/null 2>&1; then
  stow -R -t "$HOME" git
else
  echo "GNU stow required." >&2
  exit 1
fi

chmod +x "$GIT_CONFIG_DIR/templates/hooks/"* 2>/dev/null || true

# Machine-local settings (identity, signing, credential helper, templateDir)
# belong in ~/.gitconfig, not the tracked XDG config. `git config --global`
# writes to $XDG/git/config when ~/.gitconfig is absent — i.e. into this repo.
# git reads both files; ~/.gitconfig is read last, so its values win.
[[ -e "$HOME/.gitconfig" ]] || : >"$HOME/.gitconfig"

CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)
if [[ -n "$CURRENT_EMAIL" && "$CURRENT_EMAIL" != "your@email.com" && "${GIT_SETUP_NONINTERACTIVE:-}" == "1" ]]; then
  echo "  ✓ Identity already set: $(git config --global user.name) <$CURRENT_EMAIL>"
else
  DEFAULT_NAME=$(git config --global user.name 2>/dev/null || echo "")
  DEFAULT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
  # No built-in identity: this repo is public and runs on other people's machines.
  # Noninteractive: GIT_USER_NAME / GIT_USER_EMAIL, else leave identity unset.
  if [[ "${GIT_SETUP_NONINTERACTIVE:-}" == "1" ]]; then
    GIT_NAME="${GIT_USER_NAME:-$DEFAULT_NAME}"
    GIT_EMAIL="${GIT_USER_EMAIL:-$DEFAULT_EMAIL}"
    [[ $GIT_EMAIL == "your@email.com" ]] && GIT_EMAIL=""
  else
    echo ""
    read -rp "  Name  [${DEFAULT_NAME}]: " GIT_NAME
    read -rp "  Email [${DEFAULT_EMAIL}]: " GIT_EMAIL
    GIT_NAME="${GIT_NAME:-$DEFAULT_NAME}"
    GIT_EMAIL="${GIT_EMAIL:-$DEFAULT_EMAIL}"
  fi
  if [[ -n $GIT_NAME && -n $GIT_EMAIL ]]; then
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    echo "  ✓ Identity: $GIT_NAME <$GIT_EMAIL>"
  else
    echo "  ⚠ Git identity not set — later: git config --global user.name/user.email"
    echo "    (or rerun with GIT_USER_NAME=… GIT_USER_EMAIL=…)"
  fi
fi

if [[ "${GIT_SETUP_NONINTERACTIVE:-}" == "1" ]]; then
  HOOKS_SETUP="Y"
else
  read -rp "→ Install global commit hooks (Conventional Commits + pre-push)? (Y/n): " HOOKS_SETUP
  HOOKS_SETUP="${HOOKS_SETUP:-Y}"
fi
if [[ "${HOOKS_SETUP,,}" != "n" ]]; then
  git config --global init.templateDir "$GIT_CONFIG_DIR/templates"
  echo "  ✓ Hooks template: $GIT_CONFIG_DIR/templates"
  echo "    Apply to existing repo: git init (safe, non-destructive)"
else
  git config --global --unset init.templateDir 2>/dev/null || true
  echo "  Skipped hooks template."
fi

if [[ "${GIT_SETUP_NONINTERACTIVE:-}" != "1" ]]; then
  read -rp "→ Configure GPG commit signing? (y/N): " GPG_SETUP
  if [[ "${GPG_SETUP,,}" == "y" ]]; then
    GIT_NAME=$(git config --global user.name || true)
    GIT_EMAIL=$(git config --global user.email || true)
    gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep -A1 "sec" || true
    read -rp "  GPG key ID (Enter to generate Ed25519): " GPG_KEY
    if [[ -z "$GPG_KEY" ]]; then
      gpg --batch --gen-key <<EOF
%no-protection
Key-Type: EDDSA
Key-Curve: Ed25519
Name-Real: $GIT_NAME
Name-Email: $GIT_EMAIL
Expire-Date: 2y
EOF
      GPG_KEY=$(gpg --list-secret-keys --keyid-format=long "$GIT_EMAIL" 2>/dev/null \
        | grep "sec" | grep -oP '[A-F0-9]{16}' | head -1)
      echo "  Add to GitHub/GitLab:"
      gpg --armor --export "$GPG_KEY"
    fi
    if [[ -n "$GPG_KEY" ]]; then
      git config --global user.signingkey "$GPG_KEY"
      git config --global commit.gpgsign true
      git config --global tag.gpgSign true
      mkdir -p ~/.gnupg
      grep -q pinentry-gnome3 ~/.gnupg/gpg-agent.conf 2>/dev/null || \
        echo "pinentry-program /usr/bin/pinentry-gnome3" >> ~/.gnupg/gpg-agent.conf
      gpg-connect-agent reloadagent /bye &>/dev/null || true
      echo "  ✓ GPG signing: $GPG_KEY"
    fi
  fi

  read -rp "→ Configure SSH commit signing instead? (y/N): " SSH_SIGN
  if [[ "${SSH_SIGN,,}" == "y" ]]; then
    SSH_KEY=$(ls "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || ls "$HOME/.ssh/"id_*.pub 2>/dev/null | head -1)
    if [[ -n "$SSH_KEY" ]]; then
      ALLOWED_SIGNERS="$GIT_CONFIG_DIR/allowed_signers"
      GIT_EMAIL=$(git config --global user.email || true)
      echo "$GIT_EMAIL namespaces=\"git\" $(cat "$SSH_KEY")" >> "$ALLOWED_SIGNERS"
      git config --global gpg.format ssh
      git config --global user.signingkey "$SSH_KEY"
      git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
      git config --global commit.gpgsign true
      git config --global tag.gpgSign true
      echo "  ✓ SSH signing: $SSH_KEY"
    else
      echo "  ⚠ No SSH public key found."
    fi
  fi
fi

if [[ -f /usr/lib/git-core/git-credential-libsecret ]]; then
  git config --global credential.helper /usr/lib/git-core/git-credential-libsecret
else
  git config --global credential.helper store
  echo "  ⚠ libsecret helper missing; using credential store."
fi

if [[ -d "$REPO_ROOT/.git" ]]; then
  (cd "$REPO_ROOT" && git maintenance start 2>/dev/null) && \
    echo "  ✓ git maintenance timer registered for dotfiles" || \
    echo "  ⚠ git maintenance start skipped"
fi

echo ""
echo "✓ Git config ready."
echo "  git clone gh:user/repo"
echo "  git clone gl:user/repo"
