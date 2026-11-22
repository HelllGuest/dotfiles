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

# AUR after system-setup (makepkg x86-64-v3); skills before Headroom; no root; no --adopt
grep -qE 'EUID.*-eq 0' "$I" || fail "install.sh must reject root (EUID == 0)"
grep -qE 'EUID.*-eq 0' "$ROOT/stow-only.sh" || fail "stow-only.sh must reject root (EUID == 0)"
(( $(line 'bash ../scripts/system-setup.sh') < $(line 'run_step "AUR install"') )) \
  || fail "AUR install must run after system-setup.sh (makepkg.conf.d v3)"
(( $(line 'run_step "Agent skills pre-sync"') < $(line 'run_step "Headroom setup"') )) \
  || fail "sync-agent-skills must run before headroom-setup"
! grep -qE 'stow[[:space:]].*--adopt' "$ROOT/scripts/gnome-session-setup.sh" \
  || fail "gnome-session-setup.sh must not stow --adopt (overwrites tracked files)"

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

# HEADLESS_OK must allow only headless-expected t14s-selftest items (bluetooth/pipewire).
_hok="$(sed -n "s/^HEADLESS_OK='\(.*\)'$/\1/p" "$G")"
[[ -n $_hok ]] || fail "could not read HEADLESS_OK from vm-stageb-guest.sh"
grep -qE "$_hok" <<<'✗ t14s-selftest: FAIL bluetooth FAIL pipewire ' \
  || fail "HEADLESS_OK must accept bluetooth/pipewire selftest fails on headless QEMU"
! grep -qE "$_hok" <<<'✗ t14s-selftest: FAIL bluetooth FAIL firewalld ' \
  || fail "HEADLESS_OK must reject real selftest fails (firewalld)"

# network-dns-setup.sh skips bridge/tun/vpn (virbr0/docker0 break ipv6.dns)
grep -qE 'bridge\|tun\|tap\|loopback\|wireguard\|vpn' "$ROOT/scripts/network-dns-setup.sh" \
  || fail "network-dns-setup.sh must skip bridge/tun/vpn connection types"

# network-dns-setup.sh: retry via sudo on polkit denial; do not sudo on other errors.
(
  _nt="$(mktemp -d)"
  trap 'rm -rf "$_nt"' EXIT
  mkdir -p "$_nt/bin"
  cat >"$_nt/bin/nmcli" <<'STUB'
#!/bin/sh
if [ "$1" = "-t" ]; then
  printf 'Wired connection 1\nlo\n'
  exit 0
fi
if [ "${VIA_SUDO:-0}" = 1 ]; then
  printf 'sudo-nmcli %s\n' "$*" >>"$NM_LOG"
  exit 0
fi
if [ "${NM_ERR:-auth}" = auth ]; then
  echo "Error: Failed to modify connection 'Wired connection 1': Insufficient privileges" >&2
  exit 10
fi
echo "Error: unknown connection 'bad'" >&2
exit 10
STUB
  cat >"$_nt/bin/sudo" <<'STUB'
#!/bin/sh
printf 'sudo-called\n' >>"$NM_LOG"
VIA_SUDO=1 exec "$@"
STUB
  chmod +x "$_nt/bin/nmcli" "$_nt/bin/sudo"
  NM_LOG="$_nt/auth.log" PATH="$_nt/bin:$PATH" \
    bash "$ROOT/scripts/network-dns-setup.sh" >/dev/null \
    || fail "network-dns-setup.sh must retry with sudo on Insufficient privileges"
  grep -q 'sudo-nmcli connection modify Wired connection 1' "$_nt/auth.log" \
    || fail "network-dns-setup.sh did not run sudo nmcli modify"
  grep -q 'sudo-nmcli connection up Wired connection 1' "$_nt/auth.log" \
    || fail "network-dns-setup.sh did not run sudo nmcli up"
  : >"$_nt/other.log"
  if NM_ERR=other NM_LOG="$_nt/other.log" PATH="$_nt/bin:$PATH" \
    bash "$ROOT/scripts/network-dns-setup.sh" bad >/dev/null 2>&1; then
    fail "network-dns-setup.sh must fail on non-privilege nmcli error"
  fi
  [[ ! -s "$_nt/other.log" ]] || fail "network-dns-setup.sh must not invoke sudo on non-privilege error"
)

echo "PASS: stageb-order.test.sh"
