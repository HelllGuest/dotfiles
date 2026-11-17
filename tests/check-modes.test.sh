#!/usr/bin/env bash
# check.sh modes: --stage-a runs the installer's host-check.sh (strict on the
# T14s Gen 3 AMD, informational elsewhere), bad args exit 2, the default mode
# runs the Stage A follow-ups and stays what install.sh calls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Isolated copy: no sibling ~/t14s-arch-install, fake DMI, no sudo.
mkdir -p "$T/repo/scripts/lib" "$T/home" "$T/bin" "$T/inst/tests" "$T/dmi"
cp "$ROOT/scripts/check.sh" "$T/repo/scripts/"
cp "$ROOT/scripts/lib/dmi.sh" "$T/repo/scripts/lib/"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/sudo"
chmod +x "$T/bin/sudo"
hc_exit() { printf '#!/bin/bash\necho "HOSTCHECK ran"\nexit %s\n' "$1" >"$T/inst/tests/host-check.sh"; }
dmi() { printf '%s\n' "$1" >"$T/dmi/product_name"; touch "$T/dmi/product_family" "$T/dmi/product_version" "$T/dmi/product_sku"; }
run() {
  env HOME="$T/home" PATH="$T/bin:$PATH" DMI_SYSFS_ROOT="$T/dmi" "$@" \
    bash "$T/repo/scripts/check.sh" --stage-a 2>&1
}

rc=0; bash "$T/repo/scripts/check.sh" --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown option must exit 2 (got $rc)"
bash "$T/repo/scripts/check.sh" --help | grep -q -- '--stage-a' || fail "--help must document --stage-a"

dmi 21CRS1PU00
hc_exit 0
out="$(run T14S_INSTALLER_DIR="$T/inst")" || fail "T14s + passing host-check must exit 0: $out"
[[ $out == *"HOSTCHECK ran"* && $out == *"✓ Stage A host-check passed"* ]] || fail "pass output: $out"
[[ $out == *"root-only Stage A checks skipped"* ]] || fail "without cached sudo the root pass must be hinted"

hc_exit 1
rc=0; out="$(run T14S_INSTALLER_DIR="$T/inst")" || rc=$?
[[ $rc -eq 1 && $out == *"✗ Stage A host-check reported FAIL"* ]] || fail "T14s FAIL must fail check.sh (rc=$rc): $out"

dmi 20SUS0R700
out="$(run T14S_INSTALLER_DIR="$T/inst")" || fail "non-T14s host-check FAIL must be informational: $out"
[[ $out == *"informational"* ]] || fail "non-T14s must say informational: $out"

rc=0; out="$(run T14S_INSTALLER_DIR="$T/nowhere")" || rc=$?
[[ $rc -eq 1 && $out == *"git clone https://github.com/HelllGuest/t14s-arch-install"* ]] \
  || fail "missing installer checkout must fail with a clone hint (rc=$rc): $out"

# Default mode keeps install.sh's contract and includes the follow-ups.
grep -q 'bash scripts/check.sh \\' "$ROOT/install.sh" || fail "install.sh must still call check.sh (default mode)"
grep -qx 'stage_a_followups' "$ROOT/scripts/check.sh" || fail "default mode must run stage_a_followups"
grep -q 'gdm-shell-theme.sh" status' "$ROOT/scripts/check.sh" || fail "check.sh must verify the GDM greeter theme"

echo "PASS: check-modes.test.sh"
