#!/usr/bin/env bash
# detect-profile.sh — suggest profiles/*.sh from hardware (sysfs first, no sudo).
# Usage:
#   detect-profile.sh              → primary profile name (stdout)
#   detect-profile.sh --has-nvidia → exit 0 when a discrete NVIDIA GPU is present

set -euo pipefail

dmi_field() {
  local f="$1"
  if [ -r "/sys/class/dmi/id/$f" ]; then
    cat "/sys/class/dmi/id/$f"
  elif command -v dmidecode >/dev/null 2>&1; then
    dmidecode -s "$f" 2>/dev/null || true
  fi
}

has_nvidia_gpu() {
  command -v lspci >/dev/null 2>&1 || return 1
  lspci -nn 2>/dev/null | grep -qiE 'vga|3d|display.*\[10de:'
}

is_laptop_chassis() {
  case "${1:-}" in
    8|9|10|11|14|31|32) return 0 ;; # portable, laptop, notebook, sub-notebook, ...
  esac
  return 1
}

if [[ ${1:-} == --has-nvidia ]]; then
  has_nvidia_gpu
  exit $?
fi

product_name="$(dmi_field product_name)"
product_family="$(dmi_field product_family)"
product_version="$(dmi_field product_version)"
chassis_type="$(dmi_field chassis_type)"
dmi_label="${product_family} ${product_version} ${product_name}"

if echo "$dmi_label" | grep -qiE 'ThinkPad[[:space:]]*X1|X1[[:space:]]+Yoga|X1[[:space:]]+Carbon'; then
  printf '%s\n' thinkpad-x1
  exit 0
fi

if echo "$dmi_label" | grep -qi 'ThinkPad'; then
  printf '%s\n' laptop
  exit 0
fi

if is_laptop_chassis "$chassis_type"; then
  printf '%s\n' laptop
  exit 0
fi

if has_nvidia_gpu; then
  printf '%s\n' nvidia
  exit 0
fi

printf '%s\n' desktop
