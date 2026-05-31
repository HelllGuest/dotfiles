#!/bin/bash

# profiles/thinkpad-x1.sh
# Specific optimizations for Lenovo ThinkPad hardware

echo "Applying ThinkPad-specific optimizations..."

# 1. Thermal & Throttling (Fix for Intel MSR lock)
if command -v throttled >/dev/null 2>&1; then
    echo "Enabling throttled service..."
    sudo systemctl enable --now throttled
fi

# 2. Fan Control
if [ -f "/etc/thinkfan.conf" ]; then
    echo "Enabling thinkfan..."
    # Note: Requires manual config of /etc/thinkfan.conf
    sudo systemctl enable --now thinkfan
fi

# 3. Power Management (Battery Thresholds)
if command -v tlp >/dev/null 2>&1; then
    echo "Configuring TLP..."
    sudo systemctl enable --now tlp
    # Example battery thresholds (Start charging at 75%, stop at 80%)
    # sudo tlp setcharge 75 80
fi

# 4. Firmware updates
if command -v fwupdmgr >/dev/null 2>&1; then
    echo "Refreshing firmware metadata..."
    sudo fwupdmgr get-updates || true
fi

# 5. Thunderbolt
if command -v boltctl >/dev/null 2>&1; then
    echo "Enabling bolt (Thunderbolt management)..."
    sudo systemctl enable --now bolt
fi

echo "ThinkPad optimizations applied."
