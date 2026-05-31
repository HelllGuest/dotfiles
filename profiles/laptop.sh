#!/bin/bash
# Laptop specific settings
echo "Applying Laptop profile..."

# Check if we are on a ThinkPad
if dmidecode -s system-product-name | grep -qi "ThinkPad"; then
    if [ -f "profiles/thinkpad-x1.sh" ]; then
        source "profiles/thinkpad-x1.sh"
    fi
fi

# General laptop tools
sudo pacman -S --needed tlp brightnessctl
sudo systemctl enable --now tlp
