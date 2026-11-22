#!/usr/bin/env bash
# rice-setup.sh — Gruvbox / SecOps terminal & CLI rice + kgx + notify deps.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "→ Host packages for rice / notifications..."
sudo pacman -S --needed --noconfirm libnotify btop fastfetch htop starship \
  gnome-text-editor gnome-console kitty ghostty alacritty || true

echo "→ Stow rice packages..."
for pkg in ghostty alacritty kitty fastfetch htop btop starship vscode continue \
  gnome-text-editor applications; do
  [[ -d "stow/$pkg" ]] || continue
  stow -d stow -t "$HOME" -R "$pkg" 2>/dev/null \
    || stow -d stow -t "$HOME" "$pkg" 2>/dev/null \
    || echo "WARN: stow $pkg failed"
done

# GNOME Console (kgx) — dark + monospace (no Stow path for dconf)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.Console theme "'night'" 2>/dev/null || true
  gsettings set org.gnome.Console custom-font "'JetBrainsMono Nerd Font 13'" 2>/dev/null || true
  gsettings set org.gnome.Console use-system-font false 2>/dev/null || true
  # Never show notifications on lock screen
  gsettings set org.gnome.desktop.notifications show-in-lock-screen false 2>/dev/null || true
fi

# Long-command notify threshold (shell-functions default; avoid duplicate appends)
if ! grep -qs 'CMD_NOTIFY_THRESHOLD' "$HOME/.zshrc" "$HOME/.zshrc.local" 2>/dev/null; then
  echo 'export CMD_NOTIFY_THRESHOLD="${CMD_NOTIFY_THRESHOLD:-15}"' >>"$HOME/.zshrc.local" 2>/dev/null || true
fi

echo "✓ rice applied (Kitty host colors stay stock; lab-* use --override accents)"
