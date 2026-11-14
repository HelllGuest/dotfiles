#!/usr/bin/env bash
# Smoke: P15 Gen 1 Optimus installer + DMI detect (20SU).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in \
  "$ROOT/scripts/arch-install-p15.sh" \
  "$ROOT/profiles/thinkpad-p15.sh" \
  "$ROOT/scripts/lib/dmi.sh" \
  "$ROOT/scripts/lib/install-identity.sh" \
  "$ROOT/scripts/lib/thinkpad-charge-thresholds.conf" \
  "$ROOT/scripts/detect-profile.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  if [[ "$f" == *.sh ]]; then
    bash -n "$f" || fail "bash -n failed: $f"
  fi
done
[[ -x "$ROOT/scripts/arch-install-p15.sh" ]] || fail "arch-install-p15.sh not executable"
[[ -x "$ROOT/profiles/thinkpad-p15.sh" ]] || fail "thinkpad-p15.sh not executable"

INST="$ROOT/scripts/arch-install-p15.sh"

# Installer Intel/NVIDIA Optimus defaults (no AMD Rembrandt leftovers)
grep -q 'intel_iommu=on' "$INST" \
  || fail "arch-install-p15 must set intel_iommu=on"
grep -q 'nvidia_drm.modeset=1' "$INST" \
  || fail "arch-install-p15 must set nvidia_drm.modeset=1"
grep -q 'rd.driver.blacklist=nouveau' "$INST" \
  || fail "arch-install-p15 must blacklist nouveau on cmdline"
grep -q 'UCODE=intel-ucode' "$INST" \
  || fail "arch-install-p15 must default UCODE=intel-ucode"
grep -qE 'amd_iommu=on|amd_pstate=active' "$INST" \
  && fail "arch-install-p15 must not set amd_iommu/amd_pstate" || true
grep -q 'vulkan-radeon' "$INST" \
  && fail "arch-install-p15 must not pacstrap vulkan-radeon" || true
grep -q 'LIBVA_DRIVER_NAME=radeonsi' "$INST" \
  && fail "arch-install-p15 must not set LIBVA_DRIVER_NAME=radeonsi" || true
grep -q 'LIBVA_DRIVER_NAME=iHD' "$INST" \
  || fail "arch-install-p15 must set LIBVA_DRIVER_NAME=iHD"
grep -q 'nvidia-open-dkms' "$INST" \
  || fail "arch-install-p15 must pacstrap nvidia-open-dkms"
grep -q 'vulkan-intel' "$INST" \
  || fail "arch-install-p15 must pacstrap vulkan-intel"
grep -q 'intel-media-driver' "$INST" \
  || fail "arch-install-p15 must pacstrap intel-media-driver"
grep -q '/etc/modprobe.d/nvidia.conf' "$INST" \
  || fail "arch-install-p15 must seed nvidia.conf"
grep -q 'nvidia-suspend.service' "$INST" \
  || fail "arch-install-p15 must enable nvidia-suspend (resume black-screen fix)"
grep -q '80-nvidia-pm.rules' "$INST" \
  || fail "arch-install-p15 must seed 80-nvidia-pm.rules"
grep -qF 'NVIDIA stack skipped with desktop' "$INST" \
  || fail "finish text must note NVIDIA skipped when DESKTOP=N"
grep -q '0x10de' "$ROOT/stow/gdm/etc/udev/rules.d/61-gdm-wayland.rules" \
  || fail "stow GDM udev must keep NVIDIA 0x10de after Stage B gdm-setup"
grep -q 'thinkpad-p15' "$INST" \
  || fail "arch-install-p15 must default hostname thinkpad-p15"
grep -q 'INSTALL_OLLAMA' "$INST" \
  || fail "arch-install-p15 must prompt INSTALL_OLLAMA"
grep -q 'ollama-cuda' "$INST" \
  || fail "arch-install-p15 must offer ollama-cuda"
grep -q '71-thinkpad-t14s-touchpad-wakeup.rules' "$INST" \
  && fail "arch-install-p15 must not seed T14s touchpad wakeup rule" || true

# Soft DMI gate must match scripts/lib/dmi.sh is_thinkpad_p15
grep -qF "grep -qiE 'ThinkPad[[:space:]]*P15|P15[[:space:]]+Gen|(^|[[:space:]_/])20SU([[:alnum:]_-]|$)'" "$INST" \
  || fail "installer DMI soft-check must match is_thinkpad_p15 regex"
grep -qE '(^|[[:space:]_/])20SU' "$ROOT/scripts/lib/dmi.sh" \
  || fail "is_thinkpad_p15 must match 20SU"

grep -q 'firewalld' "$INST" \
  || fail "arch-install-p15 must install/enable firewalld"
grep -q 'DefaultZone=drop' "$INST" \
  || fail "arch-install-p15 must set firewalld DefaultZone=drop"
grep -q 'systemctl mask ufw' "$INST" \
  || fail "arch-install-p15 must mask ufw before/with firewalld enable"
grep -q 'htop btop fastfetch' "$INST" \
  || fail "arch-install-p15 base must include htop btop fastfetch"
grep -qE 'systemctl enable.*\bufw\b' "$INST" \
  && fail "arch-install-p15 must not enable ufw" || true
grep -qF 'DO_AUTO_PART=1' "$INST" \
  || fail "AUTO wipe must be deferred (DO_AUTO_PART) until after identity"

# Identity validators: drift-check vs lib (curl-able embed)
IDLIB="$ROOT/scripts/lib/install-identity.sh"
[[ -f $IDLIB ]] || fail "missing $IDLIB"
extract_fn() {
  awk -v n="$2" '
    $0 ~ "^" n "\\(\\)" {grab=1}
    grab {print; if ($0 == "}") exit}
  ' "$1"
}
for fn in valid_hostname valid_username valid_timezone valid_locale valid_keymap; do
  diff -u <(extract_fn "$IDLIB" "$fn") <(extract_fn "$INST" "$fn") >/dev/null \
    || fail "drift: $fn differs between install-identity.sh and arch-install-p15.sh"
done
# shellcheck disable=SC2016
grep -qF 'valid_username "$USERNAME"' "$INST" \
  || fail "installer must call valid_username before wipe"
awk '
  /ok "target profile: P15 Gen 1 Optimus \(20SU\)"/ {
    if (prev !~ /20SU/) { print "FAIL: ok profile not gated by DMI"; exit 1 }
    found=1
  }
  { prev=$0 }
  END { if (!found) { print "FAIL: missing ok profile"; exit 1 } }
' "$INST" || fail "ok target profile must only print on DMI match"
grep -qF 'First login via GDM (Wayland) if GNOME installed cleanly' "$INST" \
  || fail "finish text must not hard-claim GDM"
grep -qF 'systemctl is-active thinkpad-charge-thresholds.service' "$INST" \
  || fail "finish summary should mention charge service"
grep -q 'HelllGuest/t14s-arch-install' "$INST" \
  || fail "arch-install-p15 must point at canonical public Stage A"
grep -q 'HW_PROFILE=p15' "$INST" \
  || fail "finish text should mention HW_PROFILE=p15"

# Charge stack parity with templates (same as T14s installer)
grep -q 'thinkpad-charge-thresholds.conf' "$INST" \
  || fail "arch-install-p15 must ship charge tmpfiles"
grep -q 'thinkpad-charge-thresholds.service' "$INST" \
  || fail "arch-install-p15 must enable charge oneshot"
grep -q 'After=multi-user.target' "$INST" \
  || fail "charge oneshot must After=multi-user.target"
grep -q '/usr/local/lib/thinkpad/apply-charge-thresholds.sh' "$INST" \
  || fail "installer apply path must be /usr/local/lib/thinkpad/"
grep -q '61-thinkpad-charge-limit.rules' "$INST" \
  || fail "arch-install-p15 must seed 61-thinkpad-charge-limit.rules"
while IFS= read -r line; do
  [[ "$line" == w\ * ]] || continue
  grep -qF "$line" "$INST" \
    || fail "arch-install-p15 heredoc missing conf line: $line"
done <"$ROOT/scripts/lib/thinkpad-charge-thresholds.conf"
_rend="$ROOT/scripts/lib"
_exp_apply="$(mktemp)"
_exp_unit="$(mktemp)"
sed -e 's|@@START@@|70|g' -e 's|@@END@@|80|g' -e \
  's|@@APPLY@@|/usr/local/lib/thinkpad/apply-charge-thresholds.sh|g' \
  "$_rend/apply-charge-thresholds.sh.tmpl" >"$_exp_apply"
sed -e 's|@@START@@|70|g' -e 's|@@END@@|80|g' -e \
  's|@@APPLY@@|/usr/local/lib/thinkpad/apply-charge-thresholds.sh|g' \
  "$_rend/thinkpad-charge-thresholds.service.tmpl" >"$_exp_unit"
while IFS= read -r line; do
  [[ -n $line ]] || continue
  grep -qF "$line" "$INST" \
    || fail "installer apply heredoc drifted from template: $line"
done <"$_exp_apply"
while IFS= read -r line; do
  [[ -n $line ]] || continue
  grep -qF "$line" "$INST" \
    || fail "installer unit heredoc drifted from template: $line"
done <"$_exp_unit"
rm -f "$_exp_apply" "$_exp_unit"

# Passwords must not enter arch-chroot via environ
grep -q '\.install-secrets' "$INST" \
  || fail "arch-install-p15 must use .install-secrets for chroot passwords"
grep -E 'arch-chroot.*/mnt env' -A8 "$INST" | grep -q 'USER_PASS=' \
  && fail "arch-install-p15 must not pass USER_PASS via arch-chroot env" || true
grep -E 'arch-chroot.*/mnt env' -A8 "$INST" | grep -q 'ROOT_PASS=' \
  && fail "arch-install-p15 must not pass ROOT_PASS via arch-chroot env" || true
grep -E 'arch-chroot.*/mnt env' -A8 "$INST" | grep -q 'INSTALL_OLLAMA=' \
  || fail "arch-chroot must pass INSTALL_OLLAMA into chroot"

# First-boot seeds
for _seed in \
  's2idle.conf' \
  'thinkpad-lid.conf' \
  'zz-x86-64-v3.conf' \
  '99-wayland.conf' \
  'LIBVA_DRIVER_NAME=iHD' \
  '61-gdm-wayland.rules' \
  'gdm.service.d/override.conf' \
  '0x8086' \
  '0x10de'
do
  grep -q "$_seed" "$INST" \
    || fail "arch-install-p15.sh must seed $_seed for first boot"
done
unset -v _seed

# Profile + detect
grep -q 'nvidia' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 profile must mention nvidia"
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
mock_dmi "$TMP/p15" \
  product_family "ThinkPad P15 Gen 1" \
  product_version "ThinkPad P15 Gen 1" \
  product_name "20SUS2FJ00" \
  product_sku "LENOVO_MT_20SU" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/p15"
is_thinkpad_p15 || fail "20SU must match is_thinkpad_p15"
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" == thinkpad-p15 ]] \
  || fail "detect-profile must return thinkpad-p15 for P15 Gen 1"

# Negative: T14s must not pick p15 installer DMI path in detect
mock_dmi "$TMP/cr" \
  product_family "ThinkPad T14s Gen 3" \
  product_name "21CRS1PU00" \
  product_sku "LENOVO_MT_21CR_BU_Think_FM_ThinkPad T14s Gen 3" \
  chassis_type "10"
export DMI_SYSFS_ROOT="$TMP/cr"
is_thinkpad_p15 && fail "T14s 21CR must NOT match is_thinkpad_p15" || true
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" != thinkpad-p15 ]] \
  || fail "detect-profile must not return thinkpad-p15 for T14s"

echo "PASS: thinkpad-p15 tests"
