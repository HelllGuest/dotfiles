#!/usr/bin/env bash
# t14s-arch-install/install.sh — compatibility shim redirecting to stage-a/install.sh.
#
# Preserves bookmarked curl URLs:
#   bash <(curl -fsSL https://raw.githubusercontent.com/HelllGuest/dotfiles/main/t14s-arch-install/install.sh)
# Canonical path: stage-a/install.sh (in HelllGuest/dotfiles).
set -euo pipefail

# 1) Local checkout: hand off directly to ../stage-a/install.sh (stays offline).
_shim_self=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  _shim_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
fi
if [[ -n $_shim_self && -f $_shim_self/../stage-a/install.sh ]]; then
  _stage_a="$(cd "$_shim_self/../stage-a" && pwd)"
  if [[ -z ${STAGE_A_LIB_DIR:-${T14S_LIB_DIR:-}} && -d $_stage_a/lib ]]; then
    export STAGE_A_LIB_DIR="$_stage_a/lib"
    export T14S_LIB_DIR="$_stage_a/lib"
  fi
  if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
    printf 'shim-local:%s\nT14S_LIB_DIR=%s\n' "$_stage_a/install.sh" "${T14S_LIB_DIR:-}"
    exit 0
  fi
  exec bash "$_stage_a/install.sh" "$@"
fi
unset -v _shim_self

# 2) Remote curl (Arch ISO): pin main SHA once, then fetch stage-a/install.sh.
STAGE_A_REPO="${STAGE_A_REPO:-HelllGuest/dotfiles}"
STAGE_A_BRANCH="${STAGE_A_BRANCH:-main}"
_base="${STAGE_A_BASE_URL:-${T14S_BASE_URL:-}}"
_ref="${STAGE_A_REF:-${T14S_REF:-}}"
if [[ -n $_base ]]; then
  _base="${_base%/}"
  # Prevent self-recursion when caller exports legacy .../t14s-arch-install base URL.
  if [[ $_base == */t14s-arch-install ]]; then
    _base="${_base%/t14s-arch-install}/stage-a"
  fi
else
  if [[ ! $STAGE_A_REPO =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    printf 'ERR: invalid STAGE_A_REPO=%s\n' "$STAGE_A_REPO" >&2
    exit 1
  fi
  if [[ ! $STAGE_A_BRANCH =~ ^[A-Za-z0-9._/-]+$ || $STAGE_A_BRANCH == *..* ]]; then
    printf 'ERR: invalid STAGE_A_BRANCH=%s\n' "$STAGE_A_BRANCH" >&2
    exit 1
  fi
  if [[ -z $_ref ]]; then
    _ref="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
      "https://api.github.com/repos/${STAGE_A_REPO}/commits/${STAGE_A_BRANCH}" 2>/dev/null || true)"
    _ref="${_ref//$'\n'/}"
    if [[ ! $_ref =~ ^[0-9a-f]{40}$ ]]; then
      printf 'ERR: could not resolve %s %s SHA (set STAGE_A_REF / T14S_REF or STAGE_A_BASE_URL)\n' \
        "$STAGE_A_REPO" "$STAGE_A_BRANCH" >&2
      exit 1
    fi
  fi
  _base="https://raw.githubusercontent.com/${STAGE_A_REPO}/${_ref}/stage-a"
fi
export STAGE_A_REF="$_ref" T14S_REF="$_ref"
export STAGE_A_BASE_URL="$_base" T14S_BASE_URL="$_base"

if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
  printf 'shim-fetch:%s/install.sh\nT14S_BASE_URL=%s\nT14S_REF=%s\n' "$_base" "$_base" "$_ref"
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  printf 'ERR: curl required to fetch %s/install.sh\n' "$_base" >&2
  exit 1
}
_tmp="$(mktemp /tmp/stage-a-shim.XXXXXX)"
curl -fsSL "$_base/install.sh" -o "$_tmp" || {
  rm -f -- "$_tmp"
  printf 'ERR: failed to download %s/install.sh\n' "$_base" >&2
  exit 1
}
# exec replaces this shell (no EXIT trap); ISO /tmp is tmpfs.
exec bash "$_tmp" "$@"
