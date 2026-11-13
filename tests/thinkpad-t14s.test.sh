#!/usr/bin/env bash
# Smoke: T14s Gen 3 AMD installer + DMI detect (21CQ/21CR only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for f in \
  "$ROOT/scripts/arch-install-t14s.sh" \
  "$ROOT/profiles/thinkpad-t14s.sh" \
  "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  "$ROOT/scripts/lib/dmi.sh" \
  "$ROOT/scripts/lib/install-identity.sh" \
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
grep -q 'firewalld' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must install/enable firewalld"
grep -q 'DefaultZone=drop' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must set firewalld DefaultZone=drop"
grep -q 'systemctl mask ufw' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must mask ufw before/with firewalld enable"
grep -qE 'systemctl enable.*\bufw\b' "$ROOT/scripts/arch-install-t14s.sh" \
  && fail "arch-install-t14s must not enable ufw" || true
grep -qE '(^|[[:space:]_/])20SU' "$ROOT/scripts/lib/dmi.sh" \
  || fail "is_thinkpad_p15 must match 20SU (Stage A parity)"
grep -qF 'DO_AUTO_PART=1' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "AUTO wipe must be deferred (DO_AUTO_PART) until after identity"
# Identity validators: real inputs via shared lib; drift-check vs installers
IDLIB="$ROOT/scripts/lib/install-identity.sh"
[[ -f $IDLIB ]] || fail "missing $IDLIB"
# shellcheck source=scripts/lib/install-identity.sh
source "$IDLIB"
extract_fn() { # $1 file $2 name — body including signature
  awk -v n="$2" '
    $0 ~ "^" n "\\(\\)" {grab=1}
    grab {print; if ($0 == "}") exit}
  ' "$1"
}
for fn in valid_hostname valid_username valid_timezone valid_locale valid_keymap; do
  for inst in \
    "$ROOT/scripts/arch-install-t14s.sh" \
    "$ROOT/scripts/arch-install.sh"
  do
    diff -u <(extract_fn "$IDLIB" "$fn") <(extract_fn "$inst" "$fn") >/dev/null \
      || fail "drift: $fn differs between install-identity.sh and $(basename "$inst")"
  done
done
valid_hostname thinkpad-t14s || fail "hostname thinkpad-t14s should pass"
valid_hostname a || fail "hostname a should pass"
valid_hostname -bad && fail "hostname -bad should fail" || true
valid_hostname bad- && fail "hostname bad- should fail" || true
valid_hostname 'bad..host' && fail "hostname bad..host should fail" || true
valid_username root && fail "username root should fail" || true
valid_username bin && fail "username bin should fail" || true
valid_username nobody && fail "username nobody should fail" || true
for _g in wheel audio video users; do
  if getent group "$_g" >/dev/null 2>&1; then
    valid_username "$_g" && fail "username $_g (group) should fail" || true
  fi
done
_long40='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
valid_username "$_long40" && fail "username len 40 should fail" || true
_fresh="t14sid$$"
valid_username "$_fresh" || fail "username $_fresh should pass"
valid_timezone America/New_York || fail "timezone America/New_York should pass"
valid_timezone UTC || fail "timezone UTC should pass"
valid_timezone '../../../etc/passwd' && fail "timezone path traversal should fail" || true
valid_timezone zone.tab && fail "timezone zone.tab should fail" || true
valid_timezone America && fail "timezone America (dir) should fail" || true
if [[ -f /usr/share/zoneinfo/leapseconds ]]; then
  valid_timezone leapseconds && fail "timezone leapseconds should fail (not TZif)" || true
fi
valid_timezone Factory && fail "timezone Factory should fail" || true
if [[ -f /usr/share/zoneinfo/posixrules ]]; then
  valid_timezone posixrules && fail "timezone posixrules should fail" || true
fi
# Locale/keymap: fixture overrides (gated) so ubuntu-latest CI does not need host maps.
mkdir -p "$TMP/id/keymaps" "$TMP/id/bin"
printf '%s\n' 'en_US.UTF-8 UTF-8' '#de_DE.UTF-8 UTF-8' >"$TMP/id/locales"
: >"$TMP/id/keymaps/us.map.gz"
IDENTITY_OVERRIDES=1 LOCALE_FILES="$TMP/id/locales" valid_locale en_US.UTF-8 \
  || fail "locale en_US.UTF-8 should pass (fixture)"
IDENTITY_OVERRIDES=1 LOCALE_FILES="$TMP/id/locales" valid_locale de_DE.UTF-8 \
  || fail "locale de_DE.UTF-8 (commented) should pass (fixture)"
IDENTITY_OVERRIDES=1 LOCALE_FILES="$TMP/id/locales" valid_locale NotA_Locale \
  && fail "locale NotA_Locale should fail" || true
IDENTITY_OVERRIDES=1 KEYMAP_DIR="$TMP/id/keymaps" valid_keymap us \
  || fail "keymap us should pass (fixture)"
IDENTITY_OVERRIDES=1 KEYMAP_DIR="$TMP/id/keymaps" valid_keymap not-a-real-keymap-zz \
  && fail "keymap bogus should fail" || true
IDENTITY_OVERRIDES=1 KEYMAP_DIR="$TMP/id/keymaps" valid_keymap '*' \
  && fail "keymap glob * should fail" || true
IDENTITY_OVERRIDES=1 KEYMAP_DIR="$TMP/id/keymaps" valid_keymap 'u?' \
  && fail "keymap glob u? should fail" || true
IDENTITY_OVERRIDES=1 KEYMAP_DIR="$TMP/id/keymaps" valid_keymap '[a-z]*' \
  && fail "keymap glob [a-z]* should fail" || true
# localectl path: fixed-string match (u. must not regex-match us;
# ... must not regex-match three-letter names like dvo)
cat >"$TMP/id/bin/localectl" <<'EOF'
#!/bin/sh
[ "$1" = list-keymaps ] || exit 1
printf '%s\n' us uk dvo
EOF
chmod +x "$TMP/id/bin/localectl"
# shellcheck disable=SC2016  # intentional single-quoted bash -c body
env -u KEYMAP_DIR PATH="$TMP/id/bin:/usr/bin:/bin" bash -c '
  source "$0"
  valid_keymap us || exit 11
  valid_keymap dvo || exit 14
  valid_keymap u. && exit 12
  valid_keymap "..." && exit 13
  exit 0
' "$IDLIB" || fail "stub localectl: us/dvo pass / u. and ... must fail (grep -F)"
# shellcheck disable=SC2016  # intentional literal $USERNAME in installer source
grep -qF 'valid_username "$USERNAME"' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "installer must call valid_username before wipe"
# ok profile only on DMI match branch (not after override YES)
awk '
  /ok "target profile: T14s Gen 3 AMD \(21CQ\/21CR\)"/ {
    if (prev !~ /21CQ\|21CR/) { print "FAIL: ok profile not gated by DMI"; exit 1 }
    found=1
  }
  { prev=$0 }
  END { if (!found) { print "FAIL: missing ok profile"; exit 1 } }
' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "ok target profile must only print on DMI match"
grep -qF 'First login via GDM (Wayland) if GNOME installed cleanly' \
  "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "finish text must not hard-claim GDM"
grep -qF 'systemctl is-active thinkpad-charge-thresholds.service' \
  "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "finish summary should mention charge service"

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
grep -q '^libva-utils$' "$ROOT/packages/thinkpad-t14s.txt" \
  || fail "packages/thinkpad-t14s.txt must list libva-utils"
grep -q '^wireless-regdb$' "$ROOT/packages/thinkpad-t14s.txt" \
  || fail "packages/thinkpad-t14s.txt must list wireless-regdb"
grep -q '^fprintd$' "$ROOT/packages/thinkpad-t14s.txt" \
  || fail "packages/thinkpad-t14s.txt must list fprintd"
grep -q '^libva-mesa-driver$' "$ROOT/packages/thinkpad-t14s.txt" \
  && fail "packages/thinkpad-t14s.txt must not list obsolete libva-mesa-driver" || true
grep -q 'vulkan-radeon' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must pacstrap vulkan-radeon"
grep -q 'libva-utils' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must pacstrap libva-utils"
grep -q 'wireless-regdb' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must pacstrap wireless-regdb"
grep -q '71-thinkpad-t14s-touchpad-wakeup.rules' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must seed 71-thinkpad-t14s-touchpad-wakeup.rules"
grep -q '61-thinkpad-charge-limit.rules' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must seed 61-thinkpad-charge-limit.rules"
grep -q '71-thinkpad-t14s-touchpad-wakeup.rules' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "profiles/thinkpad-t14s.sh must install 71-thinkpad-t14s-touchpad-wakeup.rules"
grep -q '61-thinkpad-charge-limit.rules' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "profiles/thinkpad-t14s.sh must install 61-thinkpad-charge-limit.rules"
grep -q 'LIBVA_DRIVER_NAME=radeonsi' "$ROOT/stow/zsh/.shell-exports" \
  || fail ".shell-exports must set LIBVA_DRIVER_NAME=radeonsi on amdgpu"
grep -q 'LIBVA_DRIVER_NAME=radeonsi' "$ROOT/scripts/system-setup.sh" \
  || fail "system-setup.sh must rewrite LIBVA_DRIVER_NAME=radeonsi on amdgpu"
grep -q 'LIBVA_DRIVER_NAME=radeonsi' "$ROOT/scripts/gdm-setup.sh" \
  || fail "gdm-setup.sh must rewrite LIBVA_DRIVER_NAME=radeonsi on amdgpu"
grep -q '0x1002' "$ROOT/stow/gdm/etc/udev/rules.d/61-gdm-wayland.rules" \
  || fail "61-gdm-wayland.rules must include AMD vendor 0x1002"
grep -q 'yoga-tablet-mode.service' "$ROOT/scripts/gnome-session-setup.sh" \
  || fail "gnome-session-setup.sh must disable leftover yoga-tablet-mode.service"
grep -qE 'is_thinkpad_x1|yoga-tablet-mode' "$ROOT/scripts/validate-configs.sh" \
  && fail "validate-configs.sh must not gate or check yoga-tablet-mode / is_thinkpad_x1" || true
grep -q 'thinkpad-charge-thresholds.conf' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must ship charge tmpfiles"
grep -q 'thinkpad-charge-thresholds.service' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must enable charge oneshot"
grep -q 'After=multi-user.target' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "charge oneshot must After=multi-user.target"
grep -q '/usr/local/lib/thinkpad/apply-charge-thresholds.sh' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "installer apply path must be /usr/local/lib/thinkpad/"
grep -q '/usr/local/lib/t14s/' "$ROOT/scripts/arch-install-t14s.sh" \
  && fail "installer must not use legacy /usr/local/lib/t14s/" || true
# Installer heredoc must match canonical BAT0 template (w-lines)
while IFS= read -r line; do
  [[ "$line" == w\ * ]] || continue
  grep -qF "$line" "$ROOT/scripts/arch-install-t14s.sh" \
    || fail "arch-install-t14s heredoc missing conf line: $line"
done <"$ROOT/scripts/lib/thinkpad-charge-thresholds.conf"
# Apply/unit heredocs must match rendered templates (parity; curl installer embeds copy)
for f in \
  "$ROOT/scripts/lib/apply-charge-thresholds.sh.tmpl" \
  "$ROOT/scripts/lib/thinkpad-charge-thresholds.service.tmpl"
do
  [[ -f $f ]] || fail "missing template $f"
done
_rend="$ROOT/scripts/lib"
_exp_apply="$(mktemp)"
_exp_unit="$(mktemp)"
sed -e 's|@@START@@|70|g' -e 's|@@END@@|80|g' -e \
  's|@@APPLY@@|/usr/local/lib/thinkpad/apply-charge-thresholds.sh|g' \
  "$_rend/apply-charge-thresholds.sh.tmpl" >"$_exp_apply"
sed -e 's|@@START@@|70|g' -e 's|@@END@@|80|g' -e \
  's|@@APPLY@@|/usr/local/lib/thinkpad/apply-charge-thresholds.sh|g' \
  "$_rend/thinkpad-charge-thresholds.service.tmpl" >"$_exp_unit"
# Every non-empty line from rendered templates must appear in the installer.
while IFS= read -r line; do
  [[ -n $line ]] || continue
  grep -qF "$line" "$ROOT/scripts/arch-install-t14s.sh" \
    || fail "installer apply heredoc drifted from template: $line"
done <"$_exp_apply"
while IFS= read -r line; do
  [[ -n $line ]] || continue
  grep -qF "$line" "$ROOT/scripts/arch-install-t14s.sh" \
    || fail "installer unit heredoc drifted from template: $line"
done <"$_exp_unit"
rm -f "$_exp_apply" "$_exp_unit"
grep -q 'POWER_SUPPLY_ROOT' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "charge helper must support POWER_SUPPLY_ROOT for tests"
grep -q 'thinkpad-charge-thresholds.service' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "charge helper must install late-boot service"
grep -q '/usr/local/lib/thinkpad/' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "helper default apply path must be /usr/local/lib/thinkpad/"
grep -q 'install -m' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "helper must install with explicit mode (not raw 0600 mktemp copy)"
# Generic installer must NOT claim charge setup (machine scripts do: t14s + p15)
grep -q 'thinkpad-charge-thresholds' "$ROOT/scripts/arch-install.sh" \
  && fail "arch-install.sh must not seed charge thresholds (use arch-install-t14s/p15)" || true

# Passwords must not enter arch-chroot via environ (/proc leak).
for _inst in arch-install-t14s.sh arch-install.sh; do
  grep -q '\.install-secrets' "$ROOT/scripts/$_inst" \
    || fail "$_inst must use .install-secrets for chroot passwords"
  grep -E 'arch-chroot.*/mnt env' -A6 "$ROOT/scripts/$_inst" | grep -q 'USER_PASS=' \
    && fail "$_inst must not pass USER_PASS via arch-chroot env" || true
  grep -E 'arch-chroot.*/mnt env' -A6 "$ROOT/scripts/$_inst" | grep -q 'ROOT_PASS=' \
    && fail "$_inst must not pass ROOT_PASS via arch-chroot env" || true
done
unset _inst
grep -q 'HelllGuest/t14s-arch-install' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must point at canonical public Stage A"
grep -q 'systemctl is-enabled thinkpad-charge-thresholds.service' \
  "$ROOT/docs/hardened-arch-gnome.md" \
  || fail "Verify Battery Thresholds must check service enabled"

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

# Retired X1 Yoga: no thinkpad-x1 profile; chassis → laptop fallback
mock_dmi "$TMP/x1" \
  product_family "ThinkPad X1 Yoga" \
  product_version "ThinkPad X1 Yoga Gen 5" \
  product_name "20UC001BUS" \
  product_sku "LENOVO_MT_20UC" \
  chassis_type "31"
export DMI_SYSFS_ROOT="$TMP/x1"
[[ "$(bash "$ROOT/scripts/detect-profile.sh")" == laptop ]] \
  || fail "detect-profile must return laptop for retired X1 Yoga"

# P15 Gen 1 (20SU) → thinkpad-p15
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

# Late-boot service install (test paths; no systemctl)
APPLY_OUT="$TMP/apply-charge-thresholds.sh"
UNIT_OUT="$TMP/thinkpad-charge-thresholds.service"
out_svc="$(
  POWER_SUPPLY_ROOT="$PSY" CHARGE_TMPFILES="$CONF_OUT" \
    CHARGE_APPLY_SCRIPT="$APPLY_OUT" CHARGE_SERVICE_UNIT="$UNIT_OUT" \
    CHARGE_SKIP_SYSTEMCTL=1 CHARGE_START=70 CHARGE_END=80 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "charge helper service install failed: $out_svc"
[[ -x "$APPLY_OUT" ]] || fail "apply script not installed executable"
# Modes: conf/unit 0644 (not mktemp 0600); apply 0755
_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1"; }
[[ "$(_mode "$CONF_OUT")" == 644 ]] || fail "tmpfiles conf must be mode 644 (got $(_mode "$CONF_OUT"))"
[[ "$(_mode "$UNIT_OUT")" == 644 ]] || fail "unit must be mode 644 (got $(_mode "$UNIT_OUT"))"
[[ "$(_mode "$APPLY_OUT")" == 755 ]] || fail "apply must be mode 755 (got $(_mode "$APPLY_OUT"))"
grep -q 'START=70' "$APPLY_OUT" || fail "apply script must embed START"
grep -q 'END=80' "$APPLY_OUT" || fail "apply script must embed END"
grep -q 'After=multi-user.target' "$UNIT_OUT" \
  || fail "unit must After=multi-user.target"
grep -q "ExecStart=${APPLY_OUT}" "$UNIT_OUT" \
  || fail "unit must ExecStart apply script"
bash -n "$APPLY_OUT" || fail "generated apply script bash -n failed"
# Rendered apply must match template
diff -u \
  <(sed -e 's|@@START@@|70|g' -e 's|@@END@@|80|g' \
      "$ROOT/scripts/lib/apply-charge-thresholds.sh.tmpl") \
  "$APPLY_OUT" >/dev/null \
  || fail "helper apply output drifted from template"
# CHARGE_SKIP_SERVICE skips unit even with explicit paths
rm -f "$APPLY_OUT" "$UNIT_OUT"
POWER_SUPPLY_ROOT="$PSY" CHARGE_TMPFILES="$CONF_OUT" \
  CHARGE_APPLY_SCRIPT="$APPLY_OUT" CHARGE_SERVICE_UNIT="$UNIT_OUT" \
  CHARGE_SKIP_SERVICE=1 CHARGE_SKIP_SYSTEMCTL=1 \
  bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" >/dev/null \
  || fail "CHARGE_SKIP_SERVICE run failed"
[[ ! -e "$APPLY_OUT" ]] || fail "CHARGE_SKIP_SERVICE must not install apply script"

# No BAT yet + ThinkPad DMI → seed BAT0 + unit; stub systemctl proves non-block.
PSY_EMPTY="$TMP/psy_empty"
CONF_SEED="$TMP/seed.conf"
APPLY_SEED="$TMP/seed-apply.sh"
UNIT_SEED="$TMP/seed.service"
SCTCTL_LOG="$TMP/systemctl.log"
BIN_STUB="$TMP/bin"
mkdir -p "$PSY_EMPTY/BAT0" "$BIN_STUB"
# Record argv; pass-through sudo (strip -A from SUDO_ASKPASS hosts).
cat >"$BIN_STUB/sudo" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case $1 in
    -A|-n|-E) shift ;;
    *) break ;;
  esac
done
exec "$@"
STUB
cat >"$BIN_STUB/systemctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SCTCTL_LOG:?}"
exit 0
STUB
chmod 755 "$BIN_STUB/sudo" "$BIN_STUB/systemctl"
: >"$SCTCTL_LOG"
export SCTCTL_LOG
mock_dmi "$TMP/seed_dmi" \
  product_family "ThinkPad T14s Gen 3" \
  product_sku "21CRS1PU00" \
  chassis_type "10"
out_seed="$(
  DMI_SYSFS_ROOT="$TMP/seed_dmi" \
  POWER_SUPPLY_ROOT="$PSY_EMPTY" CHARGE_TMPFILES="$CONF_SEED" \
    CHARGE_APPLY_SCRIPT="$APPLY_SEED" CHARGE_SERVICE_UNIT="$UNIT_SEED" \
    SCTCTL_LOG="$SCTCTL_LOG" PATH="$BIN_STUB:$PATH" \
    env -u SUDO_ASKPASS \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "no-BAT service seed failed: $out_seed"
echo "$out_seed" | grep -qi 'seed BAT0\|late-boot' \
  || fail "no-BAT+ThinkPad must say seed/late-boot: $out_seed"
grep -q 'BAT0/charge_control_start_threshold' "$CONF_SEED" \
  || fail "no-BAT seed must write BAT0 tmpfiles"
[[ -x "$APPLY_SEED" && -f "$UNIT_SEED" ]] || fail "no-BAT seed must install unit+apply"
grep -qx 'enable thinkpad-charge-thresholds.service' "$SCTCTL_LOG" \
  || fail "seed must systemctl enable (got: $(tr '\n' ';' <"$SCTCTL_LOG"))"
grep -qx 'start --no-block thinkpad-charge-thresholds.service' "$SCTCTL_LOG" \
  || fail "seed must systemctl start --no-block (got: $(tr '\n' ';' <"$SCTCTL_LOG"))"
grep -qE '(^| )--now( |$)' "$SCTCTL_LOG" \
  && fail "seed must not use enable --now (would block 60s)" || true

# Live BAT path uses enable --now (behavior, not source grep)
: >"$SCTCTL_LOG"
CONF_LIVE="$TMP/live.conf"
APPLY_LIVE="$TMP/live-apply.sh"
UNIT_LIVE="$TMP/live.service"
out_live="$(
  DMI_SYSFS_ROOT="$TMP/seed_dmi" \
  POWER_SUPPLY_ROOT="$PSY" CHARGE_TMPFILES="$CONF_LIVE" \
    CHARGE_APPLY_SCRIPT="$APPLY_LIVE" CHARGE_SERVICE_UNIT="$UNIT_LIVE" \
    SCTCTL_LOG="$SCTCTL_LOG" PATH="$BIN_STUB:$PATH" \
    env -u SUDO_ASKPASS \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "live-BAT service install failed: $out_live"
grep -qx 'enable --now thinkpad-charge-thresholds.service' "$SCTCTL_LOG" \
  || fail "live BAT must systemctl enable --now (got: $(tr '\n' ';' <"$SCTCTL_LOG"))"
grep -q 'start --no-block' "$SCTCTL_LOG" \
  && fail "live BAT must not use start --no-block" || true

# Desktop/VM + no BAT + service hooks → plain skip
mock_dmi "$TMP/desk_dmi" \
  product_family "QEMU Virtual Machine" \
  product_name "Standard PC" \
  chassis_type "1"
CONF_DESK="$TMP/desk.conf"
APPLY_DESK="$TMP/desk-apply.sh"
UNIT_DESK="$TMP/desk.service"
out_desk="$(
  DMI_SYSFS_ROOT="$TMP/desk_dmi" \
  POWER_SUPPLY_ROOT="$PSY_EMPTY" CHARGE_TMPFILES="$CONF_DESK" \
    CHARGE_APPLY_SCRIPT="$APPLY_DESK" CHARGE_SERVICE_UNIT="$UNIT_DESK" \
    CHARGE_SKIP_SYSTEMCTL=1 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "desktop no-BAT must exit 0: $out_desk"
echo "$out_desk" | grep -qi 'skip' || fail "desktop no-BAT must skip: $out_desk"
[[ ! -e "$CONF_DESK" && ! -e "$APPLY_DESK" && ! -e "$UNIT_DESK" ]] \
  || fail "desktop no-BAT must not install conf/unit/apply"

# Non-ThinkPad laptop chassis + no BAT → skip (not a late-acpi race)
mock_dmi "$TMP/dell_dmi" \
  product_family "Latitude" \
  product_name "Latitude 7420" \
  chassis_type "10"
CONF_DELL="$TMP/dell.conf"
APPLY_DELL="$TMP/dell-apply.sh"
UNIT_DELL="$TMP/dell.service"
out_dell="$(
  DMI_SYSFS_ROOT="$TMP/dell_dmi" \
  POWER_SUPPLY_ROOT="$PSY_EMPTY" CHARGE_TMPFILES="$CONF_DELL" \
    CHARGE_APPLY_SCRIPT="$APPLY_DELL" CHARGE_SERVICE_UNIT="$UNIT_DELL" \
    CHARGE_SKIP_SYSTEMCTL=1 \
    bash "$ROOT/scripts/thinkpad-charge-thresholds.sh" 2>&1
)" || fail "non-ThinkPad laptop no-BAT must exit 0: $out_dell"
echo "$out_dell" | grep -qi 'skip' || fail "non-ThinkPad laptop must skip: $out_dell"
[[ ! -e "$CONF_DELL" && ! -e "$APPLY_DELL" && ! -e "$UNIT_DELL" ]] \
  || fail "non-ThinkPad laptop must not install conf/unit/apply"

# Templates must be tracked in git when this tree is a checkout (skip tarballs)
if git -C "$ROOT" rev-parse >/dev/null 2>&1; then
  git -C "$ROOT" ls-files --error-unmatch \
    scripts/lib/apply-charge-thresholds.sh.tmpl \
    scripts/lib/thinkpad-charge-thresholds.service.tmpl >/dev/null \
    || fail "git-add scripts/lib/*.tmpl before commit (fresh clones need them)"
fi

# Docs: Phase 14 anchor uses double hyphen (em dash in heading)
grep -q 'phase-14--thinkpad-optimization' "$ROOT/docs/fresh-install-coding-re.md" \
  || fail "fresh-install must link Phase 14 with double-hyphen anchor"

# install.sh package step: pacman reads targets from stdin and does NOT skip
# "#" lines, so comments/blanks must be stripped; with tuned-ppd installed,
# power-profiles-daemon must be dropped. Run the real block with stubs.
_pkgblk="$(awk '/^if \[ -f "packages\/pacman.txt" \]; then$/{f=1} f; f&&/^fi$/{exit}' "$ROOT/install.sh")"
[[ -n $_pkgblk ]] || fail "install.sh pacman.txt block not found"
mkdir -p "$TMP/pk/bin" "$TMP/pk/repo/packages"
printf '%s\n' '# comment' 'bash' '' '  # indented comment' 'power-profiles-daemon' \
  'zsh   # trailing comment' >"$TMP/pk/repo/packages/pacman.txt"
cat >"$TMP/pk/bin/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
cat >"$TMP/pk/bin/pacman" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == -Q ]]; then [[ -n ${PK_TUNED:-} && $2 == tuned-ppd ]]; exit; fi
cat >"$PK_OUT"
STUB
chmod +x "$TMP/pk/bin/sudo" "$TMP/pk/bin/pacman"
for _mode in ppd tuned; do
  _tuned=""; [[ $_mode == tuned ]] && _tuned=1
  (cd "$TMP/pk/repo" && PK_TUNED="$_tuned" PK_OUT="$TMP/pk/$_mode.out" \
    PATH="$TMP/pk/bin:$PATH" bash -c "$_pkgblk" >/dev/null) \
    || fail "install.sh package block failed ($_mode)"
  grep -q '#' "$TMP/pk/$_mode.out" && fail "pacman stdin must not contain comments ($_mode)"
  grep -qx '' "$TMP/pk/$_mode.out" && fail "pacman stdin must not contain blank lines ($_mode)"
  grep -qx 'zsh' "$TMP/pk/$_mode.out" || fail "trailing comment must be stripped, keeping zsh ($_mode)"
done
grep -qx 'power-profiles-daemon' "$TMP/pk/ppd.out" || fail "PPD host must still get power-profiles-daemon"
grep -qx 'power-profiles-daemon' "$TMP/pk/tuned.out" \
  && fail "tuned-ppd host must not request power-profiles-daemon (conflict aborts --noconfirm)" || true
# T14s AMD host: Intel/NVIDIA GPU packages in pacman.txt must be filtered out,
# while non-T14s hosts (e.g. P15) keep them.
mkdir -p "$TMP/pk/repo/scripts/lib"
cp "$ROOT/scripts/lib/dmi.sh" "$TMP/pk/repo/scripts/lib/dmi.sh"
printf '%s\n' 'atuin' 'intel-media-driver' 'vulkan-intel' 'nvidia-open-dkms' \
  'nvidia-prime' 'nvidia-utils' 'stow' >"$TMP/pk/repo/packages/pacman.txt"
(cd "$TMP/pk/repo" && DMI_SYSFS_ROOT="$TMP/cr" PK_OUT="$TMP/pk/t14s.out" \
  PATH="$TMP/pk/bin:$PATH" bash -c "$_pkgblk" >/dev/null) \
  || fail "install.sh package block failed (t14s)"
grep -qx 'atuin' "$TMP/pk/t14s.out" || fail "t14s must keep atuin"
grep -qx 'stow' "$TMP/pk/t14s.out" || fail "t14s must keep stow"
grep -qE '^(intel-media-driver|vulkan-intel|nvidia-open-dkms|nvidia-prime|nvidia-utils)$' \
  "$TMP/pk/t14s.out" && fail "t14s must filter out Intel/NVIDIA GPU packages" || true
(cd "$TMP/pk/repo" && DMI_SYSFS_ROOT="$TMP/p15" PK_OUT="$TMP/pk/p15.out" \
  PATH="$TMP/pk/bin:$PATH" bash -c "$_pkgblk" >/dev/null) \
  || fail "install.sh package block failed (p15)"
for _gp in intel-media-driver vulkan-intel nvidia-open-dkms nvidia-prime nvidia-utils; do
  grep -qx "$_gp" "$TMP/pk/p15.out" || fail "non-t14s must keep $_gp"
done
unset _gp
# All-filtered manifest on T14s: must exit 0 and not invoke pacman -S.
printf '%s\n' 'intel-media-driver' 'nvidia-open-dkms' >"$TMP/pk/repo/packages/pacman.txt"
rm -f "$TMP/pk/allfilt.out"
(cd "$TMP/pk/repo" && DMI_SYSFS_ROOT="$TMP/cr" PK_OUT="$TMP/pk/allfilt.out" \
  PATH="$TMP/pk/bin:$PATH" bash -e -c "$_pkgblk" >/dev/null) \
  || fail "install.sh package block failed when all packages filtered"
[[ ! -e "$TMP/pk/allfilt.out" ]] || fail "all-filtered manifest must not invoke pacman -S"
# Comment-only manifest: pacman must not be called with an empty target list.
printf '%s\n' '# only comments' '' >"$TMP/pk/repo/packages/pacman.txt"
rm -f "$TMP/pk/empty.out"
(cd "$TMP/pk/repo" && PK_OUT="$TMP/pk/empty.out" PATH="$TMP/pk/bin:$PATH" \
  bash -c "$_pkgblk" >/dev/null) || fail "install.sh package block failed (empty)"
[[ ! -e "$TMP/pk/empty.out" ]] || fail "empty manifest must not invoke pacman -S"
unset -v _pkgblk _mode _tuned
grep -q 'pacman -Q tuned-ppd' "$ROOT/profiles/thinkpad-t14s.sh" \
  || fail "T14s profile must keep tuned + tuned-ppd instead of forcing PPD"
grep -q 'pacman -Q tuned-ppd' "$ROOT/profiles/laptop.sh" \
  || fail "laptop profile must not install PPD over tuned-ppd"
for _seed in \
  's2idle.conf' \
  'thinkpad-lid.conf' \
  'zz-x86-64-v3.conf' \
  '99-wayland.conf' \
  'LIBVA_DRIVER_NAME=radeonsi' \
  '61-gdm-wayland.rules' \
  'gdm.service.d/override.conf'
do
  grep -q "$_seed" "$ROOT/scripts/arch-install-t14s.sh" \
    || fail "arch-install-t14s.sh must seed $_seed for first boot"
done
unset -v _seed

echo "PASS: thinkpad-t14s tests"
