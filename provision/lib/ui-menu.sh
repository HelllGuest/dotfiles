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
# Reads /dev/tty via stty because callers capture $(ui_menu ...) on a pipe,
# where tput falls back to 24x80 even on wide desktop terminals.
ui_dims() {
  local want_h=$1 want_w=$2 want_lh=${3:-0} rows="" cols="" sz=""
  if [[ ${LINES:-} =~ ^[1-9][0-9]*$ && ${COLUMNS:-} =~ ^[1-9][0-9]*$ ]]; then
    rows=$LINES
    cols=$COLUMNS
  else
    sz=$(stty size 2>/dev/null </dev/tty) || sz=""
    if [[ $sz =~ ^([1-9][0-9]*)[[:space:]]+([1-9][0-9]*)$ ]]; then
      rows=${BASH_REMATCH[1]}
      cols=${BASH_REMATCH[2]}
    else
      rows=$(tput lines 2>/dev/null || echo 24)
      cols=$(tput cols 2>/dev/null || echo 80)
    fi
  fi
  [[ $rows =~ ^[1-9][0-9]*$ ]] || rows=24
  [[ $cols =~ ^[1-9][0-9]*$ ]] || cols=80
  UI_H=$want_h; (( rows - 2 < UI_H )) && UI_H=$(( rows - 2 )); (( UI_H < 12 )) && UI_H=12
  UI_W=$want_w; (( cols - 4 < UI_W )) && UI_W=$(( cols - 4 )); (( UI_W < 40 )) && UI_W=40
  # Never exceed the actual terminal on tiny consoles.
  (( UI_H > rows - 2 )) && UI_H=$(( rows - 2 ))
  (( UI_W > cols - 2 )) && UI_W=$(( cols - 2 ))
  (( UI_H < 1 )) && UI_H=1
  (( UI_W < 1 )) && UI_W=1
  if (( want_lh > 0 )); then
    UI_LH=$want_lh
    (( UI_H - 8 < UI_LH )) && UI_LH=$(( UI_H - 8 ))
    (( UI_LH < 4 )) && UI_LH=4
    (( UI_LH > UI_H - 6 )) && UI_LH=$(( UI_H - 6 ))
    (( UI_LH < 1 )) && UI_LH=1
  fi
  return 0
}

# Dark TUI palette with cyan focus accent (8-colour console safe, no bright/gray bg).
# Call ui_theme_cleanup on EXIT. Every widget key is set so whiptail/dialog never fall
# back to default blue/red/gray boxes.
ui_theme_init() {
  if [[ $UI == dialog ]]; then
    UI_DIALOG_RC_DIR="$(mktemp -d /tmp/dotfiles-dialogrc.XXXXXX)"
    cat >"$UI_DIALOG_RC_DIR/dialogrc" <<'EOF'
# Dotfiles TUI theme (dark + cyan accent)
use_shadow = ON
use_colors = ON
screen_color = (WHITE,BLACK,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (CYAN,BLACK,OFF)
border2_color = (CYAN,BLACK,OFF)
button_active_color = (BLACK,CYAN,OFF)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,CYAN,OFF)
button_key_inactive_color = (CYAN,BLACK,ON)
button_label_active_color = (BLACK,CYAN,OFF)
button_label_inactive_color = (WHITE,BLACK,OFF)
inputbox_color = (WHITE,BLACK,OFF)
inputbox_border_color = (CYAN,BLACK,OFF)
inputbox_border2_color = (CYAN,BLACK,OFF)
searchbox_color = (WHITE,BLACK,OFF)
searchbox_title_color = (CYAN,BLACK,ON)
searchbox_border_color = (CYAN,BLACK,OFF)
searchbox_border2_color = (CYAN,BLACK,OFF)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (CYAN,BLACK,OFF)
menubox_border2_color = (CYAN,BLACK,OFF)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,OFF)
tag_color = (CYAN,BLACK,ON)
tag_selected_color = (BLACK,CYAN,OFF)
tag_key_color = (CYAN,BLACK,ON)
tag_key_selected_color = (BLACK,CYAN,OFF)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,CYAN,OFF)
uarrow_color = (CYAN,BLACK,ON)
darrow_color = (CYAN,BLACK,ON)
itemhelp_color = (BLACK,CYAN,OFF)
gauge_color = (BLACK,CYAN,OFF)
position_indicator_color = (CYAN,BLACK,ON)
EOF
    export DIALOGRC="$UI_DIALOG_RC_DIR/dialogrc"
  elif [[ $UI == whiptail ]]; then
    export NEWT_COLORS='
root=lightgray,black
roottext=brightcyan,black
border=cyan,black
window=lightgray,black
shadow=black,black
title=brightcyan,black
button=lightgray,black
actbutton=black,cyan
compactbutton=lightgray,black
checkbox=lightgray,black
actcheckbox=black,cyan
entry=white,black
label=white,black
listbox=lightgray,black
actlistbox=black,cyan
sellistbox=brightcyan,black
actsellistbox=black,cyan
textbox=lightgray,black
acttextbox=black,cyan
helpline=lightgray,black
emptyscale=,black
fullscale=,cyan
disentry=gray,black
'
  fi
}

ui_theme_cleanup() {
  if [[ -n ${UI_DIALOG_RC_DIR:-} && -d $UI_DIALOG_RC_DIR ]]; then
    if [[ ${DIALOGRC:-} == "$UI_DIALOG_RC_DIR/"* ]]; then
      unset DIALOGRC
    fi
    rm -rf -- "$UI_DIALOG_RC_DIR"
  fi
  UI_DIALOG_RC_DIR=""
}

# ui_checklist TITLE TAG DESC STATE [TAG DESC STATE ...] -> selected tags (one per line)
# Set UI_CANCEL_LABEL=Back for sub-screens so TUI shows Back and plain accepts BACK.
ui_checklist() {
  local title=$1 cancel_lbl="${UI_CANCEL_LABEL:-Cancel}"; shift
  case $UI in
    zenity)
      local zargs=() tag item state flag
      while (($# >= 3)); do
        tag=$1; item=$2; state=$3; shift 3
        if [[ $state == on || $state == ON ]]; then flag=TRUE; else flag=FALSE; fi
        zargs+=("$flag" "$tag" "$item")
      done
      zenity --list --checklist --title="$UI_APP_TITLE" --text="$title" \
        --width=840 --height=620 \
        --column="Run" --column="Tag" --column="Description" \
        --hide-column=2 --print-column=2 --separator=$'\n' \
        "${zargs[@]}" || return 1
      ;;
    dialog)
      ui_dims 24 104 16
      dialog --colors --backtitle "$UI_APP_TITLE" --stdout --separate-output \
        --cancel-label "$cancel_lbl" \
        --checklist "$title (Space: toggle · Enter: Ok · Esc: $cancel_lbl)" \
        "$UI_H" "$UI_W" "$UI_LH" "$@" || return 1
      ;;
    whiptail)
      # whiptail draws on stdout and answers on stderr: swap them so $(…)
      # captures the tags, not the screen. --fullbuttons makes Ok/Back focus visible.
      ui_dims 26 104 16
      local lh=$UI_LH
      (( UI_H - lh < 10 )) && lh=$(( UI_H - 10 ))
      (( lh < 1 )) && lh=1
      whiptail --fullbuttons --backtitle "$UI_APP_TITLE" --separate-output \
        --cancel-button "$cancel_lbl" \
        --checklist "$title (Space: toggle · Enter: Ok · Tab: Ok/$cancel_lbl)" \
        "$UI_H" "$UI_W" "$lh" "$@" 3>&1 1>&2 2>&3 || return 1
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
      printf 'Enter tags to enable (space-separated, empty=defaults on, NONE=none, BACK=back):\n' >&2
      local ans
      read -r ans || true
      if [[ ${ans^^} == BACK ]]; then
        return 1
      fi
      if [[ -n $ans ]]; then
        read -r -a out <<<"$ans"
      fi
      printf '%s\n' "${out[@]}"
      ;;
  esac
}

# ui_menu TITLE TAG DESC [TAG DESC ...] -> tag on stdout
# Set UI_CANCEL_LABEL=Back for submenus so TUI shows Back, adds a Back row, and plain accepts b/back.
ui_menu() {
  local title=$1 cancel_lbl="${UI_CANCEL_LABEL:-Quit}"; shift
  local auto_back=0 menu_items=("$@")
  if [[ $cancel_lbl == Back && $UI != plain ]]; then
    local _has_back=0 _idx=0
    while (( _idx < ${#menu_items[@]} )); do
      [[ ${menu_items[_idx]} == back ]] && { _has_back=1; break; }
      _idx=$((_idx + 2))
    done
    if (( ! _has_back )); then
      auto_back=1
      menu_items+=(back "Back")
    fi
  fi
  local pick=""
  case $UI in
    zenity)
      local zargs=() t d flag first=1 matched=0 idx=0
      if [[ -n ${DEFAULT_MENU_ITEM:-} ]]; then
        while (( idx < ${#menu_items[@]} )); do
          [[ ${menu_items[idx]} == "$DEFAULT_MENU_ITEM" ]] && { matched=1; break; }
          idx=$((idx + 2))
        done
      fi
      idx=0
      while (( idx + 1 < ${#menu_items[@]} )); do
        t=${menu_items[idx]}; d=${menu_items[idx + 1]}; idx=$((idx + 2))
        if (( matched )); then
          if [[ $t == "$DEFAULT_MENU_ITEM" ]]; then flag=TRUE; else flag=FALSE; fi
        elif (( first )); then
          flag=TRUE; first=0
        else
          flag=FALSE
        fi
        zargs+=("$flag" "$t" "$d")
      done
      pick="$(zenity --list --radiolist --title="$UI_APP_TITLE" --text="$title" \
        --width=760 --height=480 \
        --column="" --column="Action" --column="Description" \
        --hide-column=2 --print-column=2 \
        "${zargs[@]}")" || return 1
      ;;
    dialog)
      ui_dims 18 96 10
      pick="$(dialog --colors --backtitle "$UI_APP_TITLE" --stdout \
        --default-item "${DEFAULT_MENU_ITEM:-}" \
        --cancel-label "$cancel_lbl" --ok-label Select \
        --menu "$title" "$UI_H" "$UI_W" "$UI_LH" "${menu_items[@]}")" || return 1
      ;;
    whiptail)
      ui_dims 20 96 10
      local lh=$UI_LH
      (( UI_H - lh < 10 )) && lh=$(( UI_H - 10 ))
      (( lh < 1 )) && lh=1
      pick="$(whiptail --fullbuttons --backtitle "$UI_APP_TITLE" \
        --default-item "${DEFAULT_MENU_ITEM:-}" \
        --cancel-button "$cancel_lbl" --ok-button Select \
        --menu "$title (Enter: Select · Tab: $cancel_lbl)" "$UI_H" "$UI_W" "$lh" "${menu_items[@]}" 3>&1 1>&2 2>&3)" || return 1
      ;;
    *)
      echo "$title" >&2
      local tags=() descs=() t d i=0 idx=0
      while (( idx + 1 < ${#menu_items[@]} )); do
        t=${menu_items[idx]}; d=${menu_items[idx + 1]}; idx=$((idx + 2))
        tags+=("$t"); descs+=("$d"); i=$((i + 1))
        printf '  %d) %s [%s]\n' "$i" "$d" "$t" >&2
      done
      # End of input (Ctrl-D) on an empty line quits/goes back; text typed before
      # Ctrl-D still counts as the answer. Out of range asks again.
      local prompt="choose 1-$i (empty=1): "
      if [[ $cancel_lbl == Back ]]; then
        prompt="choose 1-$i (empty=1, b=back): "
      fi
      while true; do
        read -r -p "$prompt" pick || [[ -n $pick ]] || return 1
        [[ -z $pick ]] && pick=1
        if [[ $cancel_lbl == Back && ( ${pick,,} == b || ${pick,,} == back ) ]]; then
          return 1
        fi
        if [[ $pick =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= i )); then
          pick="${tags[pick - 1]}"
          break
        fi
        echo "not a choice: $pick" >&2
      done
      ;;
  esac
  if (( auto_back )) && [[ $pick == back ]]; then
    return 1
  fi
  printf '%s' "$pick"
  return 0
}

# ui_msg TEXT
ui_msg() {
  case $UI in
    zenity) zenity --info --title="$UI_APP_TITLE" --no-markup --text="$1" --width=520 || true ;;
    dialog) ui_dims 14 72; dialog --colors --backtitle "$UI_APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    whiptail) ui_dims 14 72; whiptail --fullbuttons --backtitle "$UI_APP_TITLE" --msgbox "$1" "$UI_H" "$UI_W" || true ;;
    *) printf '%s\n' "$1" ;;
  esac
}
