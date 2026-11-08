#!/bin/bash
# profiles/thinkpad-t14s.sh
# ThinkPad T14s Gen 3 AMD (21CQ/21CR) — Rembrandt-U, amdgpu, soldered LPDDR5
#
# Host addons this profile owns (PPD or tuned+tuned-ppd; no TLP):
#   * charge thresholds 70–80 via scripts/thinkpad-charge-thresholds.sh
#   * amd_iommu=on + amd_pstate=active (strip intel_iommu / i915 leftovers)
#   * packages/thinkpad-t14s.txt (mesa / vulkan-radeon / fprintd)
#   * fwupd refresh, bolt, bluetooth; sof-firmware via pacman.txt / installer
# Skip: ryzenadj (PRO EC often locks), thermald (DYTC firmware), TLP;
#       X1 fingerprint-disable udev (keep power-button FP)

echo "Applying ThinkPad T14s Gen 3 AMD optimizations..."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

if ! is_thinkpad_t14s; then
  echo "WARN: DMI is not type 21CQ/21CR — continuing anyway (forced by profile)."
fi

# Thermal/power: Rembrandt + thinkpad_acpi DYTC is firmware-managed.
# power-profiles-daemon, or tuned + tuned-ppd when t14s-arch-install chose it
# (no TLP — conflicts with both on GNOME).
if systemctl is-active --quiet tlp 2>/dev/null; then
  echo "Disabling TLP (use power-profiles-daemon with GNOME)..."
  sudo systemctl disable --now tlp || true
fi
if pacman -Q tlp-rdw >/dev/null 2>&1; then
  echo "Removing tlp-rdw..."
  sudo pacman -Rns --noconfirm tlp-rdw || true
fi
if pacman -Q tlp >/dev/null 2>&1; then
  echo "Removing tlp..."
  sudo pacman -Rns --noconfirm tlp || true
fi
# t14s-arch-install may pick tuned + tuned-ppd (PPD API for GNOME) instead.
if pacman -Q tuned-ppd >/dev/null 2>&1; then
  echo "Enabling tuned + tuned-ppd (power-profiles-daemon replacement)..."
  sudo systemctl enable --now tuned tuned-ppd || true
elif command -v powerprofilesctl >/dev/null 2>&1; then
  echo "Enabling power-profiles-daemon..."
  sudo systemctl unmask power-profiles-daemon 2>/dev/null || true
  sudo systemctl enable --now power-profiles-daemon || true
fi

# Battery longevity: thinkpad_acpi charge window (sysfs resets each boot)
if [[ -f "$REPO_ROOT/scripts/thinkpad-charge-thresholds.sh" ]]; then
  echo "Setting ThinkPad charge thresholds 70–80..."
  bash "$REPO_ROOT/scripts/thinkpad-charge-thresholds.sh" || true
fi

# Rembrandt extras (680M + FP) — pacman.txt is Intel-skewed (vulkan-intel).
# Manifest: packages/thinkpad-t14s.txt (keep arch-install-t14s.sh pacstrap in sync).
T14S_PKGS_FILE="$REPO_ROOT/packages/thinkpad-t14s.txt"
if [[ -f "$T14S_PKGS_FILE" ]] && command -v pacman >/dev/null 2>&1; then
  mapfile -t _t14s_pkgs < <(
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$T14S_PKGS_FILE" \
      | awk 'NF'
  )
  need_pkgs=()
  for p in "${_t14s_pkgs[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || need_pkgs+=("$p")
  done
  if ((${#need_pkgs[@]} > 0)); then
    echo "Installing T14s packages: ${need_pkgs[*]}..."
    sudo pacman -S --needed --noconfirm "${need_pkgs[@]}" || true
  fi
  unset _t14s_pkgs need_pkgs
fi

# Kernel cmdline: AMD Rembrandt (repair generic arch-install.sh intel leftovers).
CMDLINE_CHANGED=0
if [ -f /etc/kernel/cmdline ]; then
  if grep -qE 'intel_iommu=|i915\.' /etc/kernel/cmdline; then
    echo "Stripping intel_iommu / i915.* from /etc/kernel/cmdline..."
    sudo sed -i -E 's/[[:space:]]*intel_iommu=[^ ]*//g; s/[[:space:]]*i915\.[^ ]*//g' /etc/kernel/cmdline
    CMDLINE_CHANGED=1
  fi
  if ! grep -q 'amd_iommu=on' /etc/kernel/cmdline; then
    echo "Appending amd_iommu=on to /etc/kernel/cmdline..."
    sudo sed -i 's/[[:space:]]*$/ amd_iommu=on/' /etc/kernel/cmdline
    CMDLINE_CHANGED=1
  fi
  if ! grep -q 'amd_pstate=active' /etc/kernel/cmdline; then
    echo "Appending amd_pstate=active to /etc/kernel/cmdline..."
    sudo sed -i 's/[[:space:]]*$/ amd_pstate=active/' /etc/kernel/cmdline
    CMDLINE_CHANGED=1
  fi
  # collapse leftover double spaces from stripping
  if [[ $CMDLINE_CHANGED -eq 1 ]]; then
    sudo sed -i -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' /etc/kernel/cmdline
  fi
fi

# Drop X1-only i915 modprobe if present (system-setup skips it on non-X1, but leftovers possible)
if [ -f /etc/modprobe.d/i915.conf ]; then
  echo "Removing leftover /etc/modprobe.d/i915.conf (amdgpu host)..."
  sudo rm -f /etc/modprobe.d/i915.conf
  CMDLINE_CHANGED=1
fi

# Rebuild UKIs when cmdline/modprobe changed (sbctl mkinitcpio hook re-signs).
if [[ $CMDLINE_CHANGED -eq 1 ]] && command -v mkinitcpio >/dev/null 2>&1; then
  echo "Rebuilding initramfs/UKI after cmdline/modprobe change..."
  sudo mkinitcpio -P || true
fi

# Firmware updates
if command -v fwupdmgr >/dev/null 2>&1; then
  echo "Refreshing firmware metadata..."
  sudo fwupdmgr refresh || true
fi

# Thunderbolt / USB4 docks
if command -v boltctl >/dev/null 2>&1; then
  echo "Enabling bolt..."
  sudo systemctl enable --now bolt || true
fi

# Desktop RDP: user daemon has creds; system daemon steals :3389 with none set
if systemctl is-enabled --quiet gnome-remote-desktop.service 2>/dev/null; then
  echo "Disabling system gnome-remote-desktop (use user-session RDP)..."
  sudo systemctl disable --now gnome-remote-desktop.service || true
fi

if id gnome-remote-desktop >/dev/null 2>&1; then
  if ! id gnome-remote-desktop | grep -q '\btss\b'; then
    echo "Adding gnome-remote-desktop to tss group..."
    sudo usermod -aG tss gnome-remote-desktop || true
  fi
fi

# Bluetooth (bluez in packages/pacman.txt)
if pacman -Q bluez >/dev/null 2>&1; then
  echo "Enabling bluetooth..."
  sudo systemctl enable --now bluetooth || true
fi

# Legacy touchpad udev/inhibit cleanup (if present)
if [ -f "$REPO_ROOT/scripts/cleanup-input-overrides.sh" ]; then
  bash "$REPO_ROOT/scripts/cleanup-input-overrides.sh" || true
fi

echo "ThinkPad T14s Gen 3 AMD optimizations applied."
if [[ $CMDLINE_CHANGED -eq 1 ]]; then
  echo "Reboot required: amd_iommu / amd_pstate cmdline take effect at boot."
fi
