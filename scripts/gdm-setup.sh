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

echo "→ Installing GDM config into /etc (root-owned)..."
# Per-file install, never `cp -a`/`rsync -a`: those copy the repo owner onto /etc
# and its parent dirs (user-writable /etc; pacman hooks refuse unsafe paths).
while IFS= read -r -d '' src; do
    sudo install -D -m 0644 -o root -g root "$src" "/etc/${src#"$GDM_SRC"/}"
done < <(find "$GDM_SRC" -type f -print0)
# Repair parent dirs an older `rsync -a` handed to the repo owner, with the repo's
# mode (700 under umask 077). Non-recursive; only adds read/traverse, drops go-w.
while IFS= read -r -d '' dir; do
    sudo chown root:root "/etc${dir#"$GDM_SRC"}"
    sudo chmod u+rwx,go+rx,go-w "/etc${dir#"$GDM_SRC"}"
done < <(find "$GDM_SRC" -type d -print0)

echo "→ Compiling GDM dconf database..."
sudo dconf update

echo "→ Reloading udev and systemd..."
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=drm
sudo systemctl daemon-reload
sudo systemctl enable gdm.service 2>/dev/null || true

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
