#!/bin/bash
# profiles/thinkpad-x1.sh
# ThinkPad X1 Yoga Gen 5 — Comet Lake-U, Intel UHD, convertible

echo "Applying ThinkPad X1 Yoga Gen 5 optimizations..."

# 1-2. Thermal/power: Comet Lake (10th gen) is firmware-managed (Intel DPTF) +
#       power-profiles-daemon. No MSR/undervolt tool: 'throttled' is obsolete here
#       (CPU undervolt has been locked since 10th gen via the Plundervolt microcode
#       mitigation), and thermald self-exits on ThinkPads with thinkpad_acpi DYTC.
#       Thermal is handled by firmware; PPD (section 3) handles power profiles.

# 3. GNOME power profiles (conflicts with TLP — do not run both)
if systemctl is-active --quiet tlp 2>/dev/null; then
    echo "Disabling TLP (use power-profiles-daemon with GNOME)..."
    sudo systemctl disable --now tlp || true
fi
if pacman -Q tlp-rdw >/dev/null 2>&1; then
    echo "Removing tlp-rdw (NM hooks invoke tlp without tlp.service; spams journal)..."
    sudo pacman -Rns --noconfirm tlp-rdw || true
fi
if pacman -Q tlp >/dev/null 2>&1; then
    echo "Removing tlp (power-profiles-daemon is primary on GNOME)..."
    sudo pacman -Rns --noconfirm tlp || true
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

# 8. Materialize zram-generator.conf (stow symlink into $HOME breaks at early boot)
if [ -f "${BASH_SOURCE[0]%/*}/../scripts/zram-setup.sh" ]; then
    bash "${BASH_SOURCE[0]%/*}/../scripts/zram-setup.sh" || true
elif [ -f "$HOME/dotfiles/scripts/zram-setup.sh" ]; then
    bash "$HOME/dotfiles/scripts/zram-setup.sh" || true
fi

# 9. Materialize modprobe.d files (stow symlinks break in initramfs)
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

# 10. Desktop RDP: user daemon has creds; system daemon steals :3389 with none set
if systemctl is-enabled --quiet gnome-remote-desktop.service 2>/dev/null; then
    echo "Disabling system gnome-remote-desktop (use user-session RDP)..."
    sudo systemctl disable --now gnome-remote-desktop.service || true
fi

# 11. TPM access for gnome-remote-desktop system credentials
if id gnome-remote-desktop >/dev/null 2>&1; then
    if ! id gnome-remote-desktop | grep -q '\btss\b'; then
        echo "Adding gnome-remote-desktop to tss group (TPM credential store)..."
        sudo usermod -aG tss gnome-remote-desktop || true
    fi
fi

# 12. Rebuild UKI/initramfs when kernel cmdline changed
if [ -f /etc/kernel/cmdline ] && command -v mkinitcpio >/dev/null 2>&1; then
    echo "Rebuilding initramfs/UKI for new kernel cmdline..."
    sudo mkinitcpio -P || true
    # mkinitcpio -P does not trigger the pacman zz-sbctl hook — re-sign UKIs when SB is set up
    if command -v sbctl >/dev/null 2>&1 && [ -d /etc/sbctl/keys ]; then
        echo "Re-signing UKIs for Secure Boot..."
        for f in /boot/EFI/Linux/arch-linux-lts.efi /boot/EFI/Linux/arch-linux-lts-fallback.efi \
                 /boot/EFI/Linux/arch-linux-hardened.efi /boot/EFI/Linux/arch-linux-hardened-fallback.efi; do
            [ -f "$f" ] && sudo sbctl sign -s "$f" || true
        done
        sudo sbctl verify 2>/dev/null || echo "WARN: sbctl verify failed — run: sudo sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi"
    fi
fi

# 13. Tablet mode handler (X1 Yoga)
if command -v systemctl >/dev/null 2>&1; then
    echo "Enabling yoga-tablet-mode user service..."
    systemctl --user enable --now yoga-tablet-mode.service 2>/dev/null || true
fi

echo "ThinkPad X1 Yoga optimizations applied."
echo "Reboot recommended for i915 module options and the mem_sleep_default kernel param."
