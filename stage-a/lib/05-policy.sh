#!/usr/bin/env bash
# 05-policy.sh — shared Stage A / Stage B hardware and remote policy constants.
# Single source of truth for DMI machine-type regexes, ThinkPad charge window,
# and GitHub main SHA resolution. Sourced by stage-a/, provision/lib/, system/, tests/.
# shellcheck shell=bash

STAGE_A_REPO="${STAGE_A_REPO:-HelllGuest/dotfiles}"
STAGE_A_BRANCH="${STAGE_A_BRANCH:-main}"

# Word-bounded ERE patterns (case-insensitive) for supported ThinkPad SKUs.
STAGE_A_DMI_T14S_RE='(^|[[:space:]_/])21C[QR]([[:alnum:]_-]|$)'
STAGE_A_DMI_P15_GEN1_RE='(^|[[:space:]_/])20SU([[:alnum:]_-]|$)'
STAGE_A_DMI_P15_RE="ThinkPad[[:space:]]*P15|P15[[:space:]]+Gen|${STAGE_A_DMI_P15_GEN1_RE}"

# ThinkPad battery longevity charge window (overrideable via env).
CHARGE_START="${CHARGE_START:-70}"
CHARGE_END="${CHARGE_END:-80}"

dmi_matches_t14s() {
  printf '%s\n' "${1:-}" | grep -qiE "$STAGE_A_DMI_T14S_RE"
}

# Stage A auto-detect: P15 Gen 1 (20SU) only, so newer P15 gens fall through to generic.
dmi_matches_p15_gen1() {
  printf '%s\n' "${1:-}" | grep -qiE "$STAGE_A_DMI_P15_GEN1_RE"
}

dmi_matches_p15() {
  printf '%s\n' "${1:-}" | grep -qiE "$STAGE_A_DMI_P15_RE"
}

stage_a_validate_charge_window() {
  local s=${1:-$CHARGE_START} e=${2:-$CHARGE_END}
  [[ $s =~ ^[0-9]+$ && $e =~ ^[0-9]+$ ]] && (( s >= 0 && s <= 99 && e >= 1 && e <= 100 && s < e ))
}

# Resolve STAGE_A_BRANCH head on STAGE_A_REPO to a 40-hex commit SHA.
stage_a_resolve_main_sha() {
  if [[ ! $STAGE_A_REPO =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    printf 'ERR: invalid STAGE_A_REPO=%s\n' "$STAGE_A_REPO" >&2
    return 1
  fi
  if [[ ! $STAGE_A_BRANCH =~ ^[A-Za-z0-9._/-]+$ || $STAGE_A_BRANCH == *..* ]]; then
    printf 'ERR: invalid STAGE_A_BRANCH=%s\n' "$STAGE_A_BRANCH" >&2
    return 1
  fi
  local sha
  sha="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/${STAGE_A_REPO}/commits/${STAGE_A_BRANCH}" 2>/dev/null || true)"
  sha="${sha//$'\n'/}"
  if [[ ! $sha =~ ^[0-9a-f]{40}$ ]]; then
    printf 'ERR: could not resolve %s %s SHA (set STAGE_A_REF / T14S_REF or STAGE_A_BASE_URL)\n' \
      "$STAGE_A_REPO" "$STAGE_A_BRANCH" >&2
    return 1
  fi
  printf '%s\n' "$sha"
}
