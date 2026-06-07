#!/usr/bin/env bash
# gnome-session-setup.sh — GNOME session dconf, extensions, X1 Yoga tablet handler

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"

echo "→ GNOME session setup..."

PAC_PKGS=(gnome-shell-extensions gnome-tweaks iio-sensor-proxy inter-font papirus-icon-theme)
sudo pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || \
  pacman -S --needed --noconfirm "${PAC_PKGS[@]}" 2>/dev/null || true

AUR_PKGS=(
  catppuccin-gtk-theme-mocha
  catppuccin-gtk-theme-latte
  catppuccin-cursors-mocha-dark
  gnome-shell-extension-blur-my-shell
  gnome-shell-extension-caffeine
  gnome-shell-extension-appindicator
  gnome-shell-extension-tactile
  gnome-shell-extension-just-perfection-desktop
  gnome-shell-extension-vitals
  gnome-shell-extension-gesture-improvements
  gnome-shell-extension-nightthemeswitcher
  papirus-folders-git
)

if command -v paru >/dev/null 2>&1; then
  for pkg in "${AUR_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null 2>&1 || paru -S --needed --noconfirm "$pkg" || true
  done
elif command -v yay >/dev/null 2>&1; then
  for pkg in "${AUR_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null 2>&1 || yay -S --needed --noconfirm "$pkg" || true
  done
else
  echo "  ⚠ No AUR helper — install extensions/themes manually (see packages/aur.txt)"
fi

sudo systemctl enable --now iio-sensor-proxy.service 2>/dev/null || true

mkdir -p "$HOME/.config"
cd "$STOW_DIR"
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

mkdir -p "$HOME/.local/bin"
chmod +x "$REPO_ROOT/scripts/night-theme-hook.sh"
ln -sf "$REPO_ROOT/scripts/night-theme-hook.sh" "$HOME/.local/bin/night-theme-hook"

if command -v gnome-extensions >/dev/null 2>&1 \
  && gnome-extensions list --enabled 2>/dev/null | grep -q 'nightthemeswitcher@romainvigier.fr'; then
  echo "→ Syncing Catppuccin GTK theme to current day/night state..."
  bash "$REPO_ROOT/scripts/night-theme-hook.sh" sync || true
  gnome-extensions disable nightthemeswitcher@romainvigier.fr >/dev/null 2>&1 || true
  gnome-extensions enable nightthemeswitcher@romainvigier.fr >/dev/null 2>&1 || true
fi

if command -v papirus-folders >/dev/null 2>&1; then
  papirus-folders -C cat-mocha-blue --theme Papirus-Dark 2>/dev/null || true
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now yoga-tablet-mode.service 2>/dev/null || true

fc-cache -fv &>/dev/null || true

echo ""
echo "✓ GNOME session configured."
echo "  Log out/in (or restart GNOME Shell) to reload extensions."
echo "  Super+1-4 workspaces | Super+T Tactile | Super+Return kitty"
