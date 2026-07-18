#!/usr/bin/env bash
# apply-profile.sh — hostname override, else hardware detect (sources profiles/*.sh)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

apply_profile() {
  local name="$1"
  local reason="${2:-}"
  if [[ -f "profiles/${name}.sh" ]]; then
    if [[ -n "$reason" ]]; then
      echo "Applying profile '${name}' (${reason})..."
    else
      echo "Applying profile '${name}'..."
    fi
    # shellcheck source=/dev/null
    source "profiles/${name}.sh" || echo "Profile application had some failures (likely sudo)."
    return 0
  fi
  return 1
}

HOST=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown")
if apply_profile "$HOST" "hostname"; then
  exit 0
fi

if [[ -f "scripts/detect-profile.sh" ]]; then
  DETECTED=$(bash scripts/detect-profile.sh 2>/dev/null || true)
  if [[ -n "$DETECTED" ]] && apply_profile "$DETECTED" "hardware detect"; then
    exit 0
  fi
  echo "No hostname or hardware profile matched. Using default install."
  exit 0
fi

echo "No specific profile found for ${HOST}. Using default."
