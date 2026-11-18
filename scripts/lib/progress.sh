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
    if (( i < n )); then bar+=$filled; else bar+=$empty; fi
  done
  printf '[%s]' "$bar"
}

# progress_line CUR TOTAL LABEL — one TTY status line with bar.
progress_line() {
  local cur=${1:-0} tot=${2:-1} label=${3:-} pct=0
  [[ $cur =~ ^[0-9]+$ ]] || cur=0
  [[ $tot =~ ^[1-9][0-9]*$ ]] || tot=1
  (( cur > tot )) && cur=$tot
  pct=$(( cur * 100 / tot ))
  if [[ -t 2 || -w /dev/tty ]]; then
    printf '%s %d/%d · %s\n' "$(ui_bar "$pct" 20)" "$cur" "$tot" "$label" >/dev/tty 2>/dev/null \
      || printf '%s %d/%d · %s\n' "$(ui_bar "$pct" 20)" "$cur" "$tot" "$label" >&2
  else
    printf '%s %d/%d · %s\n' "$(ui_bar "$pct" 20)" "$cur" "$tot" "$label" >&2
  fi
}

# progress_banner LABEL — box header for a long module (UTF-8 or ASCII).
progress_banner() {
  local label=${1:-} top bot mid
  if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} == *UTF-8* ]]; then
    top='────────────────────────────────────────────────────────'
    bot=$top
    mid='│'
  else
    top='--------------------------------------------------------'
    bot=$top
    mid='|'
  fi
  {
    printf '\n%s\n' "$top"
    printf '%s %s\n' "$mid" "$label"
    printf '%s\n\n' "$bot"
  } >/dev/tty 2>/dev/null || {
    printf '\n%s\n' "$top" >&2
    printf '%s %s\n' "$mid" "$label" >&2
    printf '%s\n\n' "$bot" >&2
  }
}
