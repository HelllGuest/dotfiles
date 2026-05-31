#!/bin/bash
# profiles/thinkpad-x1.sh
# ThinkPad X1 Yoga Gen 5 — Comet Lake-U, Intel UHD, convertible

echo "Applying ThinkPad X1 Yoga Gen 5 optimizations..."

# 1. MSR throttling fix (AUR: throttled)
if command -v throttled >/dev/null 2>&1; then
    echo "Enabling throttled..."
    sudo systemctl enable --now throttled || true
fi

# 2. DPTF thermal management (may exit on ThinkPads with DYTC — throttled covers MSR)
if command -v thermald >/dev/null 2>&1; then
    echo "Enabling thermald..."
    sudo systemctl unmask thermald 2>/dev/null || true
    sudo systemctl enable thermald 2>/dev/null || true
    if ! sudo systemctl start thermald 2>/dev/null; then
        echo "Note: thermald unsupported with thinkpad_acpi DYTC on this model; throttled remains primary."
    fi
fi

# 3. GNOME power profiles (conflicts with TLP — do not run both)
if systemctl is-active --quiet tlp 2>/dev/null; then
    echo "Disabling TLP (use power-profiles-daemon with GNOME)..."
    sudo systemctl disable --now tlp || true
fi
if command -v powerprofilesctl >/dev/null 2>&1; then
    echo "Enabling power-profiles-daemon..."
    sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
    sudo systemctl enable --now power-profiles-daemon || true
fi

# 4. Tablet mode: auto-rotate + on-screen keyboard
if pacman -Q iio-sensor-proxy >/dev/null 2>&1; then
    echo "Enabling iio-sensor-proxy..."
    sudo systemctl enable --now iio-sensor-proxy || true
fi

# 5. Fan control (optional — requires /etc/thinkfan.conf)
if [ -f /etc/thinkfan.conf ] && command -v thinkfan >/dev/null 2>&1; then
    echo "Enabling thinkfan..."
    sudo systemctl enable --now thinkfan || true
fi

# 6. Firmware updates
if command -v fwupdmgr >/dev/null 2>&1; then
    echo "Refreshing firmware metadata..."
    sudo fwupdmgr refresh || true
fi

# 7. Thunderbolt
if command -v boltctl >/dev/null 2>&1; then
    echo "Enabling bolt..."
    sudo systemctl enable --now bolt || true
fi

# 8. Materialize modprobe.d files (stow symlinks break in initramfs)
for conf in /etc/modprobe.d/i915.conf; do
    if [ -L "$conf" ]; then
        echo "Materializing $conf for mkinitcpio..."
        target=$(readlink -f "$conf")
        tmp=$(mktemp)
        cp "$target" "$tmp"
        sudo cp "$tmp" "$conf"
        rm -f "$tmp"
    fi
done

# 9. Rebuild UKI/initramfs when kernel cmdline changed
if [ -f /etc/kernel/cmdline ] && command -v mkinitcpio >/dev/null 2>&1; then
    echo "Rebuilding initramfs/UKI for new kernel cmdline..."
    sudo mkinitcpio -P || true
fi

# 4. Tablet mode handler (X1 Yoga)
if command -v systemctl >/dev/null 2>&1; then
    echo "Enabling yoga-tablet-mode user service..."
    systemctl --user enable --now yoga-tablet-mode.service 2>/dev/null || true
fi

echo "ThinkPad X1 Yoga optimizations applied."
echo "Reboot recommended for i915 module options and mem_sleep_default=s2idle."
