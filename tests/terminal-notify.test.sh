#!/usr/bin/env bash
# Command-finished notifications in every terminal: native (focus-aware) in
# kitty / Ghostty / Console, shell notify-send fallback everywhere else, never both.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -qE '^notify_on_cmd_finish unfocused ' "$ROOT/stow/kitty/.config/kitty/kitty.conf" \
  || fail "kitty must notify on command finish when unfocused"
grep -qx 'shell_integration enabled' "$ROOT/stow/kitty/.config/kitty/kitty.conf" \
  || fail "kitty notify_on_cmd_finish needs shell_integration"
g="$ROOT/stow/ghostty/.config/ghostty/config"
grep -qx 'notify-on-command-finish = unfocused' "$g" || fail "ghostty must notify when unfocused"
grep -qE '^notify-on-command-finish-action = .*(^|,)notify' "$g" || fail "ghostty action must include notify"
grep -q '/etc/profile.d/vte.sh' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell must load vte.sh (Console notifications need vte.shell.postexec)"
for app in kitty com-mitchellh-ghostty org-gnome-console alacritty org-contourterminal-contour; do
  grep -qx "\[org/gnome/desktop/notifications/application/$app\]" "$ROOT/gnome/dconf/user.conf" \
    || fail "dconf must allow notifications for $app"
done

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# The terminal is the shell's parent process: fake it with a bash binary named
# after each terminal (comm = file name), running the shell under test
# (the trailing ':' stops bash from exec'ing the shell in its place).
for term in kitty ghostty kgx alacritty; do ln -s "$(command -v bash)" "$T/$term"; done
for sh in bash zsh; do
  command -v "$sh" >/dev/null || { echo "SKIP: $sh not installed"; continue; }
  probe() {  # TERMINAL [VAR=value...]
    local term=$1; shift
    env -i HOME="$HOME" PATH="$PATH" WAYLAND_DISPLAY=wayland-0 "$@" "$T/$term" -c \
      '"$1" -c '\''autoload -Uz add-zsh-hook 2>/dev/null; source "$0" >/dev/null 2>&1
       _has() { [ "$1" = notify-send ] || command -v "$1" >/dev/null 2>&1; }
       _cmd_notify_supported && echo fallback || echo off'\'' "$2"; :' _ "$sh" "$ROOT/stow/zsh/.shell-functions"
  }
  [[ $(probe kitty) == off ]] || fail "$sh: kitty notifies natively, no shell duplicate"
  [[ $(probe ghostty) == off ]] || fail "$sh: ghostty notifies natively, no shell duplicate"
  [[ $(probe kgx) == off ]] || fail "$sh: Console notifies natively (vte.sh), no shell duplicate"
  [[ $(probe kgx TMUX=/t) == fallback ]] || fail "$sh: inside tmux the shell hook must notify"
  [[ $(probe alacritty) == fallback ]] || fail "$sh: other terminals use the shell hook"
  [[ $(probe alacritty KITTY_WINDOW_ID=3) == fallback ]] \
    || fail "$sh: a KITTY_WINDOW_ID inherited into another terminal must not silence it"
done

# $? survives the prompt hooks (starship / VTE read it afterwards).
for sh in bash zsh; do
  command -v "$sh" >/dev/null || continue
  r="$("$sh" -c 'autoload -Uz add-zsh-hook 2>/dev/null; source "$1" >/dev/null 2>&1
    (exit 7); _cmd_notify_end; echo $?' _ "$ROOT/stow/zsh/.shell-functions")"
  [[ $r == 7 ]] || fail "$sh: _cmd_notify_end must keep the command's status (got $r)"
done
r="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color bash --rcfile "$ROOT/stow/bash/.bashrc" -i -c \
  '(exit 4); _update_terminal_cwd >/dev/null; echo $?' 2>/dev/null | tail -1)"
[[ $r == 4 ]] || fail "bash _update_terminal_cwd must keep the command's status (got $r)"
# bash in a VTE terminal: VTE's precmd runs first (sees the real $?), rest kept.
r="$(env -i HOME="$HOME" PATH="$PATH" VTE_VERSION=8401 TERM=xterm-256color bash --rcfile "$ROOT/stow/bash/.bashrc" -i -c \
  'printf "%s|" "${PROMPT_COMMAND[@]}"' 2>/dev/null | tail -1)"
[[ $r == __vte_precmd\|*_cmd_notify_end*\|__vte_osc7\| ]] || [[ ! -r /etc/profile.d/vte.sh ]] \
  || fail "bash VTE hook order wrong: $r"

echo "PASS: terminal-notify.test.sh"
