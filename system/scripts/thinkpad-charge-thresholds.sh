#!/usr/bin/env bash
# Persist ThinkPad charge window via systemd-tmpfiles + late-boot oneshot.
# Defaults: start 70 / end 80. Override with CHARGE_START / CHARGE_END.
# Test hooks: POWER_SUPPLY_ROOT, CHARGE_TMPFILES (writable paths; no sudo needed).
# Service hooks: CHARGE_APPLY_SCRIPT, CHARGE_SERVICE_UNIT, CHARGE_SKIP_SERVICE=1,
#                CHARGE_SKIP_SYSTEMCTL=1, CHARGE_TMPL_DIR, CHARGE_FORCE_SEED=1.
set -euo pipefail

START="${CHARGE_START:-70}"
END="${CHARGE_END:-80}"
CONF="${CHARGE_TMPFILES:-/etc/tmpfiles.d/thinkpad-charge-thresholds.conf}"
APPLY="${CHARGE_APPLY_SCRIPT:-/usr/local/lib/thinkpad/apply-charge-thresholds.sh}"
UNIT="${CHARGE_SERVICE_UNIT:-/etc/systemd/system/thinkpad-charge-thresholds.service}"
PSY="${POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "$_SCRIPT_DIR/../.." && pwd)"
TMPL_DIR="${CHARGE_TMPL_DIR:-$_REPO_ROOT/system/templates}"

# shellcheck source=../../provision/lib/dmi.sh
source "$_REPO_ROOT/provision/lib/dmi.sh"

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

if ! [[ "$START" =~ ^[0-9]+$ && "$END" =~ ^[0-9]+$ ]]; then
  echo "error: CHARGE_START/END must be integers" >&2
  exit 1
fi
if (( START < 0 || START > 99 || END < 1 || END > 100 || START >= END )); then
  echo "error: need 0 <= START < END <= 100 (got ${START}/${END})" >&2
  exit 1
fi

if [[ "${CHARGE_NOSUDO:-}" == 1 ]]; then
  _sudo() { echo "error: sudo disabled (CHARGE_NOSUDO=1)" >&2; return 1; }
elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
  _sudo() { sudo -A "$@"; }
else
  _sudo() { sudo "$@"; }
fi

# Write value to path; sudo only when the target is not user-writable.
_write_sysfs() {
  local path="$1" val="$2"
  if [[ -w "$path" ]]; then
    printf '%s\n' "$val" >"$path"
  else
    printf '%s\n' "$val" | _sudo tee "$path" >/dev/null
  fi
}

# Install src → dest with mode (644 conf/unit, 755 apply). Uses install(1).
_install_file() {
  local mode=$1 src=$2 dest=$3
  local dest_dir
  dest_dir="$(dirname "$dest")"
  chmod "$mode" "$src"
  mkdir -p "$dest_dir" 2>/dev/null || true
  if [[ -w "$dest_dir" ]] && { [[ ! -e "$dest" ]] || [[ -w "$dest" ]]; }; then
    install -m "$mode" "$src" "$dest"
  else
    _sudo mkdir -p "$dest_dir"
    _sudo install -m "$mode" "$src" "$dest"
  fi
}

# Bash replace (not sed) so APPLY paths may contain | & etc.
_render_tmpl() {
  local tmpl=$1 dest=$2 line
  [[ -f $tmpl ]] || {
    echo "error: missing template $tmpl (track system/templates/*.tmpl in git)" >&2
    return 1
  }
  : >"$dest"
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line//@@START@@/$START}
    line=${line//@@END@@/$END}
    line=${line//@@APPLY@@/$APPLY}
    printf '%s\n' "$line" >>"$dest"
  done <"$tmpl"
}

_want_late_service() {
  [[ "${CHARGE_SKIP_SERVICE:-0}" == 1 ]] && return 1
  [[ "$CONF" == /etc/tmpfiles.d/* ]] && return 0
  [[ -n ${CHARGE_APPLY_SCRIPT:-} && -n ${CHARGE_SERVICE_UNIT:-} ]] && return 0
  return 1
}

# Seed BAT0 + unit when charge_control_* not visible yet — ThinkPad DMI only.
# Non-ThinkPad laptops (Dell, etc.) plain-skip: missing charge_control_* means
# unsupported, not a late thinkpad_acpi race.
_may_seed_without_bat() {
  [[ "${CHARGE_FORCE_SEED:-0}" == 1 ]] && return 0
  echo "$(dmi_label) $(dmi_field product_sku)" | grep -qi 'ThinkPad'
}

_cleanup_legacy_t14s_path() {
  local legacy_dir=/usr/local/lib/t14s
  local legacy_bin=$legacy_dir/apply-charge-thresholds.sh
  local removed=0
  # Only when installing the real unit path (not test overrides).
  [[ -z ${CHARGE_APPLY_SCRIPT:-} ]] || return 0
  [[ -e $legacy_bin ]] || {
    # Empty leftover dir only — quiet rmdir, no success log.
    [[ -d $legacy_dir ]] || return 0
    if [[ -w ${legacy_dir%/*} ]]; then
      rmdir --ignore-fail-on-non-empty -- "$legacy_dir" 2>/dev/null || true
    else
      _sudo rmdir --ignore-fail-on-non-empty -- "$legacy_dir" 2>/dev/null || true
    fi
    return 0
  }
  if [[ -w ${legacy_dir%/*} ]]; then
    rm -f -- "$legacy_bin" && removed=1
    rmdir --ignore-fail-on-non-empty -- "$legacy_dir" 2>/dev/null || true
  else
    if _sudo rm -f -- "$legacy_bin"; then
      removed=1
    else
      warn "could not remove legacy ${legacy_bin} — run: sudo rm -f ${legacy_bin}"
      return 0
    fi
    _sudo rmdir --ignore-fail-on-non-empty -- "$legacy_dir" 2>/dev/null || true
  fi
  if (( removed == 1 )); then
    say "removed legacy ${legacy_bin}"
  fi
  return 0
}

# tmpfiles can race before thinkpad_acpi exposes BAT*. oneshot waits/retries.
# $1 = seed (1): enable + start --no-block (avoid 60s hang when BAT* not up yet).
# $1 = 0: enable --now (BAT* already visible; oneshot returns quickly).
_install_late_service() {
  local seed=${1:-0}
  local apply_tmp unit_tmp
  apply_tmp="$(mktemp)"
  unit_tmp="$(mktemp)"
  if ! _render_tmpl "$TMPL_DIR/apply-charge-thresholds.sh.tmpl" "$apply_tmp"; then
    rm -f "$apply_tmp" "$unit_tmp"
    return 1
  fi
  if ! _render_tmpl "$TMPL_DIR/thinkpad-charge-thresholds.service.tmpl" "$unit_tmp"; then
    rm -f "$apply_tmp" "$unit_tmp"
    return 1
  fi

  if ! _install_file 755 "$apply_tmp" "$APPLY"; then
    rm -f "$apply_tmp" "$unit_tmp"
    warn "could not install ${APPLY}"
    return 1
  fi
  if ! _install_file 644 "$unit_tmp" "$UNIT"; then
    rm -f "$apply_tmp" "$unit_tmp"
    warn "could not install ${UNIT}"
    return 1
  fi
  rm -f "$apply_tmp" "$unit_tmp"
  _cleanup_legacy_t14s_path

  if [[ "${CHARGE_SKIP_SYSTEMCTL:-0}" == 1 ]]; then
    say "installed ${APPLY} + ${UNIT} (systemctl skipped)"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1; then
    _sudo systemctl daemon-reload 2>/dev/null || true
    if (( seed == 1 )); then
      if _sudo systemctl enable thinkpad-charge-thresholds.service 2>/dev/null \
        && _sudo systemctl start --no-block thinkpad-charge-thresholds.service 2>/dev/null; then
        say "enabled thinkpad-charge-thresholds.service (start --no-block; BAT* may appear later)"
      else
        warn "could not enable/start thinkpad-charge-thresholds.service (unit installed)"
      fi
    elif _sudo systemctl enable --now thinkpad-charge-thresholds.service 2>/dev/null; then
      say "enabled thinkpad-charge-thresholds.service"
    else
      warn "could not enable thinkpad-charge-thresholds.service (unit installed)"
    fi
  else
    warn "systemctl missing — unit installed at ${UNIT}; enable after boot"
  fi
}

thresh_tmp="$(mktemp)"
trap 'rm -f "$thresh_tmp"' EXIT
{
  echo "# ThinkPad charge thresholds (generated by thinkpad-charge-thresholds.sh)"
  echo "# start=${START} end=${END}"
  echo "# Best-effort at boot; see thinkpad-charge-thresholds.service if BAT* appears late."
} >"$thresh_tmp"

wrote=0
live_fail=0
shopt -s nullglob
for bat in "${PSY}"/BAT*; do
  [[ -d $bat ]] || continue
  name="$(basename "$bat")"
  bat_ctrl=0
  live_ok=0
  if [[ -e $bat/charge_control_start_threshold ]]; then
    bat_ctrl=1
    echo "w ${bat}/charge_control_start_threshold - - - - ${START}" >>"$thresh_tmp"
    if _write_sysfs "$bat/charge_control_start_threshold" "$START"; then
      live_ok=1
    else
      warn "live write failed: ${bat}/charge_control_start_threshold"
      live_fail=1
    fi
    wrote=1
  fi
  if [[ -e $bat/charge_control_end_threshold ]]; then
    bat_ctrl=1
    echo "w ${bat}/charge_control_end_threshold - - - - ${END}" >>"$thresh_tmp"
    if _write_sysfs "$bat/charge_control_end_threshold" "$END"; then
      live_ok=1
    else
      warn "live write failed: ${bat}/charge_control_end_threshold"
      live_fail=1
    fi
    wrote=1
  fi
  if (( bat_ctrl == 1 )); then
    if (( live_ok == 1 )); then
      say "charge ${name} → ${START}–${END}"
    else
      warn "charge ${name}: tmpfiles queued; live sysfs write failed"
    fi
  fi
done
shopt -u nullglob

_seed=0
if (( wrote == 0 )); then
  # Plain skip unless ThinkPad DMI (late thinkpad_acpi race only).
  if ! _want_late_service || ! _may_seed_without_bat; then
    say "no BAT*/charge_control_* sysfs — skip (not a ThinkPad battery host?)"
    exit 0
  fi
  say "no BAT* charge_control_* yet — seed BAT0 tmpfiles + late-boot service"
  echo "w /sys/class/power_supply/BAT0/charge_control_start_threshold - - - - ${START}" >>"$thresh_tmp"
  echo "w /sys/class/power_supply/BAT0/charge_control_end_threshold - - - - ${END}" >>"$thresh_tmp"
  _seed=1
fi

if ! _install_file 644 "$thresh_tmp" "$CONF"; then
  warn "could not persist ${CONF}"
  exit 1
fi

# Best-effort apply now (sysfs already written above; tmpfiles for reboot)
if [[ $CONF == /etc/tmpfiles.d/* ]]; then
  _sudo systemd-tmpfiles --create "$CONF" 2>/dev/null || true
elif command -v systemd-tmpfiles >/dev/null 2>&1; then
  systemd-tmpfiles --create "$CONF" 2>/dev/null || true
fi
say "persisted ${CONF}"

if _want_late_service; then
  _install_late_service "$_seed" || warn "late-boot charge service not fully installed"
fi

if (( live_fail == 1 )); then
  warn "tmpfiles persisted; one or more live sysfs writes failed (check sudo)"
  exit 1
fi
