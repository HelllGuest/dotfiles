#!/usr/bin/env bash
# ui-menu.sh — shared TUI/GUI/plain menu backend for install.sh and configure.sh.
# Backends: dialog | whiptail | zenity (gui) | plain.
# shellcheck shell=bash

UI=""
UI_APP_TITLE="${UI_APP_TITLE:-Dotfiles}"
UI_DIALOG_RC_DIR=""
DEFAULT_MENU_ITEM="${DEFAULT_MENU_ITEM:-}"

# ui_init [REQUESTED] [APP_TITLE] [ENV_NAME]
# Empty REQUESTED auto-detects terminal TUI: dialog -> whiptail -> plain.
ui_init() {
  local req=${1:-} title=${2:-} env_name=${3:-UI}
  [[ -n $title ]] && UI_APP_TITLE=$title

  if [[ -z $req ]]; then
    if command -v dialog >/dev/null 2>&1; then
      UI=dialog
    elif command -v whiptail >/dev/null 2>&1; then
      UI=whiptail
    else
      UI=plain
    fi
    return 0
  fi

  case $req in
    gui|zenity)
      if ! command -v zenity >/dev/null 2>&1; then
        echo "${0##*/}: ${env_name}=${req} requested, but 'zenity' is not installed" >&2
        return 1
      fi
      if [[ -z ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        echo "${0##*/}: ${env_name}=${req} requested, but no DISPLAY/WAYLAND_DISPLAY session is active" >&2
        return 1
      fi
      UI=zenity
      ;;
    tui)
      if command -v dialog >/dev/null 2>&1; then
        UI=dialog
      elif command -v whiptail >/dev/null 2>&1; then
        UI=whiptail
      else
        echo "${0##*/}: ${env_name}=tui requested, but neither 'dialog' nor 'whiptail' is installed" >&2
        return 1
      fi
      ;;
    dialog|whiptail)
      if ! command -v "$req" >/dev/null 2>&1; then
        echo "${0##*/}: ${env_name}=${req} requested, but '${req}' is not installed" >&2
        return 1
      fi
      UI=$req
      ;;
    plain)
      UI=plain
      ;;
    *)
      echo "${0##*/}: unknown ${env_name}='${req}' (use plain|tui|dialog|whiptail|gui|zenity)" >&2
      return 1
      ;;
  esac
}

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

# Minimal Stage A–matching chrome (8-colour console safe). Call ui_theme_cleanup on EXIT.
ui_theme_init() {
  if [[ $UI == dialog ]]; then
    UI_DIALOG_RC_DIR="$(mktemp -d /tmp/dotfiles-dialogrc.XXXXXX)"
    cat >"$UI_DIALOG_RC_DIR/dialogrc" <<'EOF'
# Dotfiles TUI theme (Stage A palette)
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
    export DIALOGRC="$UI_DIALOG_RC_DIR/dialogrc"
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

ui_theme_cleanup() {
  [[ -n ${UI_DIALOG_RC_DIR:-} && -d $UI_DIALOG_RC_DIR ]] && rm -rf -- "$UI_DIALOG_RC_DIR"
  UI_DIALOG_RC_DIR=""
}

# ui_checklist TITLE TAG DESC STATE [TAG DESC STATE ...] -> selected tags (one per line)
ui_checklist() {
  local title=$1; shift
  case $UI in
    zenity)
      local zargs=() tag item state flag
      while (($# >= 3)); do
        tag=$1; item=$2; state=$3; shift 3
        if [[ $state == on || $state == ON ]]; then flag=TRUE; else flag=FALSE; fi
        zargs+=("$flag" "$tag" "$item")
      done
      zenity --list --checklist --title="$UI_APP_TITLE" --text="$title" \
        --width=780 --height=560 \
        --column="Run" --column="Tag" --column="Description" \
        --hide-column=2 --print-column=2 --separator=$'\n' \
        "${zargs[@]}" || return 1
      ;;
    dialog)
      ui_dims 22 76 14
      dialog --colors --backtitle "$UI_APP_TITLE" --stdout --separate-output \
        --checklist "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" || return 1
      ;;
    whiptail)
      # whiptail draws on stdout and answers on stderr: swap them so $(…)
      # captures the tags, not the screen.
      ui_dims 22 76 14
      whiptail --backtitle "$UI_APP_TITLE" --separate-output \
        --checklist "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" 3>&1 1>&2 2>&3 || return 1
      ;;
    *)
      echo "$title" >&2
      local tag item state out=()
      while (($# >= 3)); do
        tag=$1; item=$2; state=$3; shift 3
        if [[ $state == on || $state == ON ]]; then
          printf '  [x] %s — %s\n' "$tag" "$item" >&2
          out+=("$tag")
        else
          printf '  [ ] %s — %s\n' "$tag" "$item" >&2
        fi
      done
      printf 'Enter tags to enable (space-separated, empty=defaults on, NONE=none):\n' >&2
      local ans
      read -r ans || true
      if [[ -n $ans ]]; then
        read -r -a out <<<"$ans"
      fi
      printf '%s\n' "${out[@]}"
      ;;
  esac
}

# ui_menu TITLE TAG DESC [TAG DESC ...] -> tag on stdout
ui_menu() {
  local title=$1; shift
  case $UI in
    zenity)
      local zargs=() t d flag first=1 matched=0
      local scan=("$@") idx=0
      if [[ -n ${DEFAULT_MENU_ITEM:-} ]]; then
        while (( idx < ${#scan[@]} )); do
          [[ ${scan[idx]} == "$DEFAULT_MENU_ITEM" ]] && { matched=1; break; }
          idx=$((idx + 2))
        done
      fi
      while (($# >= 2)); do
        t=$1; d=$2; shift 2
        if (( matched )); then
          if [[ $t == "$DEFAULT_MENU_ITEM" ]]; then flag=TRUE; else flag=FALSE; fi
        elif (( first )); then
          flag=TRUE; first=0
        else
          flag=FALSE
        fi
        zargs+=("$flag" "$t" "$d")
      done
      zenity --list --radiolist --title="$UI_APP_TITLE" --text="$title" \
        --width=680 --height=460 \
        --column="" --column="Action" --column="Description" \
        --hide-column=2 --print-column=2 \
        "${zargs[@]}" || return 1
      ;;
    dialog)
      ui_dims 18 74 10
      dialog --colors --backtitle "$UI_APP_TITLE" --stdout \
        --default-item "${DEFAULT_MENU_ITEM:-}" \
        --cancel-label Quit --ok-label Select \
        --menu "$title" "$UI_H" "$UI_W" "$UI_LH" "$@" || return 1
      ;;
    whiptail)
      ui_dims 18 74 10
      whiptail --backtitle "$UI_APP_TITLE" \
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

# ui_msg TEXT
ui_msg() {
  case $UI in
    zenity) zenity --info --title="$UI_APP_TITLE" --no-markup --text="$1" --width=460 || true ;;
    dialog) ui_dims 12 60; dialog --colors --backtitle "$UI_APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    whiptail) ui_dims 12 60; whiptail --backtitle "$UI_APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    *) printf '%s\n' "$1" ;;
  esac
}
