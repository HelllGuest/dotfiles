#!/usr/bin/env bash
# configure.sh — Stage B post-boot configurator (dialog → whiptail → plain).
# Live: firewalld, ollama (P15), profile, labs, AI stack, Gruvbox rice.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

# CONFIGURE_UI=plain|dialog|whiptail — force backend (VM / CI: plain).
UI=${CONFIGURE_UI:-plain}
if [[ -z ${CONFIGURE_UI:-} ]]; then
  if command -v dialog >/dev/null 2>&1; then
    UI=dialog
  elif command -v whiptail >/dev/null 2>&1; then
    UI=whiptail
  fi
fi

is_p15=0
is_thinkpad_p15 && is_p15=1

checklist() {
  local title=$1; shift
  case $UI in
    dialog)
      dialog --stdout --separate-output --checklist "$title" 20 72 12 "$@" || return 1
      ;;
    whiptail)
      whiptail --separate-output --checklist "$title" 20 72 12 "$@" || return 1
      ;;
    *)
      echo "$title" >&2
      local tag item state out=()
      while (($#)); do
        tag=$1; item=$2; state=$3; shift 3
        if [[ $state == on || $state == ON ]]; then
          printf '  [x] %s — %s\n' "$tag" "$item" >&2
          out+=("$tag")
        else
          printf '  [ ] %s — %s\n' "$tag" "$item" >&2
        fi
      done
      printf 'Enter tags to enable (space-separated, empty=defaults on):\n' >&2
      local ans
      read -r ans || true
      if [[ -n $ans ]]; then
        # shellcheck disable=SC2206
        out=($ans)
      fi
      printf '%s\n' "${out[@]}"
      ;;
  esac
}

msg() {
  case $UI in
    dialog) dialog --msgbox "$1" 12 60 || true ;;
    whiptail) whiptail --msgbox "$1" 12 60 || true ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Default SETUP_OLLAMA on for P15 (20SU); off elsewhere (T14s never wants host ollama).
OLLAMA_STATE=off
if [[ $is_p15 -eq 1 ]]; then
  OLLAMA_STATE=on
fi

OPTS="$(checklist "Stage B modules" \
  MIGRATE_FIREWALLD "firewalld migrate (drop + libvirt + lab-malware)" on \
  APPLY_PROFILE "Re-run machine profile (detect / hostname)" off \
  SETUP_OLLAMA "P15: ollama-cuda + qwen models (localhost)" "$OLLAMA_STATE" \
  SETUP_LABS "Labs lab-triage/re/android/web (+ capture image)" off \
  SETUP_DETONATE "Detonation VMs + INetSim/PolarProxy on virbr-malware" off \
  SETUP_AI "AI MCP / Headroom / Continue / Ponytail" off \
  SETUP_RICE "Gruvbox rice + notifications + launchers" off
)" || { echo "configure: aborted"; exit 1; }

run_mod() {
  local name=$1
  echo "=== $name ==="
  shift
  "$@"
}

selected() { echo "$OPTS" | grep -qx "$1"; }

# Fail-fast: module errors propagate (no || true swallow).
if selected MIGRATE_FIREWALLD; then
  run_mod firewalld bash "$REPO_ROOT/scripts/firewalld-migrate.sh"
fi

if selected APPLY_PROFILE; then
  run_mod profile bash "$REPO_ROOT/scripts/apply-profile.sh"
fi

if selected SETUP_OLLAMA; then
  if [[ $is_p15 -eq 1 ]]; then
    run_mod ollama bash "$REPO_ROOT/scripts/ollama-setup.sh"
  else
    msg "SETUP_OLLAMA skipped: not a P15 (20SU) host."
  fi
fi

if selected SETUP_LABS; then
  run_mod labs bash "$REPO_ROOT/scripts/labs-setup.sh"
fi

if selected SETUP_DETONATE; then
  run_mod detonate bash "$REPO_ROOT/scripts/lab-detonate.sh" setup
fi

if selected SETUP_AI; then
  run_mod ai bash "$REPO_ROOT/scripts/ai-stack-setup.sh"
fi

if selected SETUP_RICE; then
  run_mod rice bash "$REPO_ROOT/scripts/rice-setup.sh"
fi

echo "✓ configure.sh finished"
