# 40-gdm.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# GDM login screen: service, Wayland, greeter dconf, systemd drop-in.

echo "--- GDM login screen ---"
if systemctl is-enabled gdm.service >/dev/null 2>&1; then
    echo "✓ gdm.service enabled"
else
    check_fail "gdm.service not enabled (run desktop/scripts/gdm-setup.sh)"
fi
if grep -q 'WaylandEnable=true' /etc/gdm/custom.conf 2>/dev/null; then
    echo "✓ GDM WaylandEnable=true"
else
    check_fail "GDM WaylandEnable not set (run desktop/scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    echo "✓ GDM greeter dconf deployed"
else
    check_fail "GDM greeter dconf missing"
fi
if [ -f /etc/systemd/system/gdm.service.d/override.conf ]; then
    if grep -q 'WAYLAND_DISPLAY' /etc/systemd/system/gdm.service.d/override.conf 2>/dev/null; then
        check_fail "GDM override still sets WAYLAND_DISPLAY (run desktop/scripts/gdm-setup.sh)"
    else
        echo "✓ GDM override has no WAYLAND_DISPLAY"
    fi
else
    check_fail "GDM systemd override missing (run desktop/scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    gdm_dconf_owner="$(stat -c '%U' /etc/dconf/db/gdm.d/00-login-screen 2>/dev/null || echo unknown)"
    if [ "$gdm_dconf_owner" = root ]; then
        echo "✓ GDM greeter dconf owned by root"
    else
        check_fail "GDM greeter dconf owned by $gdm_dconf_owner (run desktop/scripts/gdm-setup.sh)"
    fi
fi
if [ -e /etc/dconf/profile/gdm ]; then
    if [ -L /etc/dconf/profile/gdm ] && readlink /etc/dconf/profile/gdm 2>/dev/null | grep -qE "$HOME|dotfiles"; then
        check_fail "GDM dconf profile symlinks into home (run desktop/scripts/gdm-setup.sh)"
    elif [ -L /etc/dconf/profile/gdm ]; then
        check_fail "GDM dconf profile is symlink (run desktop/scripts/gdm-setup.sh)"
    else
        echo "✓ GDM dconf profile is real file in /etc"
    fi
else
    check_fail "GDM dconf profile missing (run desktop/scripts/gdm-setup.sh)"
fi
if systemctl show gdm.service -p DropInPaths --value 2>/dev/null | grep -q 'gdm.service.d/override.conf'; then
    echo "✓ GDM systemd drop-in loaded"
else
    check_fail "GDM systemd drop-in not loaded (sudo systemctl daemon-reload)"
fi
