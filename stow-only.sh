#!/bin/bash

# stow-only.sh
# Applies symlinks for dotfiles that don't require root.

set -e

# Stow targets $HOME. Never sudo ./stow-only.sh.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "error: run as your desktop user, not root (sudo ./stow-only.sh stows into /root)" >&2
    exit 1
fi

echo "Applying dotfiles..."

# Ensure ~/.config exists
mkdir -p "$HOME/.config"

STOW_CMD="stow"
if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow not found. Using minimal-stow fallback..."
    STOW_CMD="./scripts/minimal-stow.sh"
    chmod +x scripts/minimal-stow.sh
fi

# shellcheck source=scripts/lib/skel.sh
source scripts/lib/skel.sh
remove_unmodified_skel "$PWD/stow"
remove_stage_a_seeds "$PWD/stow"
cd stow || exit 1
for dir in */; do
    dir=${dir%/}
    if [ "$dir" = "zram" ] || [ "$dir" = "system" ] || [ "$dir" = "gdm" ]; then
        echo "Skipping $dir (requires root; use install.sh)."
        continue
    fi
    echo "Processing $dir..."
    if [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir"
    else
        "../$STOW_CMD" "$dir" "$HOME"
    fi
done
cd .. || exit 1

# User units shipped by stow packages are linked, not enabled. daemon-reload
# first: the manager has not seen the freshly linked unit file.
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now tmp-semgrep-cleanup.timer \
    || echo "○ could not enable tmp-semgrep-cleanup.timer (no user session?)"

echo "Symlinks applied successfully!"
echo ""
echo "GNOME session settings (workspaces, keybindings, etc.) are NOT in stow/."
echo "Mouse/touchpad/keyboard use GNOME defaults (reset by gnome-session-setup.sh)."
