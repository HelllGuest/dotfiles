# 50-gnome-input.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# GNOME extensions, touchpad/input, T14s wakeup and VA-API.

echo "--- GNOME session ---"
ENABLED_EXT=$(gnome-extensions list --enabled 2>/dev/null | wc -l || echo 0)
if [ "$ENABLED_EXT" -ge 4 ] 2>/dev/null; then
    echo "✓ GNOME extensions enabled ($ENABLED_EXT)"
else
    check_fail "Few GNOME extensions enabled ($ENABLED_EXT/4 — run desktop/scripts/gnome-session-setup.sh)"
fi

echo "--- Input / touchpad ---"
# shellcheck source=../../desktop/lib/input.sh
source "$REPO_ROOT/desktop/lib/input.sh"
if phantom_syna_mouse_inhibited; then
    check_fail "synaptics Mouse node is inhibited (clicks will not work)"
    list_phantom_syna_mice | sed 's/^/  /'
    echo "  run: bash desktop/scripts/cleanup-input-overrides.sh && log out once"
else
    echo "✓ synaptics Mouse node not inhibited"
fi
if is_thinkpad_t14s; then
    for _tp_w in /sys/bus/i2c/devices/i2c-ELAN0678:*/power/wakeup /sys/bus/i2c/devices/i2c-SYNA8018:*/power/wakeup; do
        [[ -f "$_tp_w" ]] || continue
        if [[ "$(cat "$_tp_w" 2>/dev/null)" == "disabled" ]]; then
            echo "✓ T14s touchpad s2idle wakeup disabled (${_tp_w%/power/wakeup})"
        else
            check_fail "T14s touchpad s2idle wakeup enabled (${_tp_w%/power/wakeup} — run profiles/thinkpad-t14s.sh)"
        fi
    done
    unset _tp_w
    if grep -qx 'LIBVA_DRIVER_NAME=radeonsi' /etc/environment.d/99-wayland.conf 2>/dev/null; then
        echo "✓ /etc/environment.d/99-wayland.conf sets LIBVA_DRIVER_NAME=radeonsi"
    else
        check_fail "/etc/environment.d/99-wayland.conf missing LIBVA_DRIVER_NAME=radeonsi (run system/scripts/system-setup.sh)"
    fi
fi
