#!/usr/bin/env bash
# gnome-session-setup.sh — GNOME session dconf, extensions, X1 Yoga tablet handler

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"

echo "→ GNOME session setup..."

PAC_PKGS=(gnome-shell-extensions gnome-tweaks iio-sensor-proxy inter-font)
sudo pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || \
  pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || true

sudo systemctl enable --now iio-sensor-proxy.service 2>/dev/null || true

mkdir -p "$HOME/.config"
cd "$STOW_DIR" || exit 1
stow -R -t "$HOME" gnome-session
stow -R -t "$HOME" proton-vpn 2>/dev/null || stow -t "$HOME" proton-vpn
chmod +x "$HOME/.config/gnome-session/scripts/tablet-mode-handler.sh"

if [[ -f "$REPO_ROOT/gnome/dconf/user.conf" ]]; then
  echo "→ Applying session dconf..."
  dconf load / < "$REPO_ROOT/gnome/dconf/user.conf"
fi

if [[ -f "$REPO_ROOT/scripts/install-extensions.sh" ]]; then
  bash "$REPO_ROOT/scripts/install-extensions.sh" || true
fi

if [[ -f "$REPO_ROOT/gnome/dconf/extensions.conf" ]]; then
  echo "→ Applying extension dconf..."
  dconf load / < "$REPO_ROOT/gnome/dconf/extensions.conf" || true
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now yoga-tablet-mode.service 2>/dev/null || true

fc-cache -fv &>/dev/null || true

echo ""
echo "✓ GNOME session configured."
echo "  Log out/in (or restart GNOME Shell) to reload extensions."
echo "  Super+1-4 workspaces | Super+Return kitty"
