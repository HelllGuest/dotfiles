#!/usr/bin/env bash
# stage-a-handoff.sh — run canonical Stage A installer (stage-a/ in HelllGuest/dotfiles)
#
# Sourced by thin curl-able wrappers (arch-install{,-t14s,-p15}.sh).
# Prefer the in-repo stage-a/ checkout; else download from GitHub (libs via STAGE_A_BASE_URL / T14S_BASE_URL).
#
# Env (STAGE_A_* preferred; legacy T14S_* aliases honored):
#   HW_PROFILE                    forced profile (t14s|p15); empty → canonical DMI detect
#   STAGE_A_INSTALL_SH / T14S_INSTALL_SH   explicit path to install.sh
#   STAGE_A_LOCAL / T14S_LOCAL             directory containing install.sh + lib/
#   STAGE_A_REF / T14S_REF                 optional sha/branch/tag override (else resolve main once)
#   STAGE_A_BASE_URL / T14S_BASE_URL       raw base (skips ref resolve when set)
#   STAGE_A_INSTALL_URL / T14S_INSTALL_URL full URL to install.sh
#   STAGE_A_DOTFILES_ROOT                  path to this dotfiles repo (in-repo + sibling lookup)
#   STAGE_A_DRY_PRINT=1                    print resolution only (tests); do not exec

# Source canonical SHA/policy helper when in a local monorepo checkout.
_handoff_policy=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  _handoff_policy="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/stage-a/lib/05-policy.sh"
fi
if [[ -n $_handoff_policy && -f $_handoff_policy ]]; then
  # shellcheck source=../../stage-a/lib/05-policy.sh
  source "$_handoff_policy"
fi
unset -v _handoff_policy

# Resolve one commit for every raw.githubusercontent fetch (install + libs).
# Call only on the remote path — local checkouts must stay offline.
t14s_resolve_base_url() {
  local base_override="${STAGE_A_BASE_URL:-${T14S_BASE_URL:-}}"
  if [[ -n $base_override ]]; then
    printf '%s\n' "$base_override"
    return 0
  fi
  local repo="${STAGE_A_REPO:-HelllGuest/dotfiles}"
  local branch="${STAGE_A_BRANCH:-main}"
  if [[ ! $repo =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    printf 'ERR: invalid STAGE_A_REPO=%s\n' "$repo" >&2
    return 1
  fi
  if [[ ! $branch =~ ^[A-Za-z0-9._/-]+$ || $branch == *..* ]]; then
    printf 'ERR: invalid STAGE_A_BRANCH=%s\n' "$branch" >&2
    return 1
  fi
  local ref="${STAGE_A_REF:-${T14S_REF:-}}"
  if [[ -z $ref ]]; then
    if declare -F stage_a_resolve_main_sha >/dev/null 2>&1; then
      ref="$(STAGE_A_REPO="$repo" STAGE_A_BRANCH="$branch" stage_a_resolve_main_sha)" || return 1
    else
      ref="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
        "https://api.github.com/repos/${repo}/commits/${branch}" 2>/dev/null || true)"
      ref="${ref//$'\n'/}"
      if [[ ! $ref =~ ^[0-9a-f]{40}$ ]]; then
        printf 'ERR: could not resolve %s %s SHA (set STAGE_A_REF / T14S_REF or STAGE_A_BASE_URL)\n' \
          "$repo" "$branch" >&2
        return 1
      fi
    fi
    T14S_REF="$ref"
    STAGE_A_REF="$ref"
  fi
  printf 'https://raw.githubusercontent.com/%s/%s/stage-a\n' "$repo" "$ref"
}

stage_a_handoff() {
  local profile="${1:-}"
  shift || true
  local base url tmp cand libdir
  local explicit_sh="${STAGE_A_INSTALL_SH:-${T14S_INSTALL_SH:-}}"
  local explicit_dir="${STAGE_A_LOCAL:-${T14S_LOCAL:-}}"

  if [[ -n $profile ]]; then
    export HW_PROFILE="$profile"
  fi

  # 1) Explicit file
  if [[ -n $explicit_sh && -f $explicit_sh ]]; then
    cand="$(cd "$(dirname "$explicit_sh")" && pwd)/install.sh"
    libdir="$(dirname "$cand")/lib"
    if [[ -d $libdir ]]; then
      export STAGE_A_LIB_DIR="$libdir" T14S_LIB_DIR="$libdir"
    fi
    if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
      printf 'local:%s\nHW_PROFILE=%s\nT14S_LIB_DIR=%s\n' \
        "$cand" "${HW_PROFILE:-}" "${T14S_LIB_DIR:-}"
      return 0
    fi
    printf '→ Stage A local: %s (HW_PROFILE=%s)\n' "$cand" "${HW_PROFILE:-auto}"
    # shellcheck disable=SC2093 # intentional: hand off process
    exec bash "$cand" "$@"
  fi

  # 2) Explicit dir, in-repo stage-a/, $HOME checkout, or sibling (skip shim dir without lib/)
  for cand in \
    "$explicit_dir" \
    "${STAGE_A_DOTFILES_ROOT:+$STAGE_A_DOTFILES_ROOT/stage-a}" \
    "${HOME:+$HOME/stage-a}" \
    "${HOME:+$HOME/t14s-arch-install}" \
    "${STAGE_A_DOTFILES_ROOT:+$STAGE_A_DOTFILES_ROOT/../stage-a}" \
    "${STAGE_A_DOTFILES_ROOT:+$STAGE_A_DOTFILES_ROOT/../t14s-arch-install}"
  do
    [[ -n $cand && -f $cand/install.sh && -d $cand/lib ]] || continue
    cand="$(cd "$cand" && pwd)"
    libdir="$cand/lib"
    export STAGE_A_LIB_DIR="$libdir" T14S_LIB_DIR="$libdir"
    if [[ ${STAGE_A_DRY_PRINT:-0} == 1 ]]; then
      printf 'local:%s\nHW_PROFILE=%s\nT14S_LIB_DIR=%s\n' \
        "$cand/install.sh" "${HW_PROFILE:-}" "${T14S_LIB_DIR:-}"
      return 0
    fi
    printf '→ Stage A local: %s (HW_PROFILE=%s)\n' "$cand/install.sh" "${HW_PROFILE:-auto}"
    # shellcheck disable=SC2093 # intentional: hand off process; loop does not continue
    exec bash "$cand/install.sh" "$@"
  done

  # 3) Remote: resolve one SHA (or use STAGE_A_BASE_URL / T14S_BASE_URL / *_REF) then fetch
  base="$(t14s_resolve_base_url)" || exit 1
  url="${STAGE_A_INSTALL_URL:-${T14S_INSTALL_URL:-$base/install.sh}}"
  local _resolved_ref="${STAGE_A_REF:-${T14S_REF:-}}"
  export STAGE_A_BASE_URL="$base" T14S_BASE_URL="$base"
  export STAGE_A_REF="$_resolved_ref" T14S_REF="$_resolved_ref"

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
