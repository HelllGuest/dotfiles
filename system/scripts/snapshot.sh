#!/usr/bin/env bash
# snapshot.sh — Snapper root snapshot + rollback + sbctl verify helper.
#
# Usage: bash system/scripts/snapshot.sh <create [DESC]|list|status|rollback [ID] [--apply]>
#
# Safety:
#   - status / list are read-only and never hang on polkit (uses sudo -n when non-root).
#   - rollback previews commands by default; pass --apply to execute `snapper rollback`.
#
# Env (optional / tests):
#   SNAPPER_CONFIG   snapper config name (default: root)
set -euo pipefail

CFG="${SNAPPER_CONFIG:-root}"

usage() {
  cat <<'EOF'
Usage: bash system/scripts/snapshot.sh <command> [args]

Commands:
  create [DESC]           Create a Snapper snapshot (default: pre-upgrade) + verify sbctl
  list                    List Snapper snapshots for config (default: root)
  status                  Read-only Snapper + Secure Boot (sbctl) health summary
  rollback [ID] [--apply] Preview (default) or run `snapper rollback <ID>`
EOF
}

need_snapper() {
  command -v snapper >/dev/null 2>&1 || {
    echo "error: snapper not installed (sudo pacman -S snapper)" >&2
    exit 1
  }
}

run_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_root_ro() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  elif sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    return 126
  fi
}

check_sbctl() {
  command -v sbctl >/dev/null 2>&1 || {
    echo "○ sbctl not installed — skipping Secure Boot check"
    return 0
  }
  local st
  if st="$(run_root_ro sbctl status 2>/dev/null)"; then
    printf '%s\n' "$st"
    if grep -qiE 'Installed:.*(✓|yes|true|installed)' <<<"$st"; then
      run_root_ro sbctl verify || echo "⚠ sbctl verify reported unsigned files"
    fi
  else
    echo "○ sbctl status skipped (requires sudo -n / root)"
  fi
}

cmd_create() {
  need_snapper
  local desc="${*:-manual pre-upgrade ($(date +%Y-%m-%d_%H%M))}"
  local id
  id="$(run_root snapper -c "$CFG" create --cleanup-algorithm number --print-number --description "$desc")"
  echo "✓ created snapper snapshot #$id ($CFG): $desc"
  check_sbctl
}

cmd_list() {
  need_snapper
  if ! run_root_ro snapper -c "$CFG" list; then
    echo "○ snapper list requires root (run: sudo snapper -c $CFG list)" >&2
    return 1
  fi
}

cmd_status() {
  if command -v snapper >/dev/null 2>&1; then
    if run_root_ro snapper -c "$CFG" list --columns number,date,description 2>/dev/null | tail -n 10; then
      :
    else
      echo "○ snapper ($CFG): unreadable without root/sudo -n"
    fi
  else
    echo "○ snapper not installed"
  fi
  check_sbctl
}

cmd_rollback() {
  need_snapper
  local id="" apply=0
  while (($#)); do
    case $1 in
      --apply) apply=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "error: unknown rollback option '$1'" >&2; exit 2 ;;
      *)
        if [[ -z $id ]]; then
          id=$1
        else
          echo "error: unexpected argument '$1'" >&2; exit 2
        fi
        ;;
    esac
    shift
  done

  if [[ -z $id ]]; then
    echo "error: rollback requires a snapshot ID (run: bash system/scripts/snapshot.sh list)" >&2
    exit 2
  fi
  if [[ ! $id =~ ^[0-9]+$ ]]; then
    echo "error: snapshot ID must be numeric (got: $id)" >&2
    exit 2
  fi

  if (( ! apply )); then
    echo "[dry-run] sudo snapper -c $CFG rollback $id"
    echo "Pass --apply to execute rollback, then reboot into the rolled-back snapshot."
    return 0
  fi

  run_root snapper -c "$CFG" rollback "$id"
  echo "✓ rolled back $CFG to snapshot #$id — reboot required to boot into it"
}

case ${1:-} in
  create) shift; cmd_create "$@" ;;
  list) shift; cmd_list "$@" ;;
  status) shift; cmd_status "$@" ;;
  rollback) shift; cmd_rollback "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
