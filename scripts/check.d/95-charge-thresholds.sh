# 95-charge-thresholds.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# ThinkPad battery charge thresholds.

echo "--- ThinkPad charge thresholds ---"
_charge="$REPO_ROOT/scripts/thinkpad-charge-thresholds.sh"
if [[ -f "$_charge" ]]; then
    if bash -n "$_charge" 2>/dev/null; then
        echo "✓ thinkpad-charge-thresholds.sh (syntax OK)"
    else
        check_fail "thinkpad-charge-thresholds.sh bash -n failed"
    fi
    if [[ -r /sys/class/power_supply/BAT0/charge_control_start_threshold ]]; then
        _cs="$(cat /sys/class/power_supply/BAT0/charge_control_start_threshold 2>/dev/null || true)"
        _ce="$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || true)"
        echo "  BAT0 live: start=${_cs:-?} end=${_ce:-?}"
        unset _cs _ce
    else
        echo "  ○ no BAT0 charge_control_* (non-ThinkPad or module not loaded)"
    fi
    # Only nag about missing persistence on hosts that expose BAT charge controls.
    if [[ -r /sys/class/power_supply/BAT0/charge_control_start_threshold ]]; then
      if [[ -f /etc/tmpfiles.d/thinkpad-charge-thresholds.conf ]]; then
          echo "✓ /etc/tmpfiles.d/thinkpad-charge-thresholds.conf present"
      else
          echo "○ charge tmpfiles not installed (bash scripts/thinkpad-charge-thresholds.sh)"
      fi
      if [[ -f /etc/systemd/system/thinkpad-charge-thresholds.service ]]; then
          echo "✓ thinkpad-charge-thresholds.service unit present"
          if systemctl is-enabled thinkpad-charge-thresholds.service >/dev/null 2>&1; then
              echo "✓ thinkpad-charge-thresholds.service enabled"
          else
              echo "○ thinkpad-charge-thresholds.service not enabled (re-run helper)"
          fi
      else
          echo "○ charge late-boot unit missing (bash scripts/thinkpad-charge-thresholds.sh)"
      fi
      if [[ -x /usr/local/lib/thinkpad/apply-charge-thresholds.sh ]]; then
          echo "✓ /usr/local/lib/thinkpad/apply-charge-thresholds.sh present"
      else
          echo "○ apply-charge-thresholds.sh missing (re-run helper)"
      fi
    fi
else
    check_fail "thinkpad-charge-thresholds.sh missing"
fi
unset _charge
