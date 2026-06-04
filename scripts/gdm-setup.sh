#!/usr/bin/env bash
# gdm-setup.sh — deploy GDM greeter config and compile dconf database
# Copies into /etc (not stow symlinks): gdm user cannot read $HOME paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"
GDM_SRC="$STOW_DIR/gdm/etc"

echo "→ Configuring GDM..."

if ! pacman -Qi gdm >/dev/null 2>&1; then
    echo "Installing gdm..."
    sudo pacman -S --needed --noconfirm gdm
fi

if [[ ! -d "$GDM_SRC" ]]; then
    echo "Missing GDM stow source: $GDM_SRC" >&2
    exit 1
fi

if [[ -f /etc/gdm/custom.conf && ! -L /etc/gdm/custom.conf ]]; then
    sudo cp -a /etc/gdm/custom.conf "/etc/gdm/custom.conf.bak.$(date +%Y%m%d)" 2>/dev/null || true
fi

echo "→ Removing old stow symlinks (if any)..."
if command -v stow >/dev/null 2>&1; then
    sudo stow -d "$STOW_DIR" -t / -D gdm 2>/dev/null || true
fi

echo "→ Copying GDM config into /etc..."
if command -v rsync >/dev/null 2>&1; then
    sudo rsync -a "$GDM_SRC/" /etc/
else
    sudo cp -a "$GDM_SRC/." /etc/
fi

echo "→ Fixing ownership of system GDM files..."
sudo chown root:root /etc/gdm/custom.conf 2>/dev/null || true
sudo chown -R root:root /etc/systemd/system/gdm.service.d
sudo chown -R root:root /etc/dconf/db/gdm.d
sudo chown root:root /etc/dconf/profile/gdm 2>/dev/null || true
sudo chown root:root /etc/udev/rules.d/61-gdm-wayland.rules 2>/dev/null || true

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

if [ -L /etc/dconf/profile/gdm ] && readlink /etc/dconf/profile/gdm | grep -q "$HOME"; then
    echo "⚠ GDM dconf profile still symlinks into $HOME — deploy failed?" >&2
    exit 1
fi

echo ""
echo "GDM config applied. Restart GDM to see login screen changes:"
echo "  sudo systemctl restart gdm   (logs you out)"
echo "  or reboot"
