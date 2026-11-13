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
    if source "profiles/${name}.sh"; then
      return 0
    fi
    echo "Profile application had some failures (likely sudo)." >&2
    return 1
  fi
  return 1
}

HOST=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown")
if [[ -f "profiles/${HOST}.sh" ]]; then
  apply_profile "$HOST" "hostname"
  exit $?
fi

if [[ -f "scripts/detect-profile.sh" ]]; then
  DETECTED=$(bash scripts/detect-profile.sh 2>/dev/null || true)
  if [[ -n "$DETECTED" && -f "profiles/${DETECTED}.sh" ]]; then
    apply_profile "$DETECTED" "hardware detect"
    exit $?
  fi
  echo "No hostname or hardware profile matched. Using default install."
  exit 0
fi

echo "No specific profile found for ${HOST}. Using default."
