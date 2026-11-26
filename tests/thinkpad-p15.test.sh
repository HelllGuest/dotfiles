#!/usr/bin/env bash
# Smoke: P15 Gen 1 Optimus profile + Stage A handoff (20SU).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in \
  "$ROOT/scripts/arch-install-p15.sh" \
  "$ROOT/profiles/thinkpad-p15.sh" \
  "$ROOT/provision/lib/dmi.sh" \
  "$ROOT/system/templates/thinkpad-charge-thresholds.conf" \
  "$ROOT/provision/lib/stage-a-handoff.sh" \
  "$ROOT/provision/scripts/detect-profile.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  if [[ "$f" == *.sh ]]; then
    bash -n "$f" || fail "bash -n failed: $f"
  fi
done
[[ -x "$ROOT/scripts/arch-install-p15.sh" ]] || fail "arch-install-p15.sh not executable"
[[ -x "$ROOT/profiles/thinkpad-p15.sh" ]] || fail "thinkpad-p15.sh not executable"

INST="$ROOT/scripts/arch-install-p15.sh"

# Thin handoff → canonical in-repo Stage A
grep -q 'stage_a_handoff p15' "$INST" \
  || fail "arch-install-p15 must hand off with profile p15"
grep -q 't14s-arch-install/install.sh' "$INST" \
  || fail "arch-install-p15 must point at canonical Stage A installer"
grep -qE 'cryptsetup|pacstrap' "$INST" \
  && fail "arch-install-p15 must not embed Stage A body" || true

grep -q '0x10de' "$ROOT/system/gdm/etc/udev/rules.d/61-gdm-wayland.rules" \
  || fail "stow GDM udev must keep NVIDIA 0x10de after Stage B gdm-setup"
grep -qE '(^|[[:space:]_/])20SU' "$ROOT/provision/lib/dmi.sh" \
  || fail "is_thinkpad_p15 must match 20SU"

# Profile + detect
grep -q 'nvidia' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 profile must mention nvidia"
grep -q 'thinkpad-charge-thresholds.sh' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 profile must refresh charge thresholds"
grep -q '61-thinkpad-charge-limit.rules' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 profile must install 61-thinkpad-charge-limit.rules"
grep -q '/var/lib/sbctl/keys' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 profile must check /var/lib/sbctl/keys"
grep -q '\$REPO_ROOT/profiles/thinkpad-t14s.sh' "$ROOT/profiles/laptop.sh" \
  || fail "laptop.sh must delegate via \$REPO_ROOT/profiles/thinkpad-t14s.sh"
grep -q 'return 0' "$ROOT/profiles/laptop.sh" \
  || fail "laptop.sh must return cleanly when sourced by apply-profile.sh"

# Behavioral: sourcing profiles/laptop.sh from outside repo root on T14s DMI delegates and returns
(
  _lt="$(mktemp -d)"
  trap 'rm -rf "$_lt"' EXIT
  mkdir -p "$_lt/repo/profiles" "$_lt/repo/provision/lib" "$_lt/dmi"
  cp "$ROOT/provision/lib/dmi.sh" "$_lt/repo/provision/lib/dmi.sh"
  cp "$ROOT/profiles/laptop.sh" "$_lt/repo/profiles/laptop.sh"
  printf 'echo DELEGATED_T14S\n' >"$_lt/repo/profiles/thinkpad-t14s.sh"
  printf 'ThinkPad T14s Gen 3\n' >"$_lt/dmi/product_family"
  printf '21CRS1PU00\n' >"$_lt/dmi/product_name"
  printf 'LENOVO_MT_21CR\n' >"$_lt/dmi/product_sku"
  _out="$(cd /tmp && DMI_SYSFS_ROOT="$_lt/dmi" bash -c "source '$_lt/repo/profiles/laptop.sh' && echo CALLER_SURVIVED")"
  grep -q 'DELEGATED_T14S' <<<"$_out" && grep -q 'CALLER_SURVIVED' <<<"$_out" \
    || fail "laptop.sh sourced delegation failed (got: $_out)"
)
# shellcheck source=../provision/lib/dmi.sh
source "$ROOT/provision/lib/dmi.sh"
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
mock_dmi "$TMP/p15" \
  product_family "ThinkPad P15 Gen 1" \
  product_version "ThinkPad P15 Gen 1" \
  product_name "20SUS2FJ00" \
  product_sku "LENOVO_MT_20SU" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/p15"
is_thinkpad_p15 || fail "20SU must match is_thinkpad_p15"
[[ "$(bash "$ROOT/provision/scripts/detect-profile.sh")" == thinkpad-p15 ]] \
  || fail "detect-profile must return thinkpad-p15 for P15 Gen 1"

# Negative: T14s must not pick p15
mock_dmi "$TMP/cr" \
  product_family "ThinkPad T14s Gen 3" \
  product_name "21CRS1PU00" \
  product_sku "LENOVO_MT_21CR_BU_Think_FM_ThinkPad T14s Gen 3" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/cr"
is_thinkpad_p15 && fail "T14s 21CR must NOT match is_thinkpad_p15" || true
[[ "$(bash "$ROOT/provision/scripts/detect-profile.sh")" != thinkpad-p15 ]] \
  || fail "detect-profile must not return thinkpad-p15 for T14s"

# Canonical sibling owns Optimus seeds when present
CANON="$ROOT/../t14s-arch-install"
if [[ -f $CANON/lib/80-chroot-setup.sh ]]; then
  # Chroot code = entry script + its stages (lib/chroot/, when split).
  CANON_CHROOT=("$CANON/lib/80-chroot-setup.sh")
  [[ -d $CANON/lib/chroot ]] && CANON_CHROOT+=("$CANON"/lib/chroot/*.sh)
  grep -q 'nvidia_drm.modeset=1' "${CANON_CHROOT[@]}" \
    || fail "canonical Stage A missing nvidia modeset"
  grep -q 'intel_iommu=on' "${CANON_CHROOT[@]}" \
    || fail "canonical Stage A missing intel_iommu"
fi

echo "PASS: thinkpad-p15 tests"
