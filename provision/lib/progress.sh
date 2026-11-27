# progress.sh — Unicode/ASCII percent bars for Stage B install + configure.
# shellcheck shell=bash

# ui_bar PCT [WIDTH] — UTF-8 █/░ ; C locale / non-UTF-8: #/- .
ui_bar() {
  local pct=${1:-0} w=${2:-10} filled empty i n bar=
  [[ $pct =~ ^[0-9]+$ ]] || pct=0
  [[ $w =~ ^[1-9][0-9]*$ ]] || w=10
  (( pct > 100 )) && pct=100
  n=$(( pct * w / 100 ))
  if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *UTF-8* ]]; then
    filled='█' empty='░'
  else
    filled='#' empty='-'
  fi
  for (( i = 0; i < w; i++ )); do
    if (( i < n )); then bar+="$filled"; else bar+="$empty"; fi
  done
  printf '[%s]' "$bar"
}

# progress_line CUR TOTAL LABEL — one TTY status line with bar (ANSI color on TTY unless NO_COLOR or TERM=dumb).
progress_line() {
  local cur=${1:-0} tot=${2:-1} label=${3:-} pct=0 bar c_bar="" c_cnt="" c_lbl="" c0=""
  [[ $cur =~ ^[0-9]+$ ]] || cur=0
  [[ $tot =~ ^[1-9][0-9]*$ ]] || tot=1
  (( cur > tot )) && cur=$tot
  pct=$(( cur * 100 / tot ))
  bar="$(ui_bar "$pct" 20)"
  if [[ -w /dev/tty ]] && {
    if [[ -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
      c_bar=$'\e[0m' c_cnt=$'\e[2m' c_lbl=$'\e[1m' c0=$'\e[0m'
    fi
    printf '%s%s%s %s%d/%d%s · %s%s%s\n' "$c_bar" "$bar" "$c0" "$c_cnt" "$cur" "$tot" "$c0" "$c_lbl" "$label" "$c0" >/dev/tty 2>/dev/null
  }; then
    return 0
  fi
  if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
    c_bar=$'\e[0m' c_cnt=$'\e[2m' c_lbl=$'\e[1m' c0=$'\e[0m'
  else
    c_bar="" c_cnt="" c_lbl="" c0=""
  fi
  printf '%s%s%s %s%d/%d%s · %s%s%s\n' "$c_bar" "$bar" "$c0" "$c_cnt" "$cur" "$tot" "$c0" "$c_lbl" "$label" "$c0" >&2
}

# progress_banner LABEL — box header for a long module (UTF-8 or ASCII; ANSI color on TTY unless NO_COLOR or TERM=dumb).
progress_banner() {
  local label=${1:-} top bot mid c_box="" c_ttl="" c0=""
  if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *UTF-8* ]]; then
    top='────────────────────────────────────────────────────────'
    bot=$top
    mid='│'
  else
    top='--------------------------------------------------------'
    bot=$top
    mid='|'
  fi
  if [[ -w /dev/tty ]] && {
    if [[ -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
      c_box=$'\e[2m' c_ttl=$'\e[1m' c0=$'\e[0m'
    fi
    {
      printf '\n%s%s%s\n' "$c_box" "$top" "$c0"
      printf '%s%s%s %s%s%s\n' "$c_box" "$mid" "$c0" "$c_ttl" "$label" "$c0"
      printf '%s%s%s\n\n' "$c_box" "$bot" "$c0"
    } >/dev/tty 2>/dev/null
  }; then
    return 0
  fi
  if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
    c_box=$'\e[2m' c_ttl=$'\e[1m' c0=$'\e[0m'
  else
    c_box="" c_ttl="" c0=""
  fi
  printf '\n%s%s%s\n' "$c_box" "$top" "$c0" >&2
  printf '%s%s%s %s%s%s\n' "$c_box" "$mid" "$c0" "$c_ttl" "$label" "$c0" >&2
  printf '%s%s%s\n\n' "$c_box" "$bot" "$c0" >&2
}
