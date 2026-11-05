#!/usr/bin/env bash
# Smoke: T14s Gen 3 AMD installer + DMI detect (21CQ/21CR only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/arch-install-t14s.sh" \
  "$ROOT/profiles/thinkpad-t14s.sh" \
  "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  "$ROOT/scripts/lib/dmi.sh" \
  "$ROOT/scripts/lib/thinkpad-charge-thresholds.conf" \
  "$ROOT/packages/thinkpad-t14s.txt" \
  "$ROOT/scripts/detect-profile.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  if [[ "$f" == *.sh ]]; then
    bash -n "$f" || fail "bash -n failed: $f"
  fi
done
[[ -x "$ROOT/scripts/arch-install-t14s.sh" ]] || fail "arch-install-t14s.sh not executable"
[[ -x "$ROOT/profiles/thinkpad-t14s.sh" ]] || fail "thinkpad-t14s.sh not executable"
[[ -x "$ROOT/scripts/thinkpad-charge-thresholds.sh" ]] \
  || fail "thinkpad-charge-thresholds.sh not executable"

# Installer AMD defaults (no Intel leftover on fresh path)
grep -q 'amd_iommu=on' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must set amd_iommu=on"
grep -q 'amd_pstate=active' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must set amd_pstate=active"
grep -q 'UCODE=amd-ucode' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must default UCODE=amd-ucode"
grep -qE 'intel_iommu=on' "$ROOT/scripts/arch-install-t14s.sh" \
  && fail "arch-install-t14s must not set intel_iommu=on" || true
# Soft DMI gate must require type codes (not bare T14s name)
grep -qF "grep -qiE '21CQ|21CR'" "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "installer DMI soft-check must require 21CQ|21CR"

# Profile repairs generic-install Intel leftovers
grep -q 'intel_iommu=' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must strip intel_iommu"
grep -q 'amd_iommu=on' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must append amd_iommu"
grep -q 'amd_pstate=active' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must append amd_pstate"
grep -q 'mkinitcpio -P' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must rebuild UKIs after cmdline change"
grep -q 'thinkpad-charge-thresholds.sh' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must set charge thresholds"
grep -q 'packages/thinkpad-t14s.txt' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "thinkpad-t14s profile must read packages/thinkpad-t14s.txt"
grep -q '^vulkan-radeon$' "$ROOT/packages/thinkpad-t14s.txt" \
  || fail "packages/thinkpad-t14s.txt must list vulkan-radeon"
grep -q '^fprintd$' "$ROOT/packages/thinkpad-t14s.txt" \
  || fail "packages/thinkpad-t14s.txt must list fprintd"
grep -q '^libva-mesa-driver$' "$ROOT/packages/thinkpad-t14s.txt" \
  && fail "packages/thinkpad-t14s.txt must not list obsolete libva-mesa-driver" || true
grep -q 'vulkan-radeon' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must pacstrap vulkan-radeon"
grep -q 'thinkpad-charge-thresholds.conf' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must ship charge tmpfiles"
grep -q 'thinkpad-charge-thresholds.service' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must enable charge oneshot"
grep -q 'After=multi-user.target' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "charge oneshot must After=multi-user.target"
# Installer heredoc must match canonical BAT0 template (w-lines)
while IFS= read -r line; do
  [[ "$line" == w\ * ]] || continue
  grep -qF "$line" "$ROOT/scripts/arch-install-t14s.sh" \
    || fail "arch-install-t14s heredoc missing conf line: $line"
done <"$ROOT/scripts/lib/thinkpad-charge-thresholds.conf"
grep -q 'POWER_SUPPLY_ROOT' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "charge helper must support POWER_SUPPLY_ROOT for tests"

# vmtest INSTALLER override
grep -q 'INSTALLER=' "$ROOT/scripts/arch-install-vmtest.sh" \
  || fail "arch-install-vmtest must support INSTALLER="

# shellcheck source=../scripts/lib/dmi.sh
source "$ROOT/scripts/lib/dmi.sh"

mock_dmi() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  : >"$dir/product_family"
  : >"$dir/product_version"
  : >"$dir/product_name"
  : >"$dir/product_sku"
  : >"$dir/chassis_type"
  while [[ $# -ge 2 ]]; do
    printf '%s\n' "$2" >"$dir/$1"
    shift 2
  done
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Positive: 21CR MTM
mock_dmi "$TMP/cr" \
  product_family "ThinkPad T14s Gen 3" \
  product_name "21CRS1PU00" \
  product_sku "LENOVO_MT_21CR_BU_Think_FM_ThinkPad T14s Gen 3" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/cr"
is_thinkpad_t14s || fail "21CR MTM must match is_thinkpad_t14s"
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" == thinkpad-t14s ]] \
  || fail "detect-profile must return thinkpad-t14s for 21CR"

# Positive: 21CQ
mock_dmi "$TMP/cq" \
  product_family "ThinkPad T14s" \
  product_version "ThinkPad T14s Gen 3" \
  product_name "20ABCDE" \
  product_sku "21CQ0000US" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/cq"
is_thinkpad_t14s || fail "21CQ sku must match is_thinkpad_t14s"

# Negative: Intel / other-gen T14s name without 21CQ/21CR
mock_dmi "$TMP/intel" \
  product_family "ThinkPad T14s Gen 4" \
  product_name "21F6S00A00" \
  product_sku "LENOVO_MT_21F6" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/intel"
is_thinkpad_t14s && fail "T14s without 21CQ/21CR must NOT match" || true
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" != thinkpad-t14s ]] \
  || fail "detect-profile must not return thinkpad-t14s for non-21CQ/21CR T14s"

# Negative: X1 must still win over any accidental substring (sanity)
mock_dmi "$TMP/x1" \
  product_family "ThinkPad X1 Yoga" \
  product_version "ThinkPad X1 Yoga Gen 5" \
  product_name "20UC001BUS" \
  product_sku "LENOVO_MT_20UC" \
  chassis_type "31"
export DMI_SYSFS_ROOT="$TMP/x1"
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" == thinkpad-x1 ]] \
  || fail "detect-profile must return thinkpad-x1 for X1 Yoga"

# Charge helper: fake sysfs (no sudo)
PSY="$TMP/psy"
CONF_OUT="$TMP/thinkpad-charge-thresholds.conf"
mkdir -p "$PSY/BAT0" "$PSY/BAT1" "$PSY/emptybat"
printf '50\n' >"$PSY/BAT0/charge_control_start_threshold"
printf '90\n' >"$PSY/BAT0/charge_control_end_threshold"
# BAT1: no charge_control_* — must not claim success
# emptybat: dir only

out="$(
  POWER_SUPPLY_ROOT="$PSY" CHARGE_TMPFILES="$CONF_OUT" CHARGE_START=70 CHARGE_END=80 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "charge helper failed on fake sysfs: $out"
echo "$out" | grep -q 'charge BAT0' || fail "must report BAT0 thresholds set"
echo "$out" | grep -q 'charge BAT1' && fail "must not claim BAT1 without charge_control_*" || true
echo "$out" | grep -q 'charge emptybat' && fail "must not claim emptybat" || true
# live-fail path: charge_control exists but not writable + CHARGE_NOSUDO
PSY3="$TMP/psy3"
mkdir -p "$PSY3/BAT0"
printf '50\n' >"$PSY3/BAT0/charge_control_start_threshold"
printf '90\n' >"$PSY3/BAT0/charge_control_end_threshold"
chmod a-w "$PSY3/BAT0/charge_control_start_threshold" "$PSY3/BAT0/charge_control_end_threshold"
out3="$(
  POWER_SUPPLY_ROOT="$PSY3" CHARGE_TMPFILES="$TMP/fail.conf" CHARGE_NOSUDO=1 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" && fail "unwritable sysfs with CHARGE_NOSUDO must exit non-zero" || true
echo "$out3" | grep -q 'charge BAT0 →' && fail "must not success-say when live write fails" || true
echo "$out3" | grep -qi 'live write failed\|tmpfiles queued' \
  || fail "must warn on live write failure"
[[ "$(cat "$PSY/BAT0/charge_control_start_threshold")" == 70 ]] \
  || fail "start threshold not written"
[[ "$(cat "$PSY/BAT0/charge_control_end_threshold")" == 80 ]] \
  || fail "end threshold not written"
grep -q 'w .*/BAT0/charge_control_start_threshold - - - - 70' "$CONF_OUT" \
  || fail "tmpfiles conf missing start line"
grep -q 'w .*/BAT0/charge_control_end_threshold - - - - 80' "$CONF_OUT" \
  || fail "tmpfiles conf missing end line"

# No BAT thresholds at all → soft skip exit 0
PSY2="$TMP/psy2"
mkdir -p "$PSY2/BAT0"
out2="$(
  POWER_SUPPLY_ROOT="$PSY2" CHARGE_TMPFILES="$TMP/none.conf" \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "empty charge_control should exit 0: $out2"
echo "$out2" | grep -qi 'skip' || fail "empty charge_control must say skip"
[[ ! -e "$TMP/none.conf" ]] || fail "skip path must not write conf"

# Bad range rejected
if POWER_SUPPLY_ROOT="$PSY" CHARGE_TMPFILES="$TMP/bad.conf" CHARGE_START=80 CHARGE_END=70 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>/dev/null; then
  fail "START>=END must exit non-zero"
fi

echo "PASS: thinkpad-t14s tests"
