#!/usr/bin/env bash
# configure.sh — Stage B post-boot configurator (dialog → whiptail → plain).
# Live: firewalld, ollama (P15), profile, labs, AI stack, Gruvbox rice.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"
# shellcheck source=lib/progress.sh
source "$REPO_ROOT/scripts/lib/progress.sh"

APP_TITLE="Dotfiles configure · Stage B"
DIALOG_RC_DIR=""

# CONFIGURE_UI=plain|dialog|whiptail — force backend (VM / CI: plain).
UI=${CONFIGURE_UI:-plain}
if [[ -z ${CONFIGURE_UI:-} ]]; then
  if command -v dialog >/dev/null 2>&1; then
    UI=dialog
  elif command -v whiptail >/dev/null 2>&1; then
    UI=whiptail
  fi
fi

# Minimal Stage A–matching chrome (8-colour console safe). Cleanup on EXIT.
write_configure_theme() {
  if [[ $UI == dialog ]]; then
    DIALOG_RC_DIR="$(mktemp -d /tmp/dotfiles-dialogrc.XXXXXX)"
    cat >"$DIALOG_RC_DIR/dialogrc" <<'EOF'
# Dotfiles configure theme (Stage A palette)
use_shadow = ON
use_colors = ON
screen_color = (CYAN,BLUE,ON)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (WHITE,BLACK,OFF)
title_color = (YELLOW,BLACK,ON)
border_color = (CYAN,BLACK,ON)
border2_color = (BLUE,BLACK,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (YELLOW,BLUE,ON)
button_key_inactive_color = (YELLOW,BLACK,ON)
button_label_active_color = (WHITE,BLUE,ON)
button_label_inactive_color = (WHITE,BLACK,OFF)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (YELLOW,BLACK,ON)
tag_selected_color = (WHITE,BLUE,ON)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (WHITE,BLUE,ON)
gauge_color = (CYAN,BLUE,ON)
EOF
    export DIALOGRC="$DIALOG_RC_DIR/dialogrc"
  elif [[ $UI == whiptail ]]; then
    export NEWT_COLORS='
root=white,blue
roottext=brightcyan,blue
border=brightcyan,black
window=lightgray,black
shadow=black,black
title=yellow,black
button=black,lightgray
actbutton=white,blue
checkbox=lightgray,black
actcheckbox=white,blue
listbox=lightgray,black
actlistbox=white,blue
emptyscale=,black
fullscale=,cyan
'
  fi
}

cleanup_configure_theme() {
  [[ -n ${DIALOG_RC_DIR:-} && -d $DIALOG_RC_DIR ]] && rm -rf -- "$DIALOG_RC_DIR"
  DIALOG_RC_DIR=""
}
trap cleanup_configure_theme EXIT
write_configure_theme

is_p15=0
is_thinkpad_p15 && is_p15=1

checklist() {
  local title=$1; shift
  case $UI in
    dialog)
      dialog --colors --backtitle "$APP_TITLE" --stdout --separate-output \
        --checklist "$title" 20 72 12 "$@" || return 1
      ;;
    whiptail)
      whiptail --backtitle "$APP_TITLE" --separate-output \
        --checklist "$title" 20 72 12 "$@" || return 1
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
    dialog) dialog --colors --backtitle "$APP_TITLE" --msgbox "$1" 12 60 || true ;;
    whiptail) whiptail --backtitle "$APP_TITLE" --msgbox "$1" 12 60 || true ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Default SETUP_OLLAMA on for P15 (20SU); off elsewhere (T14s never wants host ollama).
OLLAMA_STATE=off
if [[ $is_p15 -eq 1 ]]; then
  OLLAMA_STATE=on
fi

OPTS="$(checklist "Stage B modules" \
  SETUP_FIREWALLD "firewalld lab zones (drop + libvirt + lab-malware)" on \
  APPLY_PROFILE "Re-run machine profile (detect / hostname)" off \
  SETUP_OLLAMA "P15: ollama-cuda + qwen models (localhost)" "$OLLAMA_STATE" \
  SETUP_LABS "Labs lab-triage/re/android/web (+ capture image)" off \
  SETUP_DETONATE "Detonation VMs + INetSim/PolarProxy on virbr-malware" off \
  SETUP_AI "AI MCP / Headroom / Continue / Ponytail" off \
  SETUP_RICE "Gruvbox rice + notifications + launchers" off
)" || { echo "configure: aborted"; exit 1; }

selected() { echo "$OPTS" | grep -qx "$1"; }

# Count only modules that will actually run (OLLAMA skipped on non-P15).
CONFIGURE_STEP=0
CONFIGURE_STEPS=0
selected SETUP_FIREWALLD && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected APPLY_PROFILE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected SETUP_OLLAMA && (( is_p15 )) && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected SETUP_LABS && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected SETUP_DETONATE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected SETUP_AI && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
selected SETUP_RICE && CONFIGURE_STEPS=$((CONFIGURE_STEPS + 1))
(( CONFIGURE_STEPS < 1 )) && CONFIGURE_STEPS=1

run_mod() {
  local name=$1
  CONFIGURE_STEP=$((CONFIGURE_STEP + 1))
  progress_line "$CONFIGURE_STEP" "$CONFIGURE_STEPS" "$name"
  progress_banner "$name"
  shift
  "$@"
}

# Fail-fast: module errors propagate (no || true swallow).
if selected SETUP_FIREWALLD; then
  run_mod firewalld bash "$REPO_ROOT/scripts/firewalld-lab-zones.sh"
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
