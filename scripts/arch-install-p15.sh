#!/usr/bin/env bash
# arch-install-p15.sh — thin Stage A handoff (ThinkPad P15 Gen 1 Optimus)
#
# Canonical installer: t14s-arch-install/install.sh (in HelllGuest/dotfiles)
#   HW_PROFILE=p15 (20SU, intel-ucode, nvidia modeset, optional ollama)
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install-p15.sh)
#
# After first boot: clone this dotfiles tree && ./install.sh → profiles/thinkpad-p15.sh
set -euo pipefail

_DOTFILES_RAW="${DOTFILES_RAW:-https://raw.githubusercontent.com/HelllGuest/dotfiles/main}"
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n ${_here:-} && -f $_here/lib/stage-a-handoff.sh ]]; then
  # shellcheck source=lib/stage-a-handoff.sh
  source "$_here/lib/stage-a-handoff.sh"
  STAGE_A_DOTFILES_ROOT="$(cd "$_here/.." && pwd)"
  export STAGE_A_DOTFILES_ROOT
else
  _url="${STAGE_A_HANDOFF_URL:-$_DOTFILES_RAW/scripts/lib/stage-a-handoff.sh}"
  _handoff="$(mktemp /tmp/stage-a-handoff.XXXXXX)"
  if ! curl -fsSL "$_url" -o "$_handoff"; then
    rm -f -- "$_handoff"
    printf 'ERR: failed to fetch %s\n' "$_url" >&2
    exit 1
  fi
  # shellcheck disable=SC1090,SC1091
  source "$_handoff"
  rm -f -- "$_handoff"
fi
stage_a_handoff p15 "$@"
