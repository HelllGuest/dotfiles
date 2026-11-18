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
for _lab in "pacman packages" "machine profile" "stow dotfiles" "privacy hardener" "health check"; do
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

bash -n "$ROOT/scripts/lib/progress.sh" || fail "bash -n progress.sh"
bash -n "$ROOT/scripts/configure.sh" || fail "bash -n configure.sh"
bash -n "$ROOT/install.sh" || fail "bash -n install.sh"

echo "ok progress bars + Stage B wiring"
