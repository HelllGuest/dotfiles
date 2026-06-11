#!/usr/bin/env bash
# detect-profile.sh — suggest profiles/*.sh from hardware (sysfs first, no sudo).
# Usage:
#   detect-profile.sh              → primary profile name (stdout)
#   detect-profile.sh --has-nvidia → exit 0 when a discrete NVIDIA GPU is present

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

if [[ ${1:-} == --has-nvidia ]]; then
  has_nvidia_gpu
  exit $?
fi

if is_thinkpad_x1; then
  printf '%s\n' thinkpad-x1
  exit 0
fi

if echo "$(dmi_label)" | grep -qi 'ThinkPad'; then
  printf '%s\n' laptop
  exit 0
fi

if is_laptop_chassis; then
  printf '%s\n' laptop
  exit 0
fi

if has_nvidia_gpu; then
  printf '%s\n' nvidia
  exit 0
fi

exit 0
