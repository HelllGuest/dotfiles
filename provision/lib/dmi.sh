#!/usr/bin/env bash
# Shared DMI helpers (sysfs first, no sudo).
# Sources canonical DMI/charge constants from stage-a/lib/05-policy.sh when in-repo
# (inline fallbacks keep isolated temp-dir tests working standalone).

_dmi_policy=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  _dmi_policy="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/stage-a/lib/05-policy.sh"
fi
if [[ -n $_dmi_policy && -f $_dmi_policy ]]; then
  # shellcheck source=../../stage-a/lib/05-policy.sh
  source "$_dmi_policy"
fi
unset -v _dmi_policy

STAGE_A_DMI_T14S_RE="${STAGE_A_DMI_T14S_RE:-(^|[[:space:]_/])21C[QR]([[:alnum:]_-]|$)}"
STAGE_A_DMI_P15_RE="${STAGE_A_DMI_P15_RE:-ThinkPad[[:space:]]*P15|P15[[:space:]]+Gen|(^|[[:space:]_/])20SU([[:alnum:]_-]|$)}"
# shellcheck disable=SC2034 # consumed by callers sourcing dmi.sh
CHARGE_START="${CHARGE_START:-70}"
# shellcheck disable=SC2034 # consumed by callers sourcing dmi.sh
CHARGE_END="${CHARGE_END:-80}"

dmi_field() {
  local f="$1"
  local root="${DMI_SYSFS_ROOT:-/sys/class/dmi/id}"
  if [[ -r "$root/$f" ]]; then
    cat "$root/$f"
  elif command -v dmidecode >/dev/null 2>&1; then
    dmidecode -s "$f" 2>/dev/null || true
  fi
}

dmi_label() {
  printf '%s %s %s' \
    "$(dmi_field product_family)" \
    "$(dmi_field product_version)" \
    "$(dmi_field product_name)"
}

is_thinkpad_p15() {
  # Name/version match, or machine type 20SU* (same policy as Stage A).
  local blob
  blob="$(dmi_label) $(dmi_field product_sku) $(dmi_field product_name) $(dmi_field product_version)"
  echo "$blob" | grep -qiE "$STAGE_A_DMI_P15_RE"
}

# T14s Gen 3 AMD only — machine type 21CQ / 21CR (MTM e.g. 21CRS1PU00).
# Other T14s gens (Intel or later AMD types) must not match.
is_thinkpad_t14s() {
  local blob
  blob="$(dmi_label) $(dmi_field product_sku) $(dmi_field product_name)"
  echo "$blob" | grep -qiE "$STAGE_A_DMI_T14S_RE"
}

is_laptop_chassis() {
  case "$(dmi_field chassis_type)" in
    8|9|10|11|14|31|32) return 0 ;;
  esac
  return 1
}

# NVIDIA display-class PCI function (vendor 0x10de, class 0x03xxxx). Reads sysfs,
# so it works before drivers or pciutils are installed. HDMI-audio / USB-C
# companion functions (other classes) do not count.
has_nvidia_gpu() {
  local dev root="${PCI_SYSFS_ROOT:-/sys/bus/pci/devices}"
  for dev in "$root"/*; do
    [[ -r $dev/vendor && -r $dev/class ]] || continue
    [[ $(<"$dev/vendor") == 0x10de && $(<"$dev/class") == 0x03* ]] && return 0
  done
  return 1
}

# Install a root-owned udev rule if missing/changed, reload udev, optionally trigger a subsystem.
install_udev_rule() {
  local src=$1 dst=$2 trigger_subsys=${3:-}
  [[ -f $src ]] || return 0
  if [[ ! -f $dst ]] || ! cmp -s "$src" "$dst"; then
    sudo install -D -m 0644 -o root -g root "$src" "$dst" || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    if [[ -n $trigger_subsys ]]; then
      sudo udevadm trigger --subsystem-match="$trigger_subsys" 2>/dev/null || true
    fi
  fi
}
