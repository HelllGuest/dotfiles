#!/bin/bash
# thinkpad-health.sh — post-tuning verification for ThinkPad hosts (P15 / T14s)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== ThinkPad Health Check ==="

echo "--- Session ---"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"

echo "--- Power ---"
svc_state() {
    local st
    st="$(systemctl is-active "$1" 2>/dev/null || true)"
    printf "  %-24s %s\n" "$1" "${st:-unknown}"
}
svc_state bolt
if pacman -Q tuned-ppd >/dev/null 2>&1; then
    svc_state tuned
    svc_state tuned-ppd
else
    svc_state power-profiles-daemon
fi

echo "--- Kernel cmdline (key params) ---"
grep -oE 'mem_sleep_default=[^ ]+|nvme\.noacpi|nvidia_drm\.[^ ]+|amd_iommu=[^ ]+|amd_pstate=[^ ]+|i915\.[^ ]+' \
  /proc/cmdline 2>/dev/null || cat /proc/cmdline

if [[ -d /sys/module/i915 ]]; then
    echo "--- i915 module params (live; cmdline/modprobe apply at boot) ---"
    for p in enable_psr enable_fbc enable_guc; do
        val=$(sudo cat "/sys/module/i915/parameters/$p" 2>/dev/null || echo "?")
        printf "  %-12s %s\n" "$p" "$val"
    done
fi

if [[ -d /sys/module/nvidia ]] || command -v nvidia-smi >/dev/null 2>&1; then
    echo "--- NVIDIA ---"
    # Read runtime_status before nvidia-smi: listing the GPU wakes it from runtime PM.
    # Only class 0x03* (VGA/3D/display). HDMI audio / USB-C companions can stay
    # active and must not force nvidia-smi.
    nvidia_pci=0
    nvidia_awake=0
    for card in /sys/bus/pci/devices/*/power/runtime_status; do
        [[ -r "$card" ]] || continue
        dev="${card%/power/runtime_status}"
        vendor="$(cat "$dev/vendor" 2>/dev/null || true)"
        [[ "$vendor" == "0x10de" ]] || continue
        class="$(cat "$dev/class" 2>/dev/null || true)"
        [[ "$class" == 0x03* ]] || continue
        nvidia_pci=1
        st="$(cat "$card")"
        printf "  %s runtime_status=%s\n" "$dev" "$st"
        case "$st" in
            suspended|suspending) ;;
            *) nvidia_awake=1 ;;
        esac
    done
    if command -v nvidia-smi >/dev/null 2>&1; then
        if [[ "$nvidia_pci" -eq 1 && "$nvidia_awake" -eq 0 ]]; then
            echo "  nvidia-smi: skipped (GPU runtime suspended; listing would wake it)"
        else
            list="$(nvidia-smi -L 2>/dev/null || true)"
            if [[ -n "$list" ]]; then
                printf '%s\n' "$list" | head -2 | sed 's/^/  /'
            else
                echo "  nvidia-smi present but no GPU listed"
            fi
        fi
    else
        echo "  nvidia module loaded; nvidia-smi missing"
    fi
    if command -v prime-run >/dev/null 2>&1; then
        echo "  prime-run: present"
    else
        echo "  prime-run: missing"
    fi
fi

if [[ -d /sys/module/amdgpu ]]; then
    echo "--- AMDGPU ---"
    echo "  module: loaded"
    if [[ -n "${LIBVA_DRIVER_NAME:-}" ]]; then
        echo "  LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME"
    fi
fi

echo "--- VA-API ---"
if command -v vainfo >/dev/null 2>&1; then
    vainfo 2>&1 | grep -E 'Driver version|VA-API version' | head -2
else
    echo "  vainfo not installed"
fi

echo "--- Sleep ---"
cat /sys/power/mem_sleep 2>/dev/null || echo "  unavailable"

echo "--- Input ---"
# shellcheck source=lib/input.sh
source "$REPO_ROOT/scripts/lib/input.sh"
if command -v libinput >/dev/null 2>&1; then
    libinput list-devices 2>/dev/null | grep -iE 'trackpoint|touchpad|fingerprint' | head -4
    if phantom_syna_mouse_inhibited; then
        echo "  WARN: synaptics Mouse node inhibited (clicks broken)"
        echo "        run: bash scripts/cleanup-input-overrides.sh"
    else
        echo "  OK:   synaptics Mouse node not inhibited"
    fi
else
    echo "  libinput not installed"
fi

echo "Health check finished."
