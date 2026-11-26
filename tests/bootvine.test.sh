#!/usr/bin/env bash
# bootvine boot screen: official package, stage 2 + shutdown units, no initrd hook.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -qx 'bootvine' "$ROOT/packages/pacman.txt" || fail "pacman.txt must include official bootvine"
! grep -q 'bootvine' "$ROOT/packages/aur.txt" || fail "aur.txt must not build bootvine-git (official package exists)"
# The initrd hook would put bootvine in front of the LUKS prompt; keep it out.
# (check.sh / check.d only detect it in /etc/mkinitcpio.conf, so they are excluded.)
! grep -rn --exclude-dir=.git --exclude-dir=check.d \
    --exclude-dir=logs --exclude-dir=History --exclude-dir=Cache --exclude-dir='Code Cache' --exclude-dir=GPUCache \
    --exclude=bootvine.test.sh --exclude=CHANGELOG.md --exclude=README.md \
    --exclude=check.sh \
    -e 'HOOKS=.*sd-bootvine' -e 'install --initrd' "$ROOT" \
  || fail "repo must not add the sd-bootvine initrd hook"

# Run the install.sh step with stub pacman/sudo/systemctl.
block="$(awk '/^# 1\.04 Boot screen/{f=1} f&&/^# 1\.05 /{exit} f' "$ROOT/install.sh")"
[[ -n $block ]] || fail "could not find install.sh step 1.04 (bootvine)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat >"$T/bin/pacman" <<'STUB'
#!/bin/sh
[ "$1" = -Q ] && [ "$2" = bootvine ] && [ "${BV_INSTALLED:-0}" = 1 ]
STUB
cat >"$T/bin/sudo" <<'STUB'
#!/bin/sh
exec "$@"
STUB
cat >"$T/bin/systemctl" <<STUB
#!/bin/sh
echo "\$*" >>"$T/calls"
exit \${BV_SYSTEMCTL_RC:-0}
STUB
chmod +x "$T"/bin/*
# install.sh helpers (fail_step/run_step) + a summary line of recorded failures.
helpers="$(awk '/^INSTALL_FAILED=0$/{f=1} f&&/^echo "Starting installation..."$/{exit} f' "$ROOT/install.sh")"
[[ -n $helpers ]] || fail "install.sh helper block not found"
run() { PATH="$T/bin:$PATH" bash -c "$helpers
$block
echo \"FAILED=\$INSTALL_FAILED\"" 2>&1; }

BV_INSTALLED=1 run >/dev/null
[[ $(cat "$T/calls") == 'enable bootvine.service bootvine-shutdown.service' ]] \
  || fail "must enable both bootvine units (shutdown unit has its own [Install]): $(cat "$T/calls")"
grep -q -- '--now' "$T/calls" && fail "must not start bootvine mid-session (takes tty12 at boot)"
rm -f "$T/calls"

out="$(BV_INSTALLED=0 run)"
[[ ! -e $T/calls ]] || fail "must not touch systemctl when bootvine is not installed"
grep -q 'bootvine not installed' <<<"$out" && grep -qx 'FAILED=1' <<<"$out" \
  || fail "missing bootvine must be a recorded failure, not a silent skip: $out"

out="$(BV_INSTALLED=1 BV_SYSTEMCTL_RC=1 run)" || fail "enable failure must not abort install.sh"
grep -q 'bootvine enable failed' <<<"$out" && grep -qx 'FAILED=1' <<<"$out" \
  || fail "enable failure must be recorded: $out"

# Upgrade from AUR bootvine-git: both ship /usr/bin/bootvine with no conflicts=
# metadata, so pacman -S bootvine would abort the whole pacman.txt transaction.
pkgblk="$(awk '/^if \[ -f "packages\/pacman.txt" \]; then$/{f=1} f; f&&/^fi$/{exit}' "$ROOT/install.sh")"
[[ -n $pkgblk ]] || fail "install.sh pacman.txt block not found"
mkdir -p "$T/pk/bin" "$T/pk/repo/packages" "$T/pk/repo/provision/lib"
cp "$ROOT/provision/lib/pkg-lists.sh" "$ROOT/provision/lib/dmi.sh" "$T/pk/repo/provision/lib/"
printf '%s\n' bash bootvine zsh >"$T/pk/repo/packages/pacman.txt"
cat >"$T/pk/bin/sudo" <<'STUB'
#!/bin/sh
exec "$@"
STUB
cat >"$T/pk/bin/pacman" <<'STUB'
#!/usr/bin/env bash
case $1 in
  -Q) [[ -n ${PK_GIT:-} && $2 == bootvine-git ]]; exit ;;
  -R) echo "$*" >>"$PK_RM"; exit "${PK_RM_RC:-0}" ;;
  -S|-Syu) while [[ $1 != -- ]]; do shift; done; shift; printf '%s\n' "$@" >"$PK_OUT" ;;
esac
STUB
chmod +x "$T/pk/bin/sudo" "$T/pk/bin/pacman"
pk() { # git_installed rm_rc tag
  (cd "$T/pk/repo" && PK_GIT=$1 PK_RM_RC=$2 PK_RM="$T/pk/$3.rm" PK_OUT="$T/pk/$3.out" \
    PATH="$T/pk/bin:$PATH" bash -c "$helpers
$pkgblk
echo \"FAILED=\$INSTALL_FAILED\"" 2>&1) </dev/null
}
out="$(pk 1 0 swap)"
grep -qx 'FAILED=0' <<<"$out" || fail "upgrade from bootvine-git must not fail: $out"
[[ $(cat "$T/pk/swap.rm") == '-R --noconfirm bootvine-git' ]] || fail "must remove bootvine-git before installing bootvine"
grep -qx bootvine "$T/pk/swap.out" || fail "official bootvine must still be installed after the swap"
out="$(pk 1 1 rmfail)" || fail "failed bootvine-git removal must not abort the package step: $out"
grep -q 'could not remove bootvine-git' <<<"$out" && grep -qx 'FAILED=1' <<<"$out" \
  || fail "failed removal must be a recorded failure: $out"
! grep -qx bootvine "$T/pk/rmfail.out" || fail "failed removal must skip bootvine (would hit conflicting files)"
grep -qx zsh "$T/pk/rmfail.out" || fail "failed removal must still install the other packages"
out="$(pk "" 0 fresh)"
grep -qx 'FAILED=0' <<<"$out" || fail "fresh host package step failed: $out"
[[ ! -e $T/pk/fresh.rm ]] || fail "must not call pacman -R without bootvine-git"
grep -qx bootvine "$T/pk/fresh.out" || fail "fresh host must install bootvine"

echo "PASS: bootvine.test.sh"
