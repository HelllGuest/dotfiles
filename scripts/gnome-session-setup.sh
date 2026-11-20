#!/usr/bin/env bash
# gnome-session-setup.sh — GNOME session dconf, extensions, cleanup

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"

echo "→ GNOME session setup..."

PAC_PKGS=(gnome-shell-extensions gnome-tweaks inter-font)
sudo pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || \
  pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || true

mkdir -p "$HOME/.config"
cd "$STOW_DIR" || exit 1
# Empty gnome-session stow package removed; dconf/extensions below are enough.
if ! stow -R --adopt -t "$HOME" proton-vpn 2>/dev/null; then
  stow -t "$HOME" proton-vpn 2>/dev/null || \
    echo "⚠ stow proton-vpn skipped (extension likely already present)" >&2
fi

if [[ -f "$REPO_ROOT/gnome/dconf/user.conf" ]]; then
  echo "→ Applying session dconf..."
  dconf load / < "$REPO_ROOT/gnome/dconf/user.conf"
fi

if [[ -f "$REPO_ROOT/scripts/reset-input-defaults.sh" ]]; then
  bash "$REPO_ROOT/scripts/reset-input-defaults.sh" || true
fi

if [[ -f "$REPO_ROOT/scripts/cleanup-input-overrides.sh" ]]; then
  bash "$REPO_ROOT/scripts/cleanup-input-overrides.sh" || true
fi

# Fetch Dash2Dock / Caffeine, then enable extensions.txt (Blur My Shell and the
# Full-pack extensions come from Aura Glass: scripts/theme-setup.sh)
if [[ -f "$REPO_ROOT/scripts/install-extensions.sh" ]]; then
  echo "→ Fetching/enabling GNOME extensions..."
  GNOME_EXT_FETCH=1 bash "$REPO_ROOT/scripts/install-extensions.sh" || true
fi

if [[ -f "$REPO_ROOT/gnome/dconf/extensions.conf" ]]; then
  echo "→ Applying extension dconf..."
  dconf load / < "$REPO_ROOT/gnome/dconf/extensions.conf" || true
fi

systemctl --user daemon-reload 2>/dev/null || true
# Drop leftover tablet watcher from older installs.
systemctl --user disable --now yoga-tablet-mode.service 2>/dev/null || true

fc-cache -fv &>/dev/null || true

echo ""
echo "✓ GNOME session configured."
echo "  Log out/in (or restart GNOME Shell) to reload extensions."
echo "  Super+1-4 workspaces | Super+Return kitty | Shell 51"
