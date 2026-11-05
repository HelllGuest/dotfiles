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

if is_thinkpad_t14s; then
    if [ -f "profiles/thinkpad-t14s.sh" ]; then
        # shellcheck source=/dev/null
        source "profiles/thinkpad-t14s.sh"
        exit 0
    fi
fi

# General laptop tools (non-ThinkPad)
sudo pacman -S --needed --noconfirm power-profiles-daemon brightnessctl
sudo systemctl enable --now power-profiles-daemon

# Legacy touchpad udev/inhibit cleanup (if present)
if [ -f "$REPO_ROOT/scripts/cleanup-input-overrides.sh" ]; then
    bash "$REPO_ROOT/scripts/cleanup-input-overrides.sh" || true
fi
