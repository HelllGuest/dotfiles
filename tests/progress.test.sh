#!/usr/bin/env bash
# progress.sh bars + Stage B wiring (install.sh / configure.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck source=scripts/lib/progress.sh
source "$ROOT/scripts/lib/progress.sh"

bar_utf8="$(LC_ALL=en_US.UTF-8 ui_bar 0 10)"
[[ $bar_utf8 == '[░░░░░░░░░░]' ]] || fail "UTF-8 0%: got $bar_utf8"
bar_utf8="$(LC_ALL=en_US.UTF-8 ui_bar 50 10)"
[[ $bar_utf8 == '[█████░░░░░]' ]] || fail "UTF-8 50%: got $bar_utf8"
bar_utf8="$(LC_ALL=en_US.UTF-8 ui_bar 100 10)"
[[ $bar_utf8 == '[██████████]' ]] || fail "UTF-8 100%: got $bar_utf8"

bar_c="$(LC_ALL=C ui_bar 0 10)"
[[ $bar_c == '[----------]' ]] || fail "C 0%: got $bar_c"
bar_c="$(LC_ALL=C ui_bar 40 10)"
[[ $bar_c == '[####------]' ]] || fail "C 40%: got $bar_c"
bar_c="$(LC_ALL=C ui_bar 100 10)"
[[ $bar_c == '[##########]' ]] || fail "C 100%: got $bar_c"

grep -q 'scripts/lib/progress.sh' "$ROOT/install.sh" \
  || fail "install.sh must source progress.sh"
grep -q 'progress_line' "$ROOT/install.sh" \
  || fail "install.sh must call progress_line"
grep -q 'advance_progress' "$ROOT/install.sh" \
  || fail "install.sh must define advance_progress"

_rs=$(grep -c 'run_step "' "$ROOT/install.sh")
_ap=0
for _lab in "pacman packages" "machine profile" "stow dotfiles" "Node 22 (fnm install)" \
  "privacy hardener" "health check"; do
  grep -q "advance_progress \"$_lab\"" "$ROOT/install.sh" \
    || fail "missing advance_progress \"$_lab\""
  _ap=$((_ap + 1))
done
_expect=$((_rs + _ap))
grep -q "INSTALL_STEPS=${_expect}" "$ROOT/install.sh" \
  || fail "INSTALL_STEPS must equal run_step($_rs)+advance($_ap)=$_expect"
unset -v _rs _ap _expect _lab

grep -q 'scripts/lib/progress.sh' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must source progress.sh"
grep -q -- '--backtitle' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must set dialog/whiptail backtitle"
grep -q 'NEWT_COLORS=' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must set NEWT_COLORS"
grep -q 'dialogrc' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must write a dialogrc"
grep -q 'progress_line' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh run_mod must call progress_line"
grep -q 'progress_banner' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh run_mod must call progress_banner"
# Runnable count must exclude OLLAMA on non-P15 (is_p15 gate before +=).
grep -q 'selected SETUP_OLLAMA && (( is_p15 ))' "$ROOT/scripts/configure.sh" \
  || fail "CONFIGURE_STEPS must not count OLLAMA when not P15"
grep -q 'configure_once' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must support CONFIGURE_ONCE / one-shot mode"
grep -q 'Stage B main menu' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must offer an interactive main menu loop"
grep -q 'CONFIGURE_ONCE=1' "$ROOT/install.sh" \
  || fail "install.sh must set CONFIGURE_ONCE=1 so the menu does not block"

# ── configure.sh behaviour (dummy modules in a temp copy) ──────────────
# cfg_run INPUT [ENV…]: run configure.sh with INPUT on a pty (the menu loop)
# or, when INPUT is "-", with stdin closed (one-shot). Sets cfg_rc, cfg_out,
# cfg_ran (modules that ran, one per line).
CT="$(mktemp -d)"
trap 'rm -rf "$CT"' EXIT
mkdir -p "$CT/scripts/lib" "$CT/bin"
cp "$ROOT/scripts/configure.sh" "$CT/scripts/"
cp "$ROOT/scripts/lib/dmi.sh" "$ROOT/scripts/lib/progress.sh" "$CT/scripts/lib/"
for _m in firewalld-lab-zones apply-profile ollama-setup labs-setup lab-detonate ai-stack-setup rice-setup; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_m" "$CT" >"$CT/scripts/$_m.sh"
done
unset -v _m
# The menu tests need script(1) that passes end of input on to the pty
# (util-linux 2.35+); otherwise they would hang until the timeout.
cfg_pty_ok() {
  if [[ -z ${cfg_pty:-} ]]; then
    cfg_pty=no
    command -v script >/dev/null \
      && [[ $(printf 'x\n' | timeout 5 script -qec 'read -r a; read -r b || echo EOF' /dev/null 2>&1) == *EOF* ]] \
      && cfg_pty=yes
    [[ $cfg_pty == yes ]] || echo "SKIPPED: configure menu tests (script(1) missing or does not pass EOF)"
  fi
  [[ $cfg_pty == yes ]]
}
cfg_run() {
  local input=$1; shift
  : >"$CT/ran"
  if [[ $input == - ]]; then
    cfg_out="$(env "$@" timeout 20 bash "$CT/scripts/configure.sh" </dev/null 2>&1)" && cfg_rc=0 || cfg_rc=$?
  else
    cfg_pty_ok || return 1
    cfg_out="$(printf '%b' "$input" | env "$@" timeout 20 script -qec "bash $CT/scripts/configure.sh; echo RC=\$?" /dev/null 2>&1)" || true
    cfg_rc=$(sed -n 's/.*RC=\([0-9]*\).*/\1/p' <<<"$cfg_out" | tail -1)
  fi
  cfg_ran="$(cat "$CT/ran")"
}
if cfg_run - CONFIGURE_UI=plain; then
  [[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones ]] \
    || fail "no TTY: one-shot must run the defaults once (rc=$cfg_rc ran=[$cfg_ran])"
fi
if cfg_run '' CONFIGURE_UI=plain; then
  [[ $cfg_rc == 0 && -z $cfg_ran ]] || fail "Ctrl-D at the menu must quit (rc=$cfg_rc ran=[$cfg_ran])"
  # "2" then Ctrl-D (no newline): the typed text is the answer (profile).
  cfg_run '2\004\004' CONFIGURE_UI=plain
  [[ $cfg_rc == 0 && $cfg_ran == apply-profile ]] \
    || fail "text typed before Ctrl-D must count as the answer (rc=$cfg_rc)"
  cfg_run '2\n3\n' CONFIGURE_UI=plain
  [[ $cfg_rc == 0 && $cfg_ran == apply-profile && $cfg_out == *'Profile finished.'* ]] \
    || fail "menu: Apply machine profile (rc=$cfg_rc ran=[$cfg_ran])"
  cfg_run '9\n1\n\n3\n' CONFIGURE_UI=plain
  [[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones ]] \
    || fail "menu: bad number, modules, quit (rc=$cfg_rc ran=[$cfg_ran])"
  [[ $cfg_out == *'not a choice: 9'* ]] || fail "menu must re-ask after a bad number"
  [[ $cfg_out == *'Selected modules finished.'* ]] || fail "loop must report finished modules"
  cfg_run '1\nNONE\n3\n' CONFIGURE_UI=plain
  [[ $cfg_rc == 0 && -z $cfg_ran && $cfg_out == *'No modules ran.'* ]] \
    || fail "empty selection must say so (rc=$cfg_rc ran=[$cfg_ran])"
  cfg_run '1\nSETUP_OLLAMA\n3\n' CONFIGURE_UI=plain
  if [[ $cfg_out == *'not a P15'* ]]; then
    [[ $cfg_rc == 0 && -z $cfg_ran && $cfg_out == *'No modules ran.'* ]] \
      || fail "OLLAMA skipped off a P15 must report that no module ran (rc=$cfg_rc)"
  fi
  cfg_run '\n' CONFIGURE_UI=plain CONFIGURE_ONCE=1
  [[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones && $cfg_out != *'Stage B main menu'* \
     && $cfg_out != *'Selected modules finished.'* ]] \
    || fail "CONFIGURE_ONCE=1: one checklist, no menu, no extra prompt (rc=$cfg_rc)"
  printf '#!/bin/sh\nexit 3\n' >"$CT/scripts/firewalld-lab-zones.sh"
  cfg_run '1\n\n3\n' CONFIGURE_UI=plain
  [[ $cfg_rc == 1 && $cfg_out == *'Module failed: firewalld'* ]] \
    || fail "a failing module must stop the menu loop with exit 1 (rc=$cfg_rc)"
  printf '#!/bin/sh\necho firewalld-lab-zones >>"%s/ran"\n' "$CT" >"$CT/scripts/firewalld-lab-zones.sh"
fi
# whiptail draws on stdout and answers on stderr: the checklist must capture
# the answer. A stand-in whiptail does exactly that (screen → stdout, the
# "on" tags / first menu tag → stderr); the menu queue is $CT/menu.
cat >"$CT/bin/whiptail" <<'WT'
#!/usr/bin/env bash
echo SCREEN
while (($#)); do
  case $1 in
    --checklist) [[ -n ${WT_CANCEL:-} ]] && exit 1; shift 5; while (($# >= 3)); do [[ $3 == on ]] && echo "$1" >&2; shift 3; done ;;
    --menu) q=$(head -1 "$WT_MENU"); sed -i 1d "$WT_MENU"; [[ $q == quit ]] && exit 1; echo "$q" >&2; exit 0 ;;
    *) shift ;;
  esac
done
WT
chmod +x "$CT/bin/whiptail"
cfg_run - CONFIGURE_UI=whiptail CONFIGURE_ONCE=1 PATH="$CT/bin:$PATH"
[[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones ]] \
  || fail "whiptail checklist must return the selected tags (rc=$cfg_rc ran=[$cfg_ran])"
printf 'modules\nquit\n' >"$CT/menu"
cfg_run - CONFIGURE_UI=whiptail PATH="$CT/bin:$PATH" WT_MENU="$CT/menu"
[[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones && ! -s $CT/menu ]] \
  || fail "whiptail menu loop: modules then Quit (rc=$cfg_rc ran=[$cfg_ran])"
# Checklist Cancel returns to the menu (the queue's next item is reached).
printf 'modules\nquit\n' >"$CT/menu"
cfg_run - CONFIGURE_UI=whiptail PATH="$CT/bin:$PATH" WT_MENU="$CT/menu" WT_CANCEL=1
[[ $cfg_rc == 0 && -z $cfg_ran && ! -s $CT/menu ]] \
  || fail "checklist Cancel must return to the menu (rc=$cfg_rc ran=[$cfg_ran])"

# Forced missing TUI backend or unknown CONFIGURE_UI must fail fast (never exit 0).
_no_dialog="$CT/no-dialog"
mkdir -p "$_no_dialog"
for _cmd in bash env timeout mkdir rm mktemp tput dirname cat grep sed printf; do
  _p="$(command -v "$_cmd" 2>/dev/null || true)"
  [[ -n $_p ]] && ln -sf "$_p" "$_no_dialog/$_cmd"
done
cfg_run - CONFIGURE_UI=dialog PATH="$_no_dialog"
[[ $cfg_rc -ne 0 && $cfg_out == *'not installed'* ]] \
  || fail "CONFIGURE_UI=dialog without dialog must exit non-zero (rc=$cfg_rc out=$cfg_out)"
cfg_run - CONFIGURE_UI=bogus
[[ $cfg_rc -ne 0 && $cfg_out == *'unknown CONFIGURE_UI'* ]] \
  || fail "unknown CONFIGURE_UI must exit non-zero (rc=$cfg_rc out=$cfg_out)"
unset -v _no_dialog _cmd _p

# ui_dims clamps to the terminal and returns 0 (callable under set -e).
_dims="$(sed -n '/^ui_dims() {/,/^}/p' "$ROOT/scripts/configure.sh")"
[[ -n $_dims ]] || fail "configure.sh: ui_dims not found"
_got="$(LINES=20 COLUMNS=70 TERM=xterm bash -euo pipefail -c "$_dims"'
  ui_dims 20 76 12; echo "$UI_H $UI_W $UI_LH"')" \
  || fail "ui_dims must return 0 under set -e"
[[ $_got == '18 66 10' ]] || fail "ui_dims 70x20: want '18 66 10', got '$_got'"
_got="$(LINES=50 COLUMNS=200 TERM=xterm bash -euo pipefail -c "$_dims"'
  ui_dims 12 60; echo "$UI_H $UI_W"')" || fail "ui_dims (no list) must return 0"
[[ $_got == '12 60' ]] || fail "ui_dims must keep the wanted size on a big terminal, got '$_got'"
unset -v _dims _got

bash -n "$ROOT/scripts/lib/progress.sh" || fail "bash -n progress.sh"
bash -n "$ROOT/scripts/configure.sh" || fail "bash -n configure.sh"
bash -n "$ROOT/install.sh" || fail "bash -n install.sh"

echo "ok progress bars + Stage B wiring"
