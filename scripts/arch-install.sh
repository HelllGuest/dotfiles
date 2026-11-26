#!/usr/bin/env bash
# arch-install.sh — thin Stage A handoff (DMI auto-detect t14s|p15|generic)
#
# Canonical installer: stage-a/install.sh (in HelllGuest/dotfiles)
# Leaves HW_PROFILE unset so the modular installer picks t14s (21CQ/21CR),
# p15 (20SU), or generic x86_64 from DMI (or prompts). Override: HW_PROFILE=t14s|p15|generic.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/scripts/arch-install.sh)
#
# After first boot: clone this dotfiles tree && ./install.sh (Stage B).
set -euo pipefail

_DOTFILES_RAW="${DOTFILES_RAW:-https://raw.githubusercontent.com/HelllGuest/dotfiles/main}"
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n ${_here:-} && -f $_here/../provision/lib/stage-a-handoff.sh ]]; then
  # shellcheck source=../provision/lib/stage-a-handoff.sh
  source "$_here/../provision/lib/stage-a-handoff.sh"
  STAGE_A_DOTFILES_ROOT="$(cd "$_here/.." && pwd)"
  export STAGE_A_DOTFILES_ROOT
else
  _url="${STAGE_A_HANDOFF_URL:-$_DOTFILES_RAW/provision/lib/stage-a-handoff.sh}"
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
# Empty profile → canonical DMI detect / TUI radio
stage_a_handoff "${HW_PROFILE:-}" "$@"
