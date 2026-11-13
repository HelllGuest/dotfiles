#!/usr/bin/env bash
# Shared DMI helpers (sysfs first, no sudo).

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
  echo "$(dmi_label)" | grep -qiE 'ThinkPad[[:space:]]*P15|P15[[:space:]]+Gen'
}

# T14s Gen 3 AMD only — machine type 21CQ / 21CR (MTM e.g. 21CRS1PU00).
# Other T14s gens (Intel or later AMD types) must not match.
is_thinkpad_t14s() {
  local blob
  blob="$(dmi_label) $(dmi_field product_sku) $(dmi_field product_name)"
  echo "$blob" | grep -qiE '21CQ|21CR'
}

is_laptop_chassis() {
  case "$(dmi_field chassis_type)" in
    8|9|10|11|14|31|32) return 0 ;;
  esac
  return 1
}

has_nvidia_gpu() {
  command -v lspci >/dev/null 2>&1 || return 1
  lspci -nn 2>/dev/null | grep -qiE 'vga|3d|display.*\[10de:'
}
