#!/usr/bin/env bash
# configure.sh — Stage B post-boot configurator (dialog → whiptail → plain).
# Live: firewalld, ollama (P15), profile, labs, AI stack, Gruvbox rice.
#
# Interactive (TTY): archdi-style main menu loop (Modules / Profile / Quit).
# One-shot: CONFIGURE_ONCE=1 (./install.sh) or plain UI with no stdin TTY.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"
# shellcheck source=lib/progress.sh
source "$REPO_ROOT/scripts/lib/progress.sh"

APP_TITLE="Dotfiles configure · Stage B"
DIALOG_RC_DIR=""
DEFAULT_MENU_ITEM="modules"

# CONFIGURE_UI=plain|dialog|whiptail — force backend (VM / CI: plain).
if [[ -z ${CONFIGURE_UI:-} ]]; then
  if command -v dialog >/dev/null 2>&1; then
    UI=dialog
  elif command -v whiptail >/dev/null 2>&1; then
    UI=whiptail
  else
    UI=plain
  fi
else
  UI=$CONFIGURE_UI
  case $UI in
    dialog|whiptail)
      if ! command -v "$UI" >/dev/null 2>&1; then
        echo "configure.sh: CONFIGURE_UI=$UI requested, but '$UI' is not installed" >&2
        exit 1
      fi
      ;;
    plain) ;;
    *)
      echo "configure.sh: unknown CONFIGURE_UI='$UI' (use plain|dialog|whiptail)" >&2
      exit 1
      ;;
  esac
fi

# Clamp dialog/whiptail dimensions to current terminal (defaults 24x80).
ui_dims() {
  local want_h=$1 want_w=$2 want_lh=${3:-0} rows cols
  rows=$(tput lines 2>/dev/null || echo 24)
  cols=$(tput cols 2>/dev/null || echo 80)
  [[ $rows =~ ^[0-9]+$ ]] || rows=24
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
  UI_H=$want_h; (( rows - 2 < UI_H )) && UI_H=$(( rows - 2 )); (( UI_H < 12 )) && UI_H=12
  UI_W=$want_w; (( cols - 4 < UI_W )) && UI_W=$(( cols - 4 )); (( UI_W < 40 )) && UI_W=40
  if (( want_lh > 0 )); then
    UI_LH=$want_lh
    (( UI_H - 8 < UI_LH )) && UI_LH=$(( UI_H - 8 ))
    (( UI_LH < 4 )) && UI_LH=4
  fi
  return 0
}

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

# Default SETUP_OLLAMA on for P15 (20SU); off elsewhere (T14s never wants host ollama).
OLLAMA_STATE=off
if [[ $is_p15 -eq 1 ]]; then
  OLLAMA_STATE=on
fi

checklist() {
  local title=$1; shift
  case $UI in
    dialog)
      ui_dims 20 76 12
      dialog --colors --backtitle "$APP_TITLE" --stdout --separate-output \
        --checklist "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" || return 1
      ;;
    whiptail)
      # whiptail draws on stdout and answers on stderr: swap them so $(…)
      # captures the tags, not the screen.
      ui_dims 20 76 12
      whiptail --backtitle "$APP_TITLE" --separate-output \
        --checklist "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" 3>&1 1>&2 2>&3 || return 1
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

# menu TITLE TAG DESC [TAG DESC ...] -> tag on stdout
menu() {
  local title=$1; shift
  case $UI in
    dialog)
      ui_dims 16 72 8
      dialog --colors --backtitle "$APP_TITLE" --stdout \
        --default-item "${DEFAULT_MENU_ITEM:-}" \
        --cancel-label Quit --ok-label Select \
        --menu "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" || return 1
      ;;
    whiptail)
      ui_dims 16 72 8
      whiptail --backtitle "$APP_TITLE" \
        --default-item "${DEFAULT_MENU_ITEM:-}" \
        --cancel-button Quit --ok-button Select \
        --menu "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" 3>&1 1>&2 2>&3 || return 1
      ;;
    *)
      echo "$title" >&2
      local tags=() descs=() t d i=0
      while (($# >= 2)); do
        t=$1; d=$2; shift 2
        tags+=("$t"); descs+=("$d"); i=$((i + 1))
        printf '  %d) %s [%s]\n' "$i" "$d" "$t" >&2
      done
      # End of input (Ctrl-D) on an empty line quits; text typed before
      # Ctrl-D still counts as the answer. Out of range asks again.
      local pick
      while true; do
        read -r -p "choose 1-$i (empty=1): " pick || [[ -n $pick ]] || return 1
        [[ -z $pick ]] && pick=1
        if [[ $pick =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= i )); then
          printf '%s' "${tags[pick - 1]}"
          return 0
        fi
        echo "not a choice: $pick" >&2
      done
      ;;
  esac
}

msg() {
  case $UI in
    dialog) ui_dims 12 60; dialog --colors --backtitle "$APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    whiptail) ui_dims 12 60; whiptail --backtitle "$APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    *) printf '%s\n' "$1" ;;
  esac
}

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
    msg "Module failed: $name"
    exit 1
  fi
}

# Checklist → run selected modules (fail-fast). Returns 1 if checklist aborted.
run_modules_batch() {
  local OPTS
  OPTS="$(checklist "Stage B modules" \
    SETUP_FIREWALLD "firewalld drop + libvirt + lab-malware zones" on \
    APPLY_PROFILE "Re-run machine profile (detect / hostname)" off \
    SETUP_OLLAMA "P15: ollama-cuda + qwen models (localhost)" "$OLLAMA_STATE" \
    SETUP_LABS "Labs lab-triage/re/android/web (+ capture)" off \
    SETUP_DETONATE "Detonation VMs + INetSim/PolarProxy" off \
    SETUP_AI "AI MCP / Headroom / Continue / Ponytail" off \
    SETUP_RICE "Gruvbox rice + notifications + launchers" off
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
  (( CONFIGURE_STEPS < 1 )) && CONFIGURE_STEPS=1

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
  return 0
}

run_profile_only() {
  CONFIGURE_STEP=0
  CONFIGURE_STEPS=1
  run_mod profile bash "$REPO_ROOT/scripts/apply-profile.sh"
  msg "Profile finished."
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
  choice="$(menu "Stage B main menu" \
    modules "Run modules (checklist)" \
    profile "Apply machine profile" \
    quit "Quit")" || choice=quit
  DEFAULT_MENU_ITEM=$choice
  case $choice in
    modules)
      # Checklist Cancel → back to menu. Module failure → exit 1 (run_mod).
      # CONFIGURE_STEP is how many modules ran.
      if run_modules_batch; then
        if (( CONFIGURE_STEP > 0 )); then
          msg "Selected modules finished."
        else
          msg "No modules ran."
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
