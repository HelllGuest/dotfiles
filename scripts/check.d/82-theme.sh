# 82-theme.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Stock Adwaita via theme-setup.sh --check; no Aura Glass, no leftover GDM theme hook.

_theme_rc=0
_theme_out="$(bash "$REPO_ROOT/scripts/theme-setup.sh" --check 2>&1)" || _theme_rc=$?
case $_theme_rc in
    0) echo "✓ desktop theme: stock Adwaita" ;;
    1) check_fail "theme: ${_theme_out:-check failed} — bash scripts/theme-setup.sh" ;;
    *) echo "○ theme not Adwaita yet — bash scripts/theme-setup.sh (${_theme_out:-rc $_theme_rc})" ;;
esac
unset _theme_rc _theme_out
