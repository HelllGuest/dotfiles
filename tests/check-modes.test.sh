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
mkdir -p "$T/repo/scripts" "$T/repo/provision/lib" "$T/home" "$T/bin" "$T/inst/tests" "$T/dmi"
cp "$ROOT/scripts/check.sh" "$T/repo/scripts/"
cp -r "$ROOT/scripts/check.d" "$T/repo/scripts/"
cp "$ROOT/provision/lib/dmi.sh" "$T/repo/provision/lib/"
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
rc=0; bash "$T/repo/scripts/check.sh" --post --extra >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "extra arg to --post must exit 2 (got $rc)"
bash "$T/repo/scripts/check.sh" --help | grep -q -- '--stage-a' || fail "--help must document --stage-a"
bash "$T/repo/scripts/check.sh" --help | grep -q -- '--drift' || fail "--help must document --drift"
bash "$T/repo/scripts/check.sh" --help | grep -q -- '--fix' || fail "--help must document --fix"

# --drift: detects untracked packages, supports --strict, and flags broken stow symlinks
cp "$ROOT/scripts/drift.sh" "$T/repo/scripts/"
cp "$ROOT/provision/lib/pkg-lists.sh" "$T/repo/provision/lib/"
mkdir -p "$T/repo/packages" "$T/repo/stow/demo"
printf '%s\n' pkg-a >"$T/repo/packages/pacman.txt"
printf '%s\n' aur-a >"$T/repo/packages/aur.txt"
printf '%s\n' org.ok.App >"$T/repo/packages/flatpak.txt"
cat >"$T/bin/pacman" <<'EOF'
#!/bin/sh
case "$1" in
  -Qqen) printf '%s\n' pkg-a pkg-extra ;;
  -Qqem) printf '%s\n' aur-a aur-extra ;;
esac
EOF
cat >"$T/bin/flatpak" <<'EOF'
#!/bin/sh
[ "$1" = list ] && printf '%s\n' org.ok.App org.extra.App
EOF
chmod +x "$T/bin/pacman" "$T/bin/flatpak"
out="$(env HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/repo/scripts/check.sh" --drift 2>&1)" \
  || fail "--drift with only package hints must exit 0: $out"
grep -q 'pkg-extra' <<<"$out" || fail "--drift must report untracked native pkg: $out"
grep -q 'aur-extra' <<<"$out" || fail "--drift must report untracked AUR pkg: $out"
grep -q 'org.extra.App' <<<"$out" || fail "--drift must report untracked Flatpak: $out"
rc=0; out="$(env HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/repo/scripts/check.sh" --drift --strict 2>&1)" || rc=$?
[[ $rc -eq 1 ]] || fail "--drift --strict must forward --strict and exit 1 on package drift (rc=$rc): $out"
ln -s "$T/repo/stow/demo/gone" "$T/home/broken-dot"
rc=0; out="$(env HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/repo/scripts/check.sh" --drift 2>&1)" || rc=$?
[[ $rc -eq 1 && $out == *"broken stow symlink"* ]] || fail "--drift must fail on broken stow symlink (rc=$rc): $out"
rm -f "$T/home/broken-dot"

# --fix: runs safe idempotent fixers before --post checks, skips browser-hardening without cached sudo
mkdir -p "$T/repo/security/scripts"
cat >"$T/repo/security/scripts/browser-hardening.sh" <<EOF
#!/bin/sh
echo "FIX_BROWSER_RAN" >>"$T/fix.log"
EOF
chmod +x "$T/repo/security/scripts/browser-hardening.sh"
printf '#!/bin/sh\necho "FIX_AGENTSYNC_RAN" >>"%s/fix.log"\n' "$T" >"$T/bin/agentsync"
chmod +x "$T/bin/agentsync"
rm -f "$T/repo/scripts/check.d/"*.sh
printf 'echo "POST_CHECK_RAN"\n' >"$T/repo/scripts/check.d/10-stub.sh"
out="$(env HOME="$T/home" PATH="$T/bin:$PATH" DMI_SYSFS_ROOT="$T/dmi" T14S_SELFTEST_BIN="$T/none" bash "$T/repo/scripts/check.sh" --fix 2>&1)" \
  || fail "--fix must pass when post checks pass: $out"
grep -qx 'FIX_AGENTSYNC_RAN' "$T/fix.log" || fail "--fix must run agentsync: $(cat "$T/fix.log" 2>/dev/null)"
grep -qx 'FIX_BROWSER_RAN' "$T/fix.log" || fail "--fix must run browser-hardening.sh (user layer without sudo)"
grep -q 'user layer only' <<<"$out" || fail "--fix without cached sudo must note user layer only: $out"
grep -q 'POST_CHECK_RAN' <<<"$out" || fail "--fix must re-run post checks: $out"
# With cached sudo, browser-hardening.sh runs with full /etc access
printf '#!/bin/sh\nexit 0\n' >"$T/bin/sudo"
chmod +x "$T/bin/sudo"
: >"$T/fix.log"
out="$(env HOME="$T/home" PATH="$T/bin:$PATH" DMI_SYSFS_ROOT="$T/dmi" T14S_SELFTEST_BIN="$T/none" bash "$T/repo/scripts/check.sh" --fix 2>&1)" \
  || fail "--fix with cached sudo must pass: $out"
grep -qx 'FIX_BROWSER_RAN' "$T/fix.log" || fail "--fix with cached sudo must run browser-hardening.sh"
! grep -q 'user layer only' <<<"$out" || fail "--fix with cached sudo must not restrict to user layer: $out"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/sudo"
chmod +x "$T/bin/sudo"
rm -f "$T/bin/pacman" "$T/bin/flatpak" "$T/bin/agentsync" "$T/repo/security/scripts/browser-hardening.sh"
cp -r "$ROOT/scripts/check.d" "$T/repo/scripts/"

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
[[ $rc -eq 1 && $out == *"stage-a not found"* && $out == *"STAGE_A_DIR"* ]] \
  || fail "missing installer dir must fail with STAGE_A_DIR hint (rc=$rc): $out"

# STAGE_A_DIR alias (pass + missing)
dmi 21CRS1PU00
hc_exit 0
out="$(run STAGE_A_DIR="$T/inst")" || fail "STAGE_A_DIR pass failed: $out"
[[ $out == *"HOSTCHECK ran"* && $out == *"✓ Stage A host-check passed"* ]] || fail "STAGE_A_DIR pass output: $out"
rc=0; out="$(run STAGE_A_DIR="$T/nowhere")" || rc=$?
[[ $rc -eq 1 && $out == *"stage-a not found"* ]] || fail "STAGE_A_DIR missing must fail (rc=$rc): $out"

# Default in-repo stage-a/ resolution (no STAGE_A_DIR / T14S_INSTALLER_DIR needed)
mkdir -p "$T/repo/stage-a/tests"
printf '#!/bin/bash\necho "INREPO HOSTCHECK ran"\nexit 0\n' >"$T/repo/stage-a/tests/host-check.sh"
out="$(run)" || fail "in-repo stage-a host-check must pass without STAGE_A_DIR: $out"
[[ $out == *"INREPO HOSTCHECK ran"* && $out == *"✓ Stage A host-check passed"* ]] \
  || fail "in-repo host-check output mismatch: $out"

# Default mode keeps install.sh's contract and includes the follow-ups.
grep -q 'bash scripts/check.sh \\' "$ROOT/install.sh" || fail "install.sh must still call check.sh (default mode)"
grep -qx 'stage_a_followups' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh || fail "default mode must run stage_a_followups"
grep -q 'theme-setup.sh" --check' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh || fail "check.sh must verify the theme (stock Adwaita via theme-setup.sh --check)"

echo "PASS: check-modes.test.sh"
