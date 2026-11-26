#!/usr/bin/env bash
# system-setup.test.sh — system/scripts/system-setup.sh against a fake root (no sudo).
# Covers: stow file symlink, folded dir symlink, identical file, drifted file +
# backup, 700 parent dir, location-owned skip, AMDGPU LIBVA rewrite, retired
# makepkg drop-in, default DMI detection.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$REPO_ROOT/system/scripts/system-setup.sh"
SRC="$REPO_ROOT/system"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

# run_setup <root> [VAR=value ...]: run system-setup.sh, keep output in $out,
# record the exit status as a check instead of aborting under set -e.
run_setup() {
    local root="$1"; shift
    local rc=0
    out="$(env "$@" SYSTEM_ROOT="$root" bash "$SETUP" 2>&1)" || rc=$?
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
mkdir -p "$root/etc/systemd/system" "$root/etc/systemd" "$root/etc/modprobe.d" "$root/etc/udev/rules.d"
ln -s "$SRC/etc/systemd/system/virbr0-up.service" "$root/etc/systemd/system/virbr0-up.service"  # stowed file
ln -s "$SRC/etc/systemd/sleep.conf.d" "$root/etc/systemd/sleep.conf.d"    # folded dir
cp "$SRC/etc/udev/rules.d/61-thinkpad-charge-limit.rules" \
  "$root/etc/udev/rules.d/61-thinkpad-charge-limit.rules"                 # identical
echo "# drift" > "$root/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules"  # drifted
mkdir -m 700 "$root/etc/environment.d"                                    # hidden parent
# Foreign cmdline must stay untouched (installer / profile owns it).
mkdir -p "$root/etc/kernel"
echo "rd.luks.name=keep=cryptroot nvidia_drm.modeset=1" > "$root/etc/kernel/cmdline"

run_setup "$root" SYSTEM_IS_AMDGPU=0

check "stowed file replaced by regular file" \
    test -f "$root/etc/systemd/system/virbr0-up.service" -a ! -L "$root/etc/systemd/system/virbr0-up.service"
check "folded dir replaced by real dir" \
    test -d "$root/etc/systemd/sleep.conf.d" -a ! -L "$root/etc/systemd/sleep.conf.d"
check "folded dir content installed" \
    cmp -s "$SRC/etc/systemd/sleep.conf.d/s2idle.conf" "$root/etc/systemd/sleep.conf.d/s2idle.conf"
check "identical file not reported as installed" \
    bash -c '! grep -q "Installed /etc/udev/rules.d/61-thinkpad-charge-limit.rules" <<<"$1"' _ "$out"
check "drifted file installed" \
    cmp -s "$SRC/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules" \
      "$root/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules"
check "drifted file backed up" \
    bash -c 'grep -qx "# drift" "$1"/var/backups/dotfiles-system/*/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules' _ "$root"
check "700 parent dir made traversable" \
    test "$(mode_of "$root/etc/environment.d")" = 755
check "installed file mode 644" \
    test "$(mode_of "$root/etc/environment.d/99-wayland.conf")" = 644
check "perf sysctl installed 644 (linux-hardened defaults paranoid to 3)" \
    bash -c 'test "$(stat -c %a "$1")" = 644 && grep -qx "kernel.perf_event_paranoid = 2" "$1"' _ \
      "$root/etc/sysctl.d/99-perf.conf"
check "default: 99-wayland.conf keeps LIBVA_DRIVER_NAME=iHD" \
    grep -qx "LIBVA_DRIVER_NAME=iHD" "$root/etc/environment.d/99-wayland.conf"
check "foreign cmdline untouched" \
    grep -qx "rd.luks.name=keep=cryptroot nvidia_drm.modeset=1" "$root/etc/kernel/cmdline"
check "location-owned file skipped" \
    test ! -e "$root/etc/geolocation"
check "private home location (geolocation.local) never installed" \
    test ! -e "$root/etc/geolocation.local"

run_setup "$root" SYSTEM_IS_AMDGPU=0
check "second run is a no-op" \
    grep -q "System files already match" <<<"$out"

# lid logind drop-in always installed
check "lid logind drop-in installed" \
    cmp -s "$SRC/etc/systemd/logind.conf.d/thinkpad-lid.conf" \
      "$root/etc/systemd/logind.conf.d/thinkpad-lid.conf"

# AMD GPU host: 99-wayland.conf rewritten to LIBVA_DRIVER_NAME=radeonsi
root_amd="$work/root_amd"
mkdir -p "$root_amd"
run_setup "$root_amd" SYSTEM_IS_AMDGPU=1
check "amdgpu: 99-wayland.conf sets LIBVA_DRIVER_NAME=radeonsi" \
    grep -qx "LIBVA_DRIVER_NAME=radeonsi" "$root_amd/etc/environment.d/99-wayland.conf"
check "amdgpu: T14s touchpad wakeup rule installed" \
    cmp -s "$SRC/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules" \
      "$root_amd/etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules"
check "amdgpu: ThinkPad UPower CHARGE_LIMIT rule installed" \
    cmp -s "$SRC/etc/udev/rules.d/61-thinkpad-charge-limit.rules" \
      "$root_amd/etc/udev/rules.d/61-thinkpad-charge-limit.rules"

# renamed makepkg drop-in: our old 99-x86-64-v3.conf is retired, a foreign one kept
root_mk="$work/root_mk"
mkdir -p "$root_mk/etc/makepkg.conf.d"
cp "$SRC/etc/makepkg.conf.d/zz-x86-64-v3.conf" "$root_mk/etc/makepkg.conf.d/99-x86-64-v3.conf"
run_setup "$root_mk"
check "retired 99-x86-64-v3.conf removed" test ! -e "$root_mk/etc/makepkg.conf.d/99-x86-64-v3.conf"
check "zz-x86-64-v3.conf installed" \
    cmp -s "$SRC/etc/makepkg.conf.d/zz-x86-64-v3.conf" "$root_mk/etc/makepkg.conf.d/zz-x86-64-v3.conf"
root_mk2="$work/root_mk2"
mkdir -p "$root_mk2/etc/makepkg.conf.d"
printf 'CFLAGS+=" -march=x86-64-v3" # my own\n' >"$root_mk2/etc/makepkg.conf.d/99-x86-64-v3.conf"
run_setup "$root_mk2"
check "foreign file at the retired path is kept" test -f "$root_mk2/etc/makepkg.conf.d/99-x86-64-v3.conf"
root_mk3="$work/root_mk3"
mkdir -p "$root_mk3/etc/makepkg.conf.d"
ln -s "$work/gone/99-x86-64-v3.conf" "$root_mk3/etc/makepkg.conf.d/99-x86-64-v3.conf"
run_setup "$root_mk3"
check "dangling stow symlink at the retired path removed" \
    test ! -L "$root_mk3/etc/makepkg.conf.d/99-x86-64-v3.conf"

# makepkg sources conf.d in glob order: after pacman's rust.conf (which sets
# RUSTFLAGS outright) the effective flags must still target x86-64-v3.
mkd="$work/mkconf.d"
mkdir -p "$mkd"
printf 'RUSTFLAGS="-C force-frame-pointers=yes"\n' >"$mkd/rust.conf"
cp "$SRC/etc/makepkg.conf.d/zz-x86-64-v3.conf" "$mkd/"
eff="$(bash -c 'for f in "$1"/*.conf; do source "$f"; done; printf %s "$RUSTFLAGS"' _ "$mkd")"
check "x86-64-v3 drop-in wins over pacman rust.conf (RUSTFLAGS=$eff)" \
    test "$eff" = "-C force-frame-pointers=yes -C target-cpu=x86-64-v3"

# no override: real DMI check (lib/dmi.sh) must run cleanly on any host
root5="$work/root5"
mkdir -p "$root5"
run_setup "$root5" -u SYSTEM_IS_AMDGPU

if (( fails )); then
    echo "$fails test(s) failed" >&2
    exit 1
fi
echo "all system-setup tests passed"
