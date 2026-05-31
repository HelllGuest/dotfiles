#!/bin/bash
# Laptop specific settings
echo "Applying Laptop profile..."

# Check if we are on a ThinkPad
if dmidecode -s system-product-name 2>/dev/null | grep -qi "ThinkPad"; then
    if [ -f "profiles/thinkpad-x1.sh" ]; then
        source "profiles/thinkpad-x1.sh"
        exit 0
    fi
fi

# General laptop tools (non-ThinkPad)
sudo pacman -S --needed --noconfirm power-profiles-daemon brightnessctl
sudo systemctl enable --now power-profiles-daemon
