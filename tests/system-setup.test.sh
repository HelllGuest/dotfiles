#!/usr/bin/env bash
# system-setup.test.sh — scripts/system-setup.sh against a fake root (no sudo).
# Covers: stow file symlink, folded dir symlink, identical file, drifted file +
# backup, 700 parent dir, cmdline UUID rewrite / skip, location-owned skip,
# X1-only files on non-X1 hardware, default DMI detection.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$REPO_ROOT/scripts/system-setup.sh"
SRC="$REPO_ROOT/stow/system"
UUID=11111111-2222-3333-4444-555555555555

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

# run_setup <root> [VAR=value ...]: run system-setup.sh, keep output in $out,
# record the exit status as a check instead of aborting under set -e.
run_setup() {
    local root="$1"; shift
    local rc=0
    out="$(env "$@" SYSTEM_ROOT="$root" PROC_CMDLINE="$work/cmdline" bash "$SETUP" 2>&1)" || rc=$?
    check "system-setup.sh exits 0 (${root##*/})" test "$rc" -eq 0
}

check() { # $1 description, rest: test command
    local desc="$1"; shift
    if "$@"; then
        echo "ok   $desc"
    else
        echo "FAIL $desc"
        fails=$((fails + 1))
    fi
}

mode_of() { stat -c '%a' "$1"; }

# fake root with every pre-existing state system-setup.sh must handle
root="$work/root"
mkdir -p "$root/etc/kernel" "$root/etc/ufw" "$root/etc/systemd" "$root/dev/disk/by-uuid"
touch "$root/dev/disk/by-uuid/$UUID"
echo "rd.luks.name=$UUID=cryptroot root=/dev/mapper/cryptroot" > "$work/cmdline"
ln -s "$SRC/etc/ufw/before.rules" "$root/etc/ufw/before.rules"            # stowed file
ln -s "$SRC/etc/systemd/sleep.conf.d" "$root/etc/systemd/sleep.conf.d"    # folded dir
cp "$SRC/etc/modprobe.d/i915.conf" "$work/i915"; mkdir -p "$root/etc/modprobe.d"
cp "$work/i915" "$root/etc/modprobe.d/i915.conf"                          # identical
mkdir -p "$root/etc/udev/rules.d"
echo "# drift" > "$root/etc/udev/rules.d/72-fingerprint-disable.rules"   # drifted
mkdir -m 700 "$root/etc/environment.d"                                    # hidden parent
echo "rd.luks.name=old=cryptroot" > "$root/etc/kernel/cmdline"

run_setup "$root" SYSTEM_IS_X1=1

check "stowed file replaced by regular file" \
    test -f "$root/etc/ufw/before.rules" -a ! -L "$root/etc/ufw/before.rules"
check "folded dir replaced by real dir" \
    test -d "$root/etc/systemd/sleep.conf.d" -a ! -L "$root/etc/systemd/sleep.conf.d"
check "folded dir content installed" \
    cmp -s "$SRC/etc/systemd/sleep.conf.d/thinkpad-x1.conf" "$root/etc/systemd/sleep.conf.d/thinkpad-x1.conf"
check "identical file not reported as installed" \
    bash -c '! grep -q "Installed /etc/modprobe.d/i915.conf" <<<"$1"' _ "$out"
check "drifted file installed" \
    cmp -s "$SRC/etc/udev/rules.d/72-fingerprint-disable.rules" "$root/etc/udev/rules.d/72-fingerprint-disable.rules"
check "drifted file backed up" \
    bash -c 'grep -qx "# drift" "$1"/var/backups/dotfiles-system/*/etc/udev/rules.d/72-fingerprint-disable.rules' _ "$root"
check "700 parent dir made traversable" \
    test "$(mode_of "$root/etc/environment.d")" = 755
check "installed file mode 644" \
    test "$(mode_of "$root/etc/environment.d/99-wayland.conf")" = 644
check "cmdline gets booted UUID" \
    grep -q "rd.luks.name=$UUID=cryptroot" "$root/etc/kernel/cmdline"
check "location-owned file skipped" \
    test ! -e "$root/etc/geolocation"

run_setup "$root" SYSTEM_IS_X1=1
check "second run is a no-op" \
    grep -q "System files already match" <<<"$out"

# unconfirmed UUID: cmdline must be left alone
root2="$work/root2"
mkdir -p "$root2/etc/kernel"
echo "keep" > "$root2/etc/kernel/cmdline"
run_setup "$root2" SYSTEM_IS_X1=1
check "cmdline skipped when UUID device missing" \
    grep -qx keep "$root2/etc/kernel/cmdline"

# non-X1 hardware (e.g. P15 with nvidia_drm.modeset=1): X1-only files skipped
root3="$work/root3"
mkdir -p "$root3/etc/kernel" "$root3/etc/modprobe.d" "$root3/etc/systemd" "$root3/dev/disk/by-uuid"
touch "$root3/dev/disk/by-uuid/$UUID"
echo "rd.luks.name=$UUID=cryptroot nvidia_drm.modeset=1" > "$root3/etc/kernel/cmdline"
ln -s "$SRC/etc/modprobe.d/i915.conf" "$root3/etc/modprobe.d/i915.conf"      # stale X1 link
ln -s "$SRC/etc/systemd/sleep.conf.d" "$root3/etc/systemd/sleep.conf.d"      # folded X1 dir
run_setup "$root3" SYSTEM_IS_X1=0
check "non-X1: own cmdline untouched" \
    grep -q "nvidia_drm.modeset=1" "$root3/etc/kernel/cmdline"
check "non-X1: stale X1 i915 symlink removed" \
    test ! -e "$root3/etc/modprobe.d/i915.conf" -a ! -L "$root3/etc/modprobe.d/i915.conf"
check "non-X1: folded X1 sleep dir removed" \
    test ! -e "$root3/etc/systemd/sleep.conf.d"
check "non-X1: X1 fingerprint rule not installed" \
    test ! -e "$root3/etc/udev/rules.d/72-fingerprint-disable.rules"
check "non-X1: generic files still installed" \
    test -f "$root3/etc/ufw/before.rules"

# non-X1 with a stowed cmdline: materialized (content kept), never deleted
root4="$work/root4"
mkdir -p "$root4/etc/kernel"
ln -s "$SRC/etc/kernel/cmdline" "$root4/etc/kernel/cmdline"
run_setup "$root4" SYSTEM_IS_X1=0
check "non-X1: stowed cmdline materialized as real file" \
    test -f "$root4/etc/kernel/cmdline" -a ! -L "$root4/etc/kernel/cmdline"
check "non-X1: materialized cmdline keeps content" \
    cmp -s "$SRC/etc/kernel/cmdline" "$root4/etc/kernel/cmdline"

# no override: real DMI check (lib/dmi.sh) must run cleanly on any host
root5="$work/root5"
mkdir -p "$root5"
run_setup "$root5" -u SYSTEM_IS_X1   # default: real DMI check via lib/dmi.sh

if (( fails )); then
    echo "$fails test(s) failed" >&2
    exit 1
fi
echo "all system-setup tests passed"
