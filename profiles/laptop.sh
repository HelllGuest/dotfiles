#!/bin/bash
# Laptop specific settings (fallback when hostname/profile is not P15 or T14s)
echo "Applying Laptop profile..."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

if is_thinkpad_t14s; then
    if [ -f "$REPO_ROOT/profiles/thinkpad-t14s.sh" ]; then
        # shellcheck source=thinkpad-t14s.sh
        source "$REPO_ROOT/profiles/thinkpad-t14s.sh"
        return 0 2>/dev/null || exit 0
    fi
fi

# General laptop tools (non-ThinkPad / other ThinkPads)
if pacman -Q tuned-ppd >/dev/null 2>&1; then
    # tuned-ppd provides+conflicts power-profiles-daemon — keep tuned.
    sudo pacman -S --needed --noconfirm brightnessctl
    sudo systemctl enable --now tuned tuned-ppd || true
else
    sudo pacman -S --needed --noconfirm power-profiles-daemon brightnessctl
    sudo systemctl enable --now power-profiles-daemon
fi

# Legacy touchpad udev/inhibit cleanup (if present)
if [ -f "$REPO_ROOT/scripts/cleanup-input-overrides.sh" ]; then
    bash "$REPO_ROOT/scripts/cleanup-input-overrides.sh" || true
fi
