#!/bin/bash
# Laptop specific settings
echo "Applying Laptop profile..."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

if is_thinkpad_x1; then
    if [ -f "profiles/thinkpad-x1.sh" ]; then
        # shellcheck source=/dev/null
        source "profiles/thinkpad-x1.sh"
        exit 0
    fi
fi

# General laptop tools (non-ThinkPad)
sudo pacman -S --needed --noconfirm power-profiles-daemon brightnessctl
sudo systemctl enable --now power-profiles-daemon
