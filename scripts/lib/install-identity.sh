#!/usr/bin/env bash
# Identity validators for arch-install*.sh.
# Canonical copy: tests source this file. Installers embed the same function
# bodies so each script stays a single curl-able file (no runtime source).
#
# Optional overrides (honoured wherever set; tests use them, ISO normally does not):
#   LOCALE_FILES  — space-separated locale list paths (replaces SUPPORTED/locale.gen)
#   KEYMAP_DIR    — keymap tree for find / fixtures (skips localectl when set)

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
  if [[ -n ${LOCALE_FILES:-} ]]; then
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
  local km="$1" root
  # Literal name only — never pass glob metacharacters to find -name.
  [[ $km =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  # Test override: fixture dir wins (CI without console keymaps).
  if [[ -n ${KEYMAP_DIR:-} ]]; then
    root="$KEYMAP_DIR"
    [[ -d $root ]] || return 1
    find "$root" -type f \
      \( -name "${km}.map" -o -name "${km}.map.gz" \
         -o -name "${km}.kmap" -o -name "${km}.kmap.gz" \) \
      2>/dev/null | grep -q .
    return $?
  fi
  if command -v localectl >/dev/null 2>&1; then
    # localectl present: its answer is final (no find fallthrough).
    localectl list-keymaps 2>/dev/null | grep -qxF -- "$km"
    return $?
  fi
  # Fallback only when localectl is missing (non-ISO hosts).
  root=/usr/share/kbd/keymaps
  [[ -d $root ]] || return 1
  find "$root" -type f \
    \( -name "${km}.map" -o -name "${km}.map.gz" \
       -o -name "${km}.kmap" -o -name "${km}.kmap.gz" \) \
    2>/dev/null | grep -q .
}
