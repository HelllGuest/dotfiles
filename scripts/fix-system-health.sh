#!/bin/bash
# Apply sudo-required fixes from system log triage (zram, TLP noise, RDP TPM).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== fix-system-health ==="

bash "${REPO_ROOT}/scripts/zram-setup.sh"

if pacman -Q tlp-rdw >/dev/null 2>&1; then
    echo "Removing tlp-rdw..."
    sudo pacman -Rns --noconfirm tlp-rdw
fi
if pacman -Q tlp >/dev/null 2>&1; then
    echo "Removing tlp..."
    sudo pacman -Rns --noconfirm tlp
fi

if id gnome-remote-desktop >/dev/null 2>&1 && ! id gnome-remote-desktop | grep -q '\btss\b'; then
    echo "Adding gnome-remote-desktop to tss group..."
    sudo usermod -aG tss gnome-remote-desktop
fi

# System grd binds :3389 without user-session creds; desktop sharing uses user daemon only.
if systemctl is-enabled --quiet gnome-remote-desktop.service 2>/dev/null; then
    echo "Disabling system gnome-remote-desktop (user-session RDP owns credentials)..."
    sudo systemctl disable --now gnome-remote-desktop.service
fi
if systemctl --user is-active --quiet gnome-remote-desktop.service 2>/dev/null; then
    systemctl --user restart gnome-remote-desktop.service
fi

echo "Done. Restart Ghostty to pick up shortcut fix. Reboot recommended for zram early-boot."
