#!/usr/bin/env bash
# configure.sh — Stage B post-boot configurator (dialog → whiptail → plain).
# Live: firewalld, ollama (P15), profile, labs, AI stack, Gruvbox rice.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

UI=plain
if command -v dialog >/dev/null 2>&1; then
  UI=dialog
elif command -v whiptail >/dev/null 2>&1; then
  UI=whiptail
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

OLLAMA_STATE=off

OPTS="$(checklist "Stage B modules" \
  MIGRATE_FIREWALLD "UFW → firewalld (drop + libvirt + virbr-malware)" on \
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

echo "$OPTS" | grep -qx MIGRATE_FIREWALLD \
  && run_mod firewalld bash "$REPO_ROOT/scripts/firewalld-migrate.sh" || true

echo "$OPTS" | grep -qx APPLY_PROFILE \
  && run_mod profile bash "$REPO_ROOT/scripts/apply-profile.sh" || true

if echo "$OPTS" | grep -qx SETUP_OLLAMA; then
  if [[ $is_p15 -eq 1 ]]; then
    run_mod ollama bash "$REPO_ROOT/scripts/ollama-setup.sh"
  else
    msg "SETUP_OLLAMA skipped: not a P15 (20SU) host."
  fi
fi

echo "$OPTS" | grep -qx SETUP_LABS \
  && run_mod labs bash "$REPO_ROOT/scripts/labs-setup.sh" || true

echo "$OPTS" | grep -qx SETUP_DETONATE \
  && run_mod detonate bash "$REPO_ROOT/scripts/lab-detonate.sh" setup || true

echo "$OPTS" | grep -qx SETUP_AI \
  && run_mod ai bash "$REPO_ROOT/scripts/ai-stack-setup.sh" || true

echo "$OPTS" | grep -qx SETUP_RICE \
  && run_mod rice bash "$REPO_ROOT/scripts/rice-setup.sh" || true

echo "✓ configure.sh finished"
