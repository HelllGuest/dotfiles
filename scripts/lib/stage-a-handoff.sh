#!/usr/bin/env bash
# stage-a-handoff.sh — run canonical HelllGuest/t14s-arch-install Stage A
#
# Sourced by thin curl-able wrappers (arch-install{,-t14s,-p15}.sh).
# Prefer a local checkout; else download install.sh (libs via T14S_BASE_URL).
#
# Env:
#   HW_PROFILE            forced profile (t14s|p15); empty → canonical DMI detect
#   T14S_INSTALL_SH       explicit path to install.sh
#   T14S_LOCAL            directory containing install.sh + lib/
#   T14S_REF              optional sha/branch/tag override (else resolve main once)
#   T14S_BASE_URL         raw base (skips ref resolve when set)
#   T14S_INSTALL_URL      full URL to install.sh
#   STAGE_A_DOTFILES_ROOT path to this dotfiles repo (sibling lookup)
#   STAGE_A_DRY_PRINT=1   print resolution only (tests); do not exec

# Resolve one commit for every raw.githubusercontent fetch (install + libs).
# Call only on the remote path — local checkouts must stay offline.
t14s_resolve_base_url() {
  if [[ -n ${T14S_BASE_URL:-} ]]; then
    printf '%s\n' "$T14S_BASE_URL"
    return 0
  fi
  local ref="${T14S_REF:-}"
  if [[ -z $ref ]]; then
    ref="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
      https://api.github.com/repos/HelllGuest/t14s-arch-install/commits/main 2>/dev/null || true)"
    ref="${ref//$'\n'/}"
    if [[ ! $ref =~ ^[0-9a-f]{40}$ ]]; then
      printf 'ERR: could not resolve t14s-arch-install main SHA (set T14S_REF or T14S_BASE_URL)\n' >&2
      return 1
    fi
    T14S_REF="$ref"
  fi
  printf 'https://raw.githubusercontent.com/HelllGuest/t14s-arch-install/%s\n' "$ref"
}

stage_a_handoff() {
  local profile="${1:-}"
  shift || true
  local base url tmp cand libdir

  if [[ -n $profile ]]; then
    export HW_PROFILE="$profile"
  fi

  # 1) Explicit file
  if [[ -n ${T14S_INSTALL_SH:-} && -f $T14S_INSTALL_SH ]]; then
    cand="$(cd "$(dirname "$T14S_INSTALL_SH")" && pwd)/install.sh"
    libdir="$(dirname "$cand")/lib"
    [[ -d $libdir ]] && export T14S_LIB_DIR="$libdir"
    if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
      printf 'local:%s\nHW_PROFILE=%s\nT14S_LIB_DIR=%s\n' \
        "$cand" "${HW_PROFILE:-}" "${T14S_LIB_DIR:-}"
      return 0
    fi
    printf '→ Stage A local: %s (HW_PROFILE=%s)\n' "$cand" "${HW_PROFILE:-auto}"
    # shellcheck disable=SC2093 # intentional: hand off process
    exec bash "$cand" "$@"
  fi

  # 2) Explicit dir, $HOME checkout, or sibling of this dotfiles tree
  for cand in \
    "${T14S_LOCAL:-}" \
    "${HOME:+$HOME/t14s-arch-install}" \
    "${STAGE_A_DOTFILES_ROOT:+$STAGE_A_DOTFILES_ROOT/../t14s-arch-install}"
  do
    [[ -n $cand && -f $cand/install.sh ]] || continue
    cand="$(cd "$cand" && pwd)"
    libdir="$cand/lib"
    [[ -d $libdir ]] && export T14S_LIB_DIR="$libdir"
    if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
      printf 'local:%s\nHW_PROFILE=%s\nT14S_LIB_DIR=%s\n' \
        "$cand/install.sh" "${HW_PROFILE:-}" "${T14S_LIB_DIR:-}"
      return 0
    fi
    printf '→ Stage A local: %s (HW_PROFILE=%s)\n' "$cand/install.sh" "${HW_PROFILE:-auto}"
    # shellcheck disable=SC2093 # intentional: hand off process; loop does not continue
    exec bash "$cand/install.sh" "$@"
  done

  # 3) Remote: resolve one SHA (or use T14S_BASE_URL / T14S_REF) then fetch
  base="$(t14s_resolve_base_url)" || exit 1
  url="${T14S_INSTALL_URL:-$base/install.sh}"
  export T14S_BASE_URL="$base"
  export T14S_REF="${T14S_REF:-}"

  if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
    printf 'fetch:%s\nHW_PROFILE=%s\nT14S_BASE_URL=%s\nT14S_REF=%s\n' \
      "$url" "${HW_PROFILE:-}" "$base" "${T14S_REF:-}"
    return 0
  fi

  printf '→ Stage A fetch: %s (HW_PROFILE=%s ref=%s)\n' \
    "$url" "${HW_PROFILE:-auto}" "${T14S_REF:-}"
  command -v curl >/dev/null 2>&1 || {
    printf 'ERR: curl required to fetch Stage A from %s\n' "$url" >&2
    exit 1
  }
  tmp="$(mktemp /tmp/t14s-stage-a.XXXXXX)"
  curl -fsSL "$url" -o "$tmp" || {
    rm -f -- "$tmp"
    printf 'ERR: failed to download %s\n' "$url" >&2
    exit 1
  }
  # exec replaces this shell (no EXIT trap); ISO /tmp is tmpfs — leave file.
  # shellcheck disable=SC2093
  exec bash "$tmp" "$@"
}
