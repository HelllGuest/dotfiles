#!/bin/bash
# profiles/thinkpad-p15.sh
# ThinkPad P15 Gen 1 — Comet Lake-H (i7/Xeon W), Intel UHD P630 + NVIDIA Quadro
# (Turing, e.g. T1000/T2000/RTX) on Optimus. Mobile workstation, not convertible.
#
# Sets up the proprietary NVIDIA stack for a hybrid (Optimus) laptop on Wayland:
# early KMS, nouveau blacklist, DRM modeset, suspend fix, and dGPU runtime power
# management so the discrete GPU powers down on battery. The Intel iGPU stays the
# primary renderer; the NVIDIA card is used via PRIME render offload on demand.
#
# Driver packages (nvidia-open-dkms, nvidia-utils, nvidia-prime, egl-wayland) are
# installed by the packages/pacman.txt step. Turing and newer is supported by the
# open kernel modules; DKMS rebuilds for both linux-lts and linux-hardened.

echo "Applying ThinkPad P15 Gen 1 (Optimus) optimizations..."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../provision/lib/dmi.sh
source "$REPO_ROOT/provision/lib/dmi.sh"

if ! is_thinkpad_p15; then
    echo "WARN: DMI does not look like a ThinkPad P15 — applying anyway (forced by profile)."
fi
if ! has_nvidia_gpu; then
    echo "No NVIDIA GPU detected — this profile is for the Optimus P15. Skipping NVIDIA setup."
fi

# 1. Power: power-profiles-daemon (GNOME). Remove TLP if present (they conflict).
if pacman -Q tlp >/dev/null 2>&1; then
    echo "Removing tlp (power-profiles-daemon is primary on GNOME)..."
    sudo pacman -Rns --noconfirm tlp tlp-rdw 2>/dev/null || true
fi
if command -v powerprofilesctl >/dev/null 2>&1; then
    sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
    sudo systemctl enable --now power-profiles-daemon || true
fi

# 2. Thunderbolt + firmware
command -v boltctl  >/dev/null 2>&1 && sudo systemctl enable --now bolt || true
command -v fwupdmgr >/dev/null 2>&1 && sudo fwupdmgr refresh || true

# 2.5 Battery longevity: thinkpad_acpi charge window 70–80 (UPower rule + thresholds)
install_udev_rule \
    "$REPO_ROOT/system/etc/udev/rules.d/61-thinkpad-charge-limit.rules" \
    "/etc/udev/rules.d/61-thinkpad-charge-limit.rules" \
    power_supply
if [[ -f "$REPO_ROOT/system/scripts/thinkpad-charge-thresholds.sh" ]]; then
    echo "Setting ThinkPad charge thresholds 70–80..."
    bash "$REPO_ROOT/system/scripts/thinkpad-charge-thresholds.sh" || true
fi

INITRAMFS_CHANGED=0
if has_nvidia_gpu; then
    # 3. modprobe options: blacklist nouveau, enable DRM modeset + framebuffer
    #    (required for Wayland/GDM on NVIDIA), and Turing runtime power management
    #    (0x02 = fine-grained: dGPU powers down when idle — key for battery life).
    _nv_conf='# ThinkPad P15 Gen 1 — NVIDIA Optimus (managed by profiles/thinkpad-p15.sh)
blacklist nouveau
blacklist nvidiafb
install nouveau /bin/false
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1'
    if [ ! -f /etc/modprobe.d/nvidia.conf ] || ! cmp -s <(printf '%s\n' "$_nv_conf") /etc/modprobe.d/nvidia.conf; then
        echo "Writing /etc/modprobe.d/nvidia.conf (blacklist nouveau, modeset, runtime PM)..."
        printf '%s\n' "$_nv_conf" | sudo install -Dm644 /dev/stdin /etc/modprobe.d/nvidia.conf
        INITRAMFS_CHANGED=1
    fi
    unset _nv_conf

    # 4. Early KMS: load NVIDIA modules in the initramfs so the console and GDM
    #    come up on the right DRM driver. Insert into mkinitcpio MODULES=() if absent.
    if [ -f /etc/mkinitcpio.conf ] && ! grep -qE '^MODULES=.*nvidia' /etc/mkinitcpio.conf; then
        echo "Adding NVIDIA modules to mkinitcpio MODULES..."
        sudo sed -i -E \
          's/^MODULES=\((.*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
          /etc/mkinitcpio.conf
        # collapse a leading space if MODULES was empty: "( nvidia" -> "(nvidia"
        sudo sed -i -E 's/^MODULES=\(\s+/MODULES=(/' /etc/mkinitcpio.conf
        INITRAMFS_CHANGED=1
    fi

    # 5. Kernel cmdline: modeset + early nouveau blacklist (UKI embeds /etc/kernel/cmdline).
    if [ -f /etc/kernel/cmdline ]; then
        if ! grep -q 'nvidia_drm.modeset=1' /etc/kernel/cmdline; then
            echo "Appending nvidia_drm.modeset=1 to /etc/kernel/cmdline..."
            sudo sed -i 's/[[:space:]]*$/ nvidia_drm.modeset=1/' /etc/kernel/cmdline
            INITRAMFS_CHANGED=1
        fi
        if ! grep -q 'rd.driver.blacklist=nouveau' /etc/kernel/cmdline; then
            echo "Appending rd.driver.blacklist=nouveau to /etc/kernel/cmdline..."
            sudo sed -i 's/[[:space:]]*$/ rd.driver.blacklist=nouveau/' /etc/kernel/cmdline
            INITRAMFS_CHANGED=1
        fi
    fi

    # 6. Suspend/resume: NVIDIA's services preserve VRAM across sleep (fixes the
    #    black-screen-after-resume that Optimus laptops hit otherwise).
    echo "Enabling NVIDIA suspend/resume/hibernate services..."
    sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true

    # 7. dGPU runtime power management udev rules (auto-suspend the card when idle).
    echo "Writing /etc/udev/rules.d/80-nvidia-pm.rules..."
    sudo install -Dm644 /dev/stdin /etc/udev/rules.d/80-nvidia-pm.rules <<'EOF'
# NVIDIA dynamic power management — bind/unbind + runtime auto on the dGPU.
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
EOF
fi

# 8. Rebuild initramfs/UKI only when modprobe/MODULES/cmdline changed, then re-sign for Secure Boot.
if [[ $INITRAMFS_CHANGED -eq 1 ]] && command -v mkinitcpio >/dev/null 2>&1; then
    echo "Rebuilding initramfs/UKI..."
    sudo mkinitcpio -P || true
    if command -v sbctl >/dev/null 2>&1 && { [ -d /var/lib/sbctl/keys ] || [ -d /etc/sbctl/keys ]; }; then
        echo "Re-signing UKIs for Secure Boot..."
        for f in /boot/EFI/Linux/arch-linux*.efi; do
            [ -f "$f" ] && sudo sbctl sign -s "$f" || true
        done
        sudo sbctl verify 2>/dev/null || echo "WARN: sbctl verify failed — re-sign manually."
    fi
fi

echo "ThinkPad P15 Gen 1 optimizations applied."
if [[ $INITRAMFS_CHANGED -eq 1 ]]; then
    echo "Reboot required: nouveau blacklist, NVIDIA early KMS, and the modeset cmdline take effect at boot."
fi
echo "Run GPU apps on the dGPU with: prime-run <app>   (e.g. prime-run glxinfo | grep renderer)"
