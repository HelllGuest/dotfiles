# 82-theme.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Aura Glass at the pinned commit: theme, extensions, icons, pointer, settings
# app and login screen (its own --verify), and no leftover old GDM theme hook.

_theme_rc=0
_theme_out="$(bash "$REPO_ROOT/scripts/theme-setup.sh" --check 2>&1)" || _theme_rc=$?
case $_theme_rc in
    0) echo "✓ Aura Glass verified (theme, extensions, icons, pointer, login screen)" ;;
    1) check_fail "Aura Glass: ${_theme_out:-check failed} — bash scripts/theme-setup.sh" ;;
    *) echo "○ Aura Glass not set up yet — bash scripts/theme-setup.sh" ;;
esac
unset _theme_rc _theme_out
