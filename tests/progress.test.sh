#!/usr/bin/env bash
# progress.sh bars + Stage B wiring (install.sh / configure.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck source=provision/lib/progress.sh
source "$ROOT/provision/lib/progress.sh"

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

grep -q 'provision/lib/progress.sh' "$ROOT/install.sh" \
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

grep -q 'provision/lib/progress.sh' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh must source progress.sh"
grep -q 'provision/lib/ui-menu.sh' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh must source ui-menu.sh"
grep -q 'provision/lib/ui-menu.sh' "$ROOT/install.sh" \
  || fail "install.sh must source ui-menu.sh"
grep -q -- '--backtitle' "$ROOT/provision/lib/ui-menu.sh" \
  || fail "ui-menu.sh must set dialog/whiptail backtitle"
grep -q 'NEWT_COLORS=' "$ROOT/provision/lib/ui-menu.sh" \
  || fail "ui-menu.sh must set NEWT_COLORS"
grep -q 'dialogrc' "$ROOT/provision/lib/ui-menu.sh" \
  || fail "ui-menu.sh must write a dialogrc"
grep -q 'zenity --list --checklist' "$ROOT/provision/lib/ui-menu.sh" \
  || fail "ui-menu.sh must support zenity GUI checklist"
grep -q 'progress_line' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh run_mod must call progress_line"
grep -q 'progress_banner' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh run_mod must call progress_banner"
# Runnable count must exclude OLLAMA on non-P15 (is_p15 gate before +=).
grep -q 'selected SETUP_OLLAMA && (( is_p15 ))' "$ROOT/provision/scripts/configure.sh" \
  || fail "CONFIGURE_STEPS must not count OLLAMA when not P15"
grep -q 'configure_once' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh must support CONFIGURE_ONCE / one-shot mode"
grep -q 'Stage B main menu' "$ROOT/provision/scripts/configure.sh" \
  || fail "configure.sh must offer an interactive main menu loop"
grep -q 'CONFIGURE_ONCE=1' "$ROOT/install.sh" \
  || fail "install.sh must set CONFIGURE_ONCE=1 so the menu does not block"

# ── configure.sh behaviour (dummy modules in a temp copy) ──────────────
# cfg_run INPUT [ENV…]: run configure.sh with INPUT on a pty (the menu loop)
# or, when INPUT is "-", with stdin closed (one-shot). Sets cfg_rc, cfg_out,
# cfg_ran (modules that ran, one per line).
CT="$(mktemp -d)"
trap 'rm -rf "$CT"' EXIT
mkdir -p "$CT/provision/scripts" "$CT/provision/lib" "$CT/security/scripts" "$CT/ai/scripts" "$CT/labs/scripts" "$CT/desktop/scripts" "$CT/bin"
cp "$ROOT/provision/scripts/configure.sh" "$CT/provision/scripts/"
cp "$ROOT/provision/lib/dmi.sh" "$ROOT/provision/lib/progress.sh" "$ROOT/provision/lib/ui-menu.sh" "$CT/provision/lib/"
printf '#!/bin/sh\necho firewalld-lab-zones >>"%s/ran"\n' "$CT" >"$CT/security/scripts/firewalld-lab-zones.sh"
printf '#!/bin/sh\necho apply-profile >>"%s/ran"\n' "$CT" >"$CT/provision/scripts/apply-profile.sh"
for _m in ollama-setup ai-stack-setup; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_m" "$CT" >"$CT/ai/scripts/$_m.sh"
done
for _m in labs-setup lab-detonate; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_m" "$CT" >"$CT/labs/scripts/$_m.sh"
done
printf '#!/bin/sh\necho rice-setup >>"%s/ran"\n' "$CT" >"$CT/desktop/scripts/rice-setup.sh"
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
    cfg_out="$(env "$@" timeout 20 bash "$CT/provision/scripts/configure.sh" </dev/null 2>&1)" && cfg_rc=0 || cfg_rc=$?
  else
    cfg_pty_ok || return 1
    cfg_out="$(printf '%b' "$input" | env "$@" timeout 20 script -qec "bash $CT/provision/scripts/configure.sh; echo RC=\$?" /dev/null 2>&1)" || true
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
  printf '#!/bin/sh\nexit 3\n' >"$CT/security/scripts/firewalld-lab-zones.sh"
  cfg_run '1\n\n3\n' CONFIGURE_UI=plain
  [[ $cfg_rc == 1 && $cfg_out == *'Module failed: firewalld'* ]] \
    || fail "a failing module must stop the menu loop with exit 1 (rc=$cfg_rc)"
  printf '#!/bin/sh\necho firewalld-lab-zones >>"%s/ran"\n' "$CT" >"$CT/security/scripts/firewalld-lab-zones.sh"
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

# Forced missing TUI/GUI backend or unknown CONFIGURE_UI must fail fast (never exit 0).
_no_dialog="$CT/no-dialog"
mkdir -p "$_no_dialog"
for _cmd in bash env timeout mkdir rm mktemp tput dirname cat grep sed printf; do
  _p="$(command -v "$_cmd" 2>/dev/null || true)"
  [[ -n $_p ]] && ln -sf "$_p" "$_no_dialog/$_cmd"
done
cfg_run - CONFIGURE_UI=dialog PATH="$_no_dialog"
[[ $cfg_rc -ne 0 && $cfg_out == *'not installed'* ]] \
  || fail "CONFIGURE_UI=dialog without dialog must exit non-zero (rc=$cfg_rc out=$cfg_out)"
cfg_run - CONFIGURE_UI=gui PATH="$_no_dialog"
[[ $cfg_rc -ne 0 && $cfg_out == *'not installed'* ]] \
  || fail "CONFIGURE_UI=gui without zenity must exit non-zero (rc=$cfg_rc out=$cfg_out)"
cfg_run - CONFIGURE_UI=bogus
[[ $cfg_rc -ne 0 && $cfg_out == *'unknown CONFIGURE_UI'* ]] \
  || fail "unknown CONFIGURE_UI must exit non-zero (rc=$cfg_rc out=$cfg_out)"
unset -v _no_dialog _cmd _p

# Stand-in zenity GUI backend: --checklist prints TRUE tags; --radiolist pops $ZN_MENU.
cat >"$CT/bin/zenity" <<'ZN'
#!/usr/bin/env bash
mode=""
for a in "$@"; do
  case $a in
    --checklist) mode=checklist ;;
    --radiolist) mode=radiolist ;;
    --info) exit 0 ;;
  esac
done
if [[ $mode == radiolist ]]; then
  q=$(head -1 "$ZN_MENU"); sed -i 1d "$ZN_MENU"
  [[ -z $q || $q == quit ]] && exit 1
  printf '%s\n' "$q"
  exit 0
fi
if [[ $mode == checklist ]]; then
  [[ -n ${ZN_CANCEL:-} ]] && exit 1
  if [[ -n ${ZN_PICK:-} ]]; then
    printf '%s\n' $ZN_PICK
    exit 0
  fi
  args=()
  for a in "$@"; do [[ $a != --* ]] && args+=("$a"); done
  i=0
  while (( i + 2 < ${#args[@]} )); do
    [[ ${args[i]} == TRUE ]] && printf '%s\n' "${args[i + 1]}"
    i=$((i + 3))
  done
  exit 0
fi
exit 0
ZN
chmod +x "$CT/bin/zenity"
# GUI without DISPLAY/WAYLAND_DISPLAY must fail cleanly.
cfg_run - DISPLAY= WAYLAND_DISPLAY= CONFIGURE_UI=gui PATH="$CT/bin:$PATH"
[[ $cfg_rc -ne 0 && $cfg_out == *'DISPLAY/WAYLAND_DISPLAY'* ]] \
  || fail "CONFIGURE_UI=gui without display must fail (rc=$cfg_rc out=$cfg_out)"
printf 'modules\nquit\n' >"$CT/zmenu"
cfg_run - WAYLAND_DISPLAY=wayland-0 CONFIGURE_UI=gui PATH="$CT/bin:$PATH" ZN_MENU="$CT/zmenu"
[[ $cfg_rc == 0 && $cfg_ran == firewalld-lab-zones && ! -s $CT/zmenu ]] \
  || fail "zenity GUI menu loop failed (rc=$cfg_rc ran=[$cfg_ran])"
# configure.sh CLI flags (--gui / --plain) work identically to CONFIGURE_UI.
: >"$CT/ran"
printf 'modules\nquit\n' >"$CT/zmenu"
WAYLAND_DISPLAY=wayland-0 ZN_MENU="$CT/zmenu" PATH="$CT/bin:$PATH" \
  bash "$CT/provision/scripts/configure.sh" --gui </dev/null >/dev/null 2>&1 \
  || fail "configure.sh --gui failed"
[[ "$(cat "$CT/ran")" == firewalld-lab-zones ]] \
  || fail "configure.sh --gui ran wrong modules: $(cat "$CT/ran")"
: >"$CT/ran"
bash "$CT/provision/scripts/configure.sh" --plain </dev/null >/dev/null 2>&1 \
  || fail "configure.sh --plain failed"
[[ "$(cat "$CT/ran")" == firewalld-lab-zones ]] \
  || fail "configure.sh --plain ran wrong modules: $(cat "$CT/ran")"

# ui_checklist plain mode must not glob-expand '*' and ui_menu zenity must
# pre-select the first row when DEFAULT_MENU_ITEM does not match any tag.
_noglob="$(cd "$CT" && bash -euo pipefail -c '
  source "$1"; ui_init plain; ui_checklist "Pick" a "A" on
' _ "$ROOT/provision/lib/ui-menu.sh" <<<'*' 2>/dev/null)"
[[ $_noglob == '*' ]] || fail "ui_checklist plain must not glob-expand '*' (got: $_noglob)"
_zchk="$CT/bin/zenity-chk"
cat >"$_zchk" <<'ZC'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$Z_ARGS"
printf 'first\n'
ZC
chmod +x "$_zchk"
_zout="$(Z_ARGS="$CT/zargs" WAYLAND_DISPLAY=wayland-0 PATH="$CT/bin:$PATH" bash -euo pipefail -c '
  source "$1"; UI=zenity; DEFAULT_MENU_ITEM="stale"
  zenity() { "'"$_zchk"'" "$@"; }
  ui_menu "M" first "First" second "Second"
' _ "$ROOT/provision/lib/ui-menu.sh")"
[[ $_zout == first ]] && grep -q '^TRUE$' "$CT/zargs" \
  || fail "ui_menu zenity must default to TRUE on first row when DEFAULT_MENU_ITEM misses"
unset -v _noglob _zchk _zout

# ui_dims clamps to the terminal and returns 0 (callable under set -e).
_dims="$(sed -n '/^ui_dims() {/,/^}/p' "$ROOT/provision/lib/ui-menu.sh")"
[[ -n $_dims ]] || fail "ui-menu.sh: ui_dims not found"
_got="$(LINES=20 COLUMNS=70 TERM=xterm bash -euo pipefail -c "$_dims"'
  ui_dims 20 76 12; echo "$UI_H $UI_W $UI_LH"')" \
  || fail "ui_dims must return 0 under set -e"
[[ $_got == '18 66 10' ]] || fail "ui_dims 70x20: want '18 66 10', got '$_got'"
_got="$(LINES=50 COLUMNS=200 TERM=xterm bash -euo pipefail -c "$_dims"'
  ui_dims 12 60; echo "$UI_H $UI_W"')" || fail "ui_dims (no list) must return 0"
[[ $_got == '12 60' ]] || fail "ui_dims must keep the wanted size on a big terminal, got '$_got'"
unset -v _dims _got

# ── install.sh menu & selective section flags (stub repo in $CT/inst) ──
IR="$CT/inst"
mkdir -p "$IR/scripts" "$IR/provision/scripts" "$IR/provision/lib" "$IR/desktop/scripts" "$IR/security/scripts" "$IR/bin" "$IR/bin-ok"
cp "$ROOT/install.sh" "$IR/"
cp "$ROOT/provision/lib/progress.sh" "$ROOT/provision/lib/ui-menu.sh" "$IR/provision/lib/"
for _s in check validate-configs; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_s" "$IR" >"$IR/scripts/$_s.sh"
done
printf '#!/bin/sh\necho configure >>"%s/ran"\n' "$IR" >"$IR/provision/scripts/configure.sh"
for _s in privacy-hardener ops-hygiene; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_s" "$IR" >"$IR/security/scripts/$_s.sh"
done
for _s in git-setup nvim-setup; do
  printf '#!/bin/sh\necho %s >>"%s/ran"\n' "$_s" "$IR" >"$IR/desktop/scripts/$_s.sh"
done
# Failing sudo stub proves check-only runs never ask for sudo; ok stub tracks sudo calls.
printf '#!/bin/sh\necho "SUDO_CALLED" >>"%s/ran"; exit 99\n' "$IR" >"$IR/bin/sudo"
printf '#!/bin/sh\n[ "$1" = -v ] && echo "SUDO_V" >>"%s/sudo.log"; exit 0\n' "$IR" >"$IR/bin-ok/sudo"
chmod +x "$IR/bin/sudo" "$IR/bin-ok/sudo"
_out="$(bash "$IR/install.sh" --list)"
grep -q '^packages ' <<<"$_out" && grep -q '^check ' <<<"$_out" \
  || fail "install.sh --list must print section names"
bash "$IR/install.sh" --help | grep -q -- '--only' \
  || fail "install.sh --help must document --only"
if bash "$IR/install.sh" --only bogus >/dev/null 2>&1; then
  fail "install.sh --only bogus must exit non-zero"
fi
if bash "$IR/install.sh" --only check --skip dev >/dev/null 2>&1; then
  fail "install.sh must reject combining --only and --skip"
fi
# --only check runs only check + validate-configs and never calls sudo.
: >"$IR/ran"
PATH="$IR/bin:$PATH" bash "$IR/install.sh" --only check </dev/null >/dev/null 2>&1 \
  || fail "install.sh --only check failed"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "check validate-configs " ]] \
  || fail "install.sh --only check ran wrong scripts: $(cat "$IR/ran")"
# --only dev,check runs git + nvim + check AND authenticates sudo (git/nvim setup need sudo).
: >"$IR/ran"; : >"$IR/sudo.log"
PATH="$IR/bin-ok:$PATH" bash "$IR/install.sh" --only dev,check </dev/null >/dev/null 2>&1 \
  || fail "install.sh --only dev,check failed"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "git-setup nvim-setup check validate-configs " ]] \
  || fail "install.sh --only dev,check ran wrong scripts: $(cat "$IR/ran")"
grep -qx 'SUDO_V' "$IR/sudo.log" || fail "install.sh --only dev must call sudo -v"
# --skip with CONFIGURE=1 preserves configure unless configure itself is skipped.
: >"$IR/ran"
CONFIGURE=1 PATH="$IR/bin-ok:$PATH" bash "$IR/install.sh" \
  --skip packages,profile,flatpak,fonts,stow,aur,shell,desktop,dev,ai,apps,hardening </dev/null >/dev/null 2>&1 \
  || fail "install.sh CONFIGURE=1 --skip failed"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "configure check validate-configs " ]] \
  || fail "install.sh CONFIGURE=1 --skip dropped configure: $(cat "$IR/ran")"
: >"$IR/ran"
CONFIGURE=1 PATH="$IR/bin:$PATH" bash "$IR/install.sh" \
  --skip packages,profile,flatpak,fonts,stow,aur,shell,desktop,dev,ai,apps,hardening,configure </dev/null >/dev/null 2>&1 \
  || fail "install.sh CONFIGURE=1 --skip ...,configure failed"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "check validate-configs " ]] \
  || fail "install.sh --skip configure must skip configure: $(cat "$IR/ran")"
# GUI (--gui) with stub zenity: pick custom checklist → dev + check.
: >"$IR/ran"
printf 'custom\n' >"$IR/zmenu"
WAYLAND_DISPLAY=wayland-0 ZN_MENU="$IR/zmenu" ZN_PICK="dev check" \
  PATH="$CT/bin:$IR/bin-ok:$PATH" bash "$IR/install.sh" --gui </dev/null >/dev/null 2>&1 \
  || fail "install.sh --gui custom selection failed"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "git-setup nvim-setup check validate-configs " ]] \
  || fail "install.sh --gui ran wrong scripts: $(cat "$IR/ran")"
# INSTALL_UI=gui off-TTY and INSTALL_ALL=1 --gui both open GUI menu (Quit exits 0, no sudo).
: >"$IR/ran"
printf 'quit\n' >"$IR/zmenu"
WAYLAND_DISPLAY=wayland-0 INSTALL_UI=gui ZN_MENU="$IR/zmenu" \
  PATH="$CT/bin:$IR/bin:$PATH" bash "$IR/install.sh" </dev/null >/dev/null 2>&1 \
  || fail "INSTALL_UI=gui off-TTY must open GUI menu and exit 0 on Quit"
[[ ! -s $IR/ran ]] || fail "INSTALL_UI=gui quit must not run any scripts: $(cat "$IR/ran")"
printf 'quit\n' >"$IR/zmenu"
WAYLAND_DISPLAY=wayland-0 INSTALL_ALL=1 ZN_MENU="$IR/zmenu" \
  PATH="$CT/bin:$IR/bin:$PATH" bash "$IR/install.sh" --gui </dev/null >/dev/null 2>&1 \
  || fail "INSTALL_ALL=1 --gui must honor CLI --gui and exit 0 on Quit"
[[ ! -s $IR/ran ]] || fail "INSTALL_ALL=1 --gui quit must not run any scripts: $(cat "$IR/ran")"
# Plain menu loop: mistyped tag is warned and rejected; valid tag runs cleanly.
: >"$IR/ran"
_pm_out="$(printf '1\ncheck badtag\n1\ncheck\n' | PATH="$IR/bin:$PATH" \
  bash "$IR/install.sh" --plain 2>&1)" \
  || fail "install.sh --plain typo then check failed: $_pm_out"
grep -q 'Unknown section(s): badtag' <<<"$_pm_out" \
  || fail "install.sh --plain must warn on mistyped section: $_pm_out"
[[ "$(tr '\n' ' ' <"$IR/ran")" == "check validate-configs " ]] \
  || fail "install.sh --plain ran wrong scripts: $(cat "$IR/ran")"
unset -v IR _s _out _pm_out

# Desktop launcher for GUI installer exists and is valid, and zenity is in pacman.txt.
grep -qx 'zenity' "$ROOT/packages/pacman.txt" || fail "packages/pacman.txt must include zenity for --gui / Dotfiles Installer"
_desk="$ROOT/stow/applications/.local/share/applications/dotfiles-installer.desktop"
[[ -f $_desk ]] || fail "missing dotfiles-installer.desktop"
grep -q './install.sh --gui' "$_desk" || fail "dotfiles-installer.desktop must launch ./install.sh --gui"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$_desk" 2>&1 | grep -v ' hint: ' | grep -q . \
    && fail "desktop-file-validate dotfiles-installer.desktop failed"
fi
unset -v _desk

bash -n "$ROOT/provision/lib/progress.sh" || fail "bash -n progress.sh"
bash -n "$ROOT/provision/lib/ui-menu.sh" || fail "bash -n ui-menu.sh"
bash -n "$ROOT/provision/scripts/configure.sh" || fail "bash -n configure.sh"
bash -n "$ROOT/install.sh" || fail "bash -n install.sh"

echo "ok progress bars + Stage B wiring"
