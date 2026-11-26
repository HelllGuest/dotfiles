#!/usr/bin/env bash
# configure.sh — Stage B post-boot configurator (dialog / whiptail / zenity / plain).
# Live: firewalld, ollama (P15), profile, labs, AI stack, Gruvbox rice.
#
# Usage: bash provision/scripts/configure.sh [--tui|--gui|--plain]
# Interactive (TTY/GUI): archdi-style main menu loop (Modules / Profile / Quit).
# One-shot: CONFIGURE_ONCE=1 (./install.sh) or plain UI with no stdin TTY.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=../lib/dmi.sh
source "$REPO_ROOT/provision/lib/dmi.sh"
# shellcheck source=../lib/progress.sh
source "$REPO_ROOT/provision/lib/progress.sh"
# shellcheck source=../lib/ui-menu.sh
source "$REPO_ROOT/provision/lib/ui-menu.sh"

while (($#)); do
  case $1 in
    --gui|--zenity) CONFIGURE_UI=gui ;;
    --tui) CONFIGURE_UI=tui ;;
    --plain) CONFIGURE_UI=plain ;;
    -h|--help)
      echo "usage: configure.sh [--tui|--gui|--plain]"
      echo "  env: CONFIGURE_UI=plain|tui|dialog|whiptail|gui|zenity  CONFIGURE_ONCE=1"
      exit 0
      ;;
    *)
      echo "configure.sh: unknown option '$1' (use --tui|--gui|--plain|-h)" >&2
      exit 2
      ;;
  esac
  shift
done

DEFAULT_MENU_ITEM="modules"
ui_init "${CONFIGURE_UI:-}" "Dotfiles configure · Stage B" "CONFIGURE_UI" || exit 1
trap ui_theme_cleanup EXIT
ui_theme_init

is_p15=0
is_thinkpad_p15 && is_p15=1

# Default SETUP_OLLAMA on for P15 (20SU); off elsewhere (T14s never wants host ollama).
OLLAMA_STATE=off
if [[ $is_p15 -eq 1 ]]; then
  OLLAMA_STATE=on
fi

selected() { printf '%s\n' "$OPTS" | grep -qx "$1"; }

run_mod() {
  local name=$1
  CONFIGURE_STEP=$((CONFIGURE_STEP + 1))
  progress_line "$CONFIGURE_STEP" "$CONFIGURE_STEPS" "$name"
  progress_banner "$name"
  shift
  # Explicit exit: menu uses `if run_modules_batch` / `||`, which would
  # otherwise swallow a failing module under set -e.
  if ! "$@"; then
    ui_msg "Module failed: $name"
    exit 1
  fi
}

# Checklist → run selected modules (fail-fast). Returns 1 if checklist aborted.
run_modules_batch() {
  local OPTS
  OPTS="$(ui_checklist "Stage B modules" \
    SETUP_FIREWALLD "firewalld drop + libvirt + lab-malware zones" on \
    APPLY_PROFILE "Re-run machine profile (detect / hostname)" off \
    SETUP_OLLAMA "P15: ollama-cuda + qwen models (localhost)" "$OLLAMA_STATE" \
    SETUP_LABS "Labs lab-triage/re/android/web (+ capture)" off \
    SETUP_DETONATE "Detonation VMs + INetSim/PolarProxy" off \
    SETUP_AI "AI MCP / Headroom / Continue / Ponytail" off \
    SETUP_RICE "Terminal/CLI rice (Gruvbox/SecOps) + notify" off \
    SETUP_THEMES "GNOME theme packs manager (install/uninstall)" off
  )" || return 1

  CONFIGURE_STEP=0
  CONFIGURE_STEPS=0
  selected SETUP_FIREWALLD && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected APPLY_PROFILE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_OLLAMA && (( is_p15 )) && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_LABS && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_DETONATE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_AI && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_RICE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  selected SETUP_THEMES && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
  (( CONFIGURE_STEPS < 1 )) && CONFIGURE_STEPS=1

  if selected SETUP_FIREWALLD; then
    run_mod firewalld bash "$REPO_ROOT/security/scripts/firewalld-lab-zones.sh"
  fi
  if selected APPLY_PROFILE; then
    run_mod profile bash "$REPO_ROOT/provision/scripts/apply-profile.sh"
  fi
  if selected SETUP_OLLAMA; then
    if [[ $is_p15 -eq 1 ]]; then
      run_mod ollama bash "$REPO_ROOT/ai/scripts/ollama-setup.sh"
    else
      ui_msg "SETUP_OLLAMA skipped: not a P15 (20SU) host."
    fi
  fi
  if selected SETUP_LABS; then
    run_mod labs bash "$REPO_ROOT/labs/scripts/labs-setup.sh"
  fi
  if selected SETUP_DETONATE; then
    run_mod detonate bash "$REPO_ROOT/labs/scripts/lab-detonate.sh" setup
  fi
  if selected SETUP_AI; then
    run_mod ai bash "$REPO_ROOT/ai/scripts/ai-stack-setup.sh"
  fi
  if selected SETUP_RICE; then
    run_mod rice bash "$REPO_ROOT/desktop/scripts/rice-setup.sh"
  fi
  if selected SETUP_THEMES; then
    run_mod themes env THEME_UI="$UI" bash "$REPO_ROOT/desktop/scripts/theme-packs.sh"
  fi
  return 0
}

run_profile_only() {
  CONFIGURE_STEP=0
  CONFIGURE_STEPS=1
  run_mod profile bash "$REPO_ROOT/provision/scripts/apply-profile.sh"
  ui_msg "Profile finished."
}

configure_once() {
  case ${CONFIGURE_ONCE:-0} in
    1|Y|y|yes|on) return 0 ;;
  esac
  # Headless plain (CI / serial with no TTY): one checklist then exit.
  [[ $UI == plain && ! -t 0 ]] && return 0
  return 1
}

if configure_once; then
  run_modules_batch || { echo "configure: aborted"; exit 1; }
  echo "✓ configure.sh finished"
  exit 0
fi

# Interactive loop (archdi-style): return here after each action until Quit.
while true; do
  choice="$(ui_menu "Stage B main menu" \
    modules "Run modules (checklist)" \
    profile "Apply machine profile" \
    quit "Quit")" || choice=quit
  # shellcheck disable=SC2034 # consumed by ui_menu in lib/ui-menu.sh
  DEFAULT_MENU_ITEM=$choice
  case $choice in
    modules)
      # Checklist Cancel → back to menu. Module failure → exit 1 (run_mod).
      # CONFIGURE_STEP is how many modules ran.
      if run_modules_batch; then
        if (( CONFIGURE_STEP > 0 )); then
          ui_msg "Selected modules finished."
        else
          ui_msg "No modules ran."
        fi
      fi
      ;;
    profile)
      run_profile_only
      ;;
    quit|*)
      echo "✓ configure.sh finished"
      exit 0
      ;;
  esac
done
