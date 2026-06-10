#!/bin/bash
# thinkpad-health.sh — post-tuning verification for ThinkPad X1 Yoga Gen 5

echo "=== ThinkPad X1 Yoga Health Check ==="

echo "--- Session ---"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"

echo "--- Power ---"
for svc in power-profiles-daemon iio-sensor-proxy bolt; do
    printf "  %-24s %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
done

echo "--- Kernel cmdline (key params) ---"
grep -oE 'mem_sleep_default=[^ ]+|nvme\.noacpi|i915\.[^ ]+' /proc/cmdline 2>/dev/null || cat /proc/cmdline

echo "--- i915 module params (live; cmdline/modprobe apply at boot) ---"
for p in enable_psr enable_fbc enable_guc; do
    val=$(sudo cat "/sys/module/i915/parameters/$p" 2>/dev/null || echo "?")
    printf "  %-12s %s\n" "$p" "$val"
done

echo "--- VA-API ---"
if command -v vainfo >/dev/null 2>&1; then
    vainfo 2>&1 | grep -E 'Driver version|VA-API version' | head -2
else
    echo "  vainfo not installed"
fi

echo "--- Sleep ---"
cat /sys/power/mem_sleep 2>/dev/null || echo "  unavailable"

echo "--- Input ---"
if command -v libinput >/dev/null 2>&1; then
    libinput list-devices 2>/dev/null | grep -iE 'wacom|trackpoint' | head -4
else
    grep -i wacom /proc/bus/input/devices 2>/dev/null | grep ^N | head -2
fi

echo "Health check finished."
