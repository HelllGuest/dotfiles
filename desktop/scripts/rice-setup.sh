#!/usr/bin/env bash
# rice-setup.sh — Gruvbox / SecOps terminal & CLI rice + kgx notify deps.
# Console font/theme: desktop/scripts/gnome-console-setup.sh (single writer).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

RICE_FAILED=0
fail_rice() {
    echo "✗ $1" >&2
    RICE_FAILED=1
}

echo "→ Host packages for rice / notifications..."
if ! sudo pacman -S --needed --noconfirm libnotify btop fastfetch htop starship \
  gnome-text-editor gnome-console kitty ghostty alacritty contour; then
    fail_rice "pacman rice packages failed"
fi

echo "→ Stow rice packages..."
for pkg in ghostty alacritty kitty contour fastfetch htop btop starship vscode continue \
  gnome-text-editor applications nvim; do
  [[ -d "stow/$pkg" ]] || continue
  if ! stow -d stow -t "$HOME" -R "$pkg" 2>/dev/null \
    && ! stow -d stow -t "$HOME" "$pkg" 2>/dev/null; then
    fail_rice "stow $pkg failed"
  fi
done

# Kitty include is not optional; seed a quiet stub unless rice-theme already linked a theme.
_kitty_local="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/theme.local.conf"
if [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/kitty && ! -e $_kitty_local ]]; then
  printf '# rice-theme: default (no override). Do not edit; switched via rice-theme.\n' >"$_kitty_local" \
    || fail_rice "could not write kitty theme.local.conf stub"
fi
unset _kitty_local

# Lock-screen notifications off (privacy). kgx theme/font: gnome-console-setup.sh + dconf/user.conf.
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.notifications show-in-lock-screen false \
    || fail_rice "gsettings show-in-lock-screen failed"
fi

# Long-command notify threshold (shell-functions default; avoid duplicate appends)
if ! grep -qs 'CMD_NOTIFY_THRESHOLD' "$HOME/.zshrc" "$HOME/.zshrc.local" 2>/dev/null; then
  echo 'export CMD_NOTIFY_THRESHOLD="${CMD_NOTIFY_THRESHOLD:-15}"' >>"$HOME/.zshrc.local" 2>/dev/null \
    || fail_rice "could not append CMD_NOTIFY_THRESHOLD to ~/.zshrc.local"
fi

if (( RICE_FAILED )); then
  echo "✗ rice finished with failures (re-run after fixing the ✗ lines above)" >&2
  exit 1
fi
echo "✓ rice applied (switch with: rice-theme gruvbox|secops; preview: rice-theme --dry gruvbox)"
