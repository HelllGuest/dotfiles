#!/usr/bin/env bash
# Shared DMI helpers (sysfs first, no sudo).

dmi_field() {
  local f="$1"
  if [[ -r "/sys/class/dmi/id/$f" ]]; then
    cat "/sys/class/dmi/id/$f"
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

is_thinkpad_x1() {
  echo "$(dmi_label)" | grep -qiE 'ThinkPad[[:space:]]*X1|X1[[:space:]]+Yoga|X1[[:space:]]+Carbon'
}

is_thinkpad_p15() {
  echo "$(dmi_label)" | grep -qiE 'ThinkPad[[:space:]]*P15|P15[[:space:]]+Gen'
}

is_laptop_chassis() {
  case "$(dmi_field chassis_type)" in
    8|9|10|11|14|31|32) return 0 ;;
  esac
  return 1
}
