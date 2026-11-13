#!/usr/bin/env bash
# Identity validators for arch-install*.sh.
# Canonical copy: tests source this file. Installers embed the same function
# bodies so each script stays a single curl-able file (no runtime source).
#
# Test fixtures only when T14S_IDENTITY_OVERRIDES=1 (or IDENTITY_OVERRIDES=1):
#   LOCALE_FILES  — space-separated locale list paths (replaces SUPPORTED/locale.gen)
#   KEYMAP_DIR    — keymap tree for find / fixtures
#
# Note: public t14s-arch-install (HelllGuest/t14s-arch-install) keeps its own
# copies (FQDN hostnames, + in keymaps, T14S_IDENTITY_OVERRIDES only). That
# repo is canonical Stage A. Do not assume byte-identical parity; do not
# "sync" validators the wrong way.

valid_hostname() {
  local h="$1"
  # RFC 1123: labels start/end alnum; hyphen only mid; 1–63 chars total.
  [[ $h =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

valid_username() {
  local u="$1"
  [[ $u =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
  (( ${#u} <= 32 )) || return 1
  # Reject names already in passwd or group (root/bin/nobody/wheel on the ISO).
  id "$u" &>/dev/null && return 1
  getent group "$u" >/dev/null 2>&1 && return 1
  return 0
}

valid_timezone() {
  local tz="$1" f magic
  [[ $tz != *..* ]] || return 1
  [[ $tz =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)*$ ]] || return 1
  case $tz in
    Factory|leapseconds|posixrules|localtime|iso3166.tab|zone.tab|zonenow.tab|tzdata.zi) return 1 ;;
  esac
  f="/usr/share/zoneinfo/$tz"
  [[ -f $f ]] || return 1
  # Zone files start with TZif; reject leapseconds / plain text tables.
  magic="$(head -c4 "$f" 2>/dev/null || true)"
  [[ $magic == TZif ]]
}

valid_locale() {
  local loc="$1" f line name
  local -a files=()
  [[ -n $loc ]] || return 1
  if [[ ${T14S_IDENTITY_OVERRIDES:-${IDENTITY_OVERRIDES:-0}} == 1 && -n ${LOCALE_FILES:-} ]]; then
    # shellcheck disable=SC2206
    files=(${LOCALE_FILES})
  else
    files=(/usr/share/i18n/SUPPORTED /etc/locale.gen)
  fi
  for f in "${files[@]}"; do
    [[ -r $f ]] || continue
    while read -r line || [[ -n $line ]]; do
      [[ $line =~ ^[[:space:]]*#?([A-Za-z0-9_.@-]+)[[:space:]] ]] || continue
      name="${BASH_REMATCH[1]}"
      [[ $name == "$loc" ]] && return 0
    done <"$f"
  done
  return 1
}

valid_keymap() {
  local km="$1" root=/usr/share/kbd/keymaps
  # Literal name only — never pass glob/regex metacharacters to find/grep.
  [[ $km =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  if [[ ${T14S_IDENTITY_OVERRIDES:-${IDENTITY_OVERRIDES:-0}} == 1 && -n ${KEYMAP_DIR:-} ]]; then
    root="$KEYMAP_DIR"
  fi
  if command -v localectl >/dev/null 2>&1; then
    localectl list-keymaps 2>/dev/null | grep -qxF -- "$km" && return 0
    # Not listed: still accept an exact on-disk map. Charset is safe.
  fi
  # Directory check only for find fallback (Ubuntu CI often has no kbd keymaps tree).
  [[ -d $root ]] || return 1
  find "$root" -type f \
    \( -name "${km}.map" -o -name "${km}.map.gz" \
       -o -name "${km}.kmap" -o -name "${km}.kmap.gz" \) \
    2>/dev/null | grep -q .
}
