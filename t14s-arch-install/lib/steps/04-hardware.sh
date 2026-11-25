# 04-hardware.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# Wizard step 2/11: DMI check and hardware profile (T14s / P15 / Generic x86_64).
# Runs after 03-answers.sh so HW_PROFILE from T14S_ANSWERS is honored and normalized.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# Soft DMI check — T14s Gen 3 AMD (21CQ/21CR), P15 Gen 1 (20SU), or Generic x86_64.
ui_step 2 Hardware
_dmi_dir="${T14S_DMI_DIR:-/sys/class/dmi/id}"
_dmi="$({ cat "$_dmi_dir/product_family" "$_dmi_dir/product_version" \
          "$_dmi_dir/product_name" "$_dmi_dir/product_sku" 2>/dev/null || true; } \
        | tr '\n' ' ')"
unset -v _dmi_dir
HW_PROFILE="${HW_PROFILE:-}"
if [[ -z $HW_PROFILE ]]; then
  if echo "$_dmi" | grep -qiE '(^|[[:space:]_/])21C[QR]([[:alnum:]_-]|$)'; then
    HW_PROFILE=t14s
  elif echo "$_dmi" | grep -qiE '(^|[[:space:]_/])20SU([[:alnum:]_-]|$)'; then
    HW_PROFILE=p15
  fi
fi
case ${HW_PROFILE,,} in
  t14s|thinkpad-t14s) HW_PROFILE=t14s ;;
  p15|thinkpad-p15) HW_PROFILE=p15 ;;
  generic|auto) HW_PROFILE=generic ;;
  "")
    if (( NONINTERACTIVE )); then
      HW_PROFILE=generic
      warn "NONINTERACTIVE: DMI not 21CQ/21CR or 20SU (${_dmi:-unknown}) — HW_PROFILE=generic"
    elif [[ $(detect_vm_hypervisor) != none ]]; then
      HW_PROFILE=generic
      ok "VM detected ($(detect_vm_hypervisor)) — HW_PROFILE=generic"
    else
      HW_PROFILE="$(ui_radio "Hardware profile (DMI: ${_dmi:-unknown})" \
        generic "Generic x86_64 — auto-detect CPU/GPU/ThinkPad" on \
        t14s "ThinkPad T14s Gen 3 AMD (21CQ/21CR)" off \
        p15 "ThinkPad P15 Gen 1 Optimus (20SU)" off)" || die "aborted"
    fi
    ;;
  *)
    die "unsupported HW_PROFILE=$HW_PROFILE (use t14s|p15|generic)"
    ;;
esac
if [[ $HW_PROFILE == t14s ]]; then
  ok "target profile: T14s Gen 3 AMD (21CQ/21CR)"
  if ! grep -q AuthenticAMD /proc/cpuinfo; then
    if (( NONINTERACTIVE )); then
      warn "NONINTERACTIVE: CPU not AuthenticAMD — continuing (amd-ucode/cmdline still set)"
    else
      ui_yesno "CPU is not AuthenticAMD.
T14s profile sets amd-ucode + amd_iommu/amd_pstate.

Continue without an AMD CPU (VM rehearsal)?" no warn \
        || die "aborted — need AuthenticAMD or explicit YES"
    fi
  fi
elif [[ $HW_PROFILE == p15 ]]; then
  ok "target profile: P15 Gen 1 (20SU Optimus)"
  if ! grep -q GenuineIntel /proc/cpuinfo; then
    if (( NONINTERACTIVE )); then
      warn "NONINTERACTIVE: CPU not GenuineIntel — continuing (intel-ucode/cmdline still set)"
    else
      ui_yesno "CPU is not GenuineIntel.
P15 profile sets intel-ucode + nvidia_drm modeset.

Continue without an Intel CPU (VM rehearsal)?" no warn \
        || die "aborted — need GenuineIntel or explicit YES"
    fi
  fi
else
  ok "target profile: Generic x86_64 (CPU=$(detect_cpu_vendor), GPU=$(detect_gpu_vendors || true))"
fi
