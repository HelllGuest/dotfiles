#!/usr/bin/env bash
# gdm-setup.sh — deploy GDM greeter config and compile dconf database

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"

echo "→ Configuring GDM..."

if ! pacman -Qi gdm >/dev/null 2>&1; then
    echo "Installing gdm..."
    sudo pacman -S --needed --noconfirm gdm
fi

if [[ -f /etc/gdm/custom.conf && ! -L /etc/gdm/custom.conf ]]; then
    sudo cp -a /etc/gdm/custom.conf "/etc/gdm/custom.conf.bak.$(date +%Y%m%d)" 2>/dev/null || true
    sudo rm -f /etc/gdm/custom.conf
fi

cd "$STOW_DIR"
if command -v stow >/dev/null 2>&1; then
    sudo stow -d "$STOW_DIR" -t / -R gdm
else
    echo "GNU stow required for GDM config." >&2
    exit 1
fi

echo "→ Compiling GDM dconf database..."
sudo dconf update

echo "→ Reloading udev and systemd..."
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=drm
sudo systemctl daemon-reload

if grep -q 'WaylandEnable=true' /etc/gdm/custom.conf 2>/dev/null; then
    echo "✓ WaylandEnable=true"
else
    echo "⚠ WaylandEnable not set in /etc/gdm/custom.conf"
fi

echo ""
echo "GDM config applied. Restart GDM to see login screen changes:"
echo "  sudo systemctl restart gdm   (logs you out)"
echo "  or reboot"
