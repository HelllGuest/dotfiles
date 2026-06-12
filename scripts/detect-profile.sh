#!/usr/bin/env bash
# detect-profile.sh — suggest profiles/*.sh from hardware (sysfs first, no sudo).
# Usage:
#   detect-profile.sh → primary profile name (stdout)
# NVIDIA/ThinkPad P15 profiles live on the p15 branch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

if is_thinkpad_x1; then
  printf '%s\n' thinkpad-x1
  exit 0
fi

if is_thinkpad_p15; then
  printf '%s\n' thinkpad-p15
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

exit 0
