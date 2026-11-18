# 82-theme.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# User theme copy, theme-sync.service, GDM greeter theme and its pacman hook.

# Theme copy for Flatpaks shadows the system theme: it must match it
# (theme-sync.service refreshes it at login).
bash "$REPO_ROOT/scripts/theme-setup.sh" --check
_theme_rc=$?
case $_theme_rc in
    0) echo "✓ user theme copy matches the system theme" ;;
    1) check_fail "user theme copy is stale — bash scripts/theme-setup.sh --sync" ;;
    *) echo "○ theme not set up yet — bash scripts/theme-setup.sh" ;;
esac
if [[ $_theme_rc -lt 2 ]]; then
    if systemctl --user is-enabled --quiet theme-sync.service 2>/dev/null; then
        echo "✓ theme-sync.service enabled (refreshes the copy at login)"
    else
        check_fail "theme-sync.service not enabled — bash scripts/theme-setup.sh"
    fi
    # Greeter theme (theme-setup.sh runs gdm-shell-theme.sh install unless opted out).
    if [[ "${SKIP_GDM_SHELL_THEME:-0}" == 1 ]]; then
        echo "○ GDM shell theme skipped (SKIP_GDM_SHELL_THEME=1)"
    else
        _gdm="$(bash "$REPO_ROOT/scripts/gdm-shell-theme.sh" status 2>/dev/null)"
        if [[ $_gdm == themed:* ]]; then
            echo "✓ GDM login screen ${_gdm%%$'\n'*}"
        else
            check_fail "GDM login screen uses the stock theme — bash scripts/gdm-shell-theme.sh install"
        fi
        if [[ $_gdm == *"pacman hook: /"* ]]; then
            echo "✓ GDM theme pacman hook installed (re-applies after gnome-shell/theme upgrades)"
        else
            check_fail "GDM theme pacman hook missing (upgrades revert the greeter) — bash scripts/gdm-shell-theme.sh install"
        fi
    fi
fi
unset _theme_rc _gdm
