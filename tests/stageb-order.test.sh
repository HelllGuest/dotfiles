#!/usr/bin/env bash
# Stage B ordering and first-boot edge cases: Rust toolchain on a rustup host
# (paru), configure.sh after what its modules need, one extension pass, user
# unit reload, and the headless VM harness.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
I="$ROOT/install.sh"
line() { grep -n -m1 -F -- "$1" "$I" | cut -d: -f1; }

# --- ensure_rust_toolchain: a fresh rustup has no default -------------------------
mkdir -p "$T/bin"
cat >"$T/bin/cargo" <<EOF
#!/bin/sh
[ -f "$T/default-set" ] && { echo "cargo 1.0"; exit 0; }
echo "error: rustup could not choose a version of cargo to run" >&2; exit 1
EOF
cat >"$T/bin/rustup" <<EOF
#!/bin/sh
echo "rustup \$*" >>"$T/rustup.log"
[ "\$1 \$2" = "default stable" ] && : >"$T/default-set"
EOF
chmod +x "$T/bin/"*
# shellcheck source=scripts/lib/rust-toolchain.sh
source "$ROOT/scripts/lib/rust-toolchain.sh"
PATH="$T/bin:$PATH" ensure_rust_toolchain >/dev/null || fail "ensure_rust_toolchain must set a default on a fresh rustup"
grep -qx 'rustup default stable' "$T/rustup.log" || fail "must run rustup default stable"
: >"$T/rustup.log"
PATH="$T/bin:$PATH" ensure_rust_toolchain >/dev/null || fail "a working cargo must pass"
[[ ! -s $T/rustup.log ]] || fail "a working toolchain must not be changed"
if PATH="$T/none:/usr/bin/false-only" ensure_rust_toolchain >/dev/null 2>&1; then
  fail "no cargo and no rustup must fail"
fi
# paru is built only after the toolchain is ensured; ghidra-cli uses the same helper.
B="$ROOT/scripts/bootstrap-aur.sh"
(( $(grep -n -m1 'ensure_rust_toolchain' "$B" | cut -d: -f1) < $(grep -n -m1 'makepkg -si' "$B" | cut -d: -f1) )) \
  || fail "bootstrap-aur.sh must ensure the Rust toolchain before building paru"
grep -q 'ensure_rust_toolchain' "$ROOT/scripts/install-ghidra-cli.sh" || fail "install-ghidra-cli.sh must use the shared helper"
! grep -q 'rustup default stable' "$ROOT/scripts/install-ghidra-cli.sh" || fail "install-ghidra-cli.sh must not keep its own copy"

# --- install.sh order: configure.sh after stow, fnm, AI steps and extensions ----
cfg="$(line 'CONFIGURE_ONCE=1 bash scripts/configure.sh')"
[[ -n $cfg ]] || fail "install.sh must still run configure.sh"
for dep in 'stow -R -t "$HOME"' 'fnm install 22' 'run_step "Coding agents"' 'run_step "GNOME extensions"'; do
  d="$(line "$dep")"
  [[ -n $d ]] || fail "install.sh: '$dep' not found"
  (( d < cfg )) || fail "configure.sh (line $cfg) must run after '$dep' (line $d)"
done
(( cfg < $(line 'bash scripts/privacy-hardener.sh') )) || fail "configure.sh must run before privacy + check.sh"

# --- one extension pass, recorded by install.sh ---------------------------------
grep -q 'env SKIP_GNOME_EXTENSIONS=1 bash scripts/gnome-session-setup.sh' "$I" \
  || fail "install.sh must stop gnome-session-setup.sh from fetching/enabling extensions itself"
grep -q 'SKIP_GNOME_EXTENSIONS:-0} != 1' "$ROOT/scripts/gnome-session-setup.sh" \
  || fail "gnome-session-setup.sh must honour SKIP_GNOME_EXTENSIONS=1"
[[ $(grep -cE '(bash|run_step .*) scripts/(install-dash2dock|fetch-gnome-extensions)\.sh' "$I") -eq 1 ]] \
  || fail "install.sh must download extensions exactly once"
(( $(line 'bash scripts/fetch-gnome-extensions.sh') < $(line 'run_step "GNOME extensions"') )) \
  || fail "extension downloads must come before the enable pass"

# --- user unit reload before enable ------------------------------------------------
for f in "$I" "$ROOT/stow-only.sh"; do
  r="$(grep -n -m1 'systemctl --user daemon-reload' "$f" | cut -d: -f1)"
  e="$(grep -n -m1 'enable --now tmp-semgrep-cleanup.timer' "$f" | cut -d: -f1)"
  [[ -n $r && -n $e ]] && (( r <= e )) || fail "${f##*/}: daemon-reload must precede enabling tmp-semgrep-cleanup.timer"
done

# --- headless VM harness --------------------------------------------------------
grep -q '"${SKIP_THEME:-0}" = 1' "$I" || fail "install.sh must offer SKIP_THEME=1"
G="$ROOT/scripts/vm-stageb-guest.sh"
grep -qx 'export SKIP_THEME=1' "$G" || fail "headless guest must skip the theme (no GNOME Shell)"
grep -q 'dbus-run-session -- bash ./install.sh' "$G" || fail "headless guest must give install.sh a session bus"
grep -q '\[\[ -f $WORK/OVMF_VARS.fd \]\] || cp' "$ROOT/scripts/vm-stageb-run.sh" \
  || fail "vm-stageb-run.sh must keep Stage A's OVMF vars (boot entry)"

echo "PASS: stageb-order.test.sh"
