#!/usr/bin/env bash
# Thin Stage A wrappers → stage-a/install.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/provision/lib/stage-a-handoff.sh" \
  "$ROOT/scripts/arch-install.sh" \
  "$ROOT/scripts/arch-install-t14s.sh" \
  "$ROOT/scripts/arch-install-p15.sh"
do
  [[ -f $f ]] || fail "missing $f"
  bash -n "$f" || fail "bash -n $f"
done
[[ -x $ROOT/scripts/arch-install.sh ]] || fail "arch-install.sh not executable"
[[ -x $ROOT/scripts/arch-install-t14s.sh ]] || fail "arch-install-t14s.sh not executable"
[[ -x $ROOT/scripts/arch-install-p15.sh ]] || fail "arch-install-p15.sh not executable"

# Wrappers must stay thin (no embedded LUKS/pacstrap body)
for w in arch-install.sh arch-install-t14s.sh arch-install-p15.sh; do
  lines=$(wc -l <"$ROOT/scripts/$w")
  (( lines < 80 )) || fail "$w too fat ($lines lines) — must hand off to t14s-arch-install"
  grep -q 'stage_a_handoff' "$ROOT/scripts/$w" \
    || fail "$w must call stage_a_handoff"
  grep -qE 'cryptsetup|pacstrap|mkfs.btrfs' "$ROOT/scripts/$w" \
    && fail "$w must not embed Stage A body" || true
done

grep -q 'stage_a_handoff t14s' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must hand off with profile t14s"
grep -q 'stage_a_handoff p15' "$ROOT/scripts/arch-install-p15.sh" \
  || fail "arch-install-p15 must hand off with profile p15"
grep -q 'stage-a/install.sh' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must document canonical in-repo installer"
grep -q 'stage-a/install.sh' "$ROOT/scripts/arch-install-p15.sh" \
  || fail "arch-install-p15 must document canonical in-repo installer"

# Compatibility shim at t14s-arch-install/install.sh: local + curl-safe
SHIM="$ROOT/t14s-arch-install/install.sh"
[[ -x $SHIM ]] || fail "t14s-arch-install/install.sh shim must be executable"
bash -n "$SHIM" || fail "bash -n t14s-arch-install/install.sh"
shim_local="$(STAGE_A_DRY_PRINT=1 bash "$SHIM")" || fail "local shim dry-print failed"
grep -qx "shim-local:$ROOT/stage-a/install.sh" <<<"$shim_local" \
  || fail "local shim must resolve ../stage-a/install.sh: $shim_local"
# Simulate remote curl (bash <(...) has no regular file at BASH_SOURCE[0], even from t14s-arch-install/)
shim_remote="$(cd "$ROOT/t14s-arch-install" && STAGE_A_DRY_PRINT=1 STAGE_A_REF=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  bash <(cat "$SHIM"))" || fail "remote shim dry-print failed"
grep -qx 'shim-fetch:https://raw.githubusercontent.com/HelllGuest/dotfiles/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/stage-a/install.sh' <<<"$shim_remote" \
  || fail "remote shim must fetch SHA-pinned stage-a/install.sh: $shim_remote"
# Legacy .../t14s-arch-install base URL must rewrite to .../stage-a (no self-recursion)
shim_rewrite="$(cd "$ROOT/t14s-arch-install" && STAGE_A_DRY_PRINT=1 \
  T14S_BASE_URL=https://raw.githubusercontent.com/HelllGuest/dotfiles/cccccccccccccccccccccccccccccccccccccccc/t14s-arch-install/ \
  bash <(cat "$SHIM"))" || fail "remote shim rewrite failed"
grep -qx 'shim-fetch:https://raw.githubusercontent.com/HelllGuest/dotfiles/cccccccccccccccccccccccccccccccccccccccc/stage-a/install.sh' <<<"$shim_rewrite" \
  || fail "remote shim must rewrite legacy /t14s-arch-install base URL: $shim_rewrite"
# Remote shim real curl+exec path (stubbed curl, no network)
SHIM_TMP="$(mktemp -d)"
cat >"$SHIM_TMP/curl" <<'STUB'
#!/usr/bin/env bash
out="" url=""
while (( $# )); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '#!/usr/bin/env bash\nprintf "exec-ok:%%s|%%s|%%s\\n" %q "$STAGE_A_BASE_URL" "$*"\n' "$url" >"$out"
STUB
chmod +x "$SHIM_TMP/curl"
shim_exec="$(PATH="$SHIM_TMP:$PATH" STAGE_A_REF=dddddddddddddddddddddddddddddddddddddddd \
  bash <(cat "$SHIM") --smoke-arg)" || fail "remote shim stubbed curl exec failed"
rm -rf -- "$SHIM_TMP"
grep -qx 'exec-ok:https://raw.githubusercontent.com/HelllGuest/dotfiles/dddddddddddddddddddddddddddddddddddddddd/stage-a/install.sh|https://raw.githubusercontent.com/HelllGuest/dotfiles/dddddddddddddddddddddddddddddddddddddddd/stage-a|--smoke-arg' <<<"$shim_exec" \
  || fail "remote shim curl+exec mismatch: $shim_exec"

# Resolution: local checkout. Use a fixture so CI / hosts without a sibling
# ~/t14s-arch-install still exercise the local path (no network).
# shellcheck source=../provision/lib/stage-a-handoff.sh
source "$ROOT/provision/lib/stage-a-handoff.sh"
T14S_FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$T14S_FIXTURE_ROOT"' EXIT
T14S_FIXTURE="$T14S_FIXTURE_ROOT/t14s-arch-install"
mkdir -p "$T14S_FIXTURE/lib"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T14S_FIXTURE/install.sh"
# Local path must not call GitHub API (works with no network)
_run_local_handoff() {
  STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT="$ROOT" \
    T14S_LOCAL="$T14S_FIXTURE" \
    stage_a_handoff t14s
}
if command -v unshare >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  out="$(unshare -rn bash -c '
    set -euo pipefail
    ROOT="'"$ROOT"'"
    T14S_FIXTURE="'"$T14S_FIXTURE"'"
    # shellcheck source=/dev/null
    source "$ROOT/provision/lib/stage-a-handoff.sh"
    STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT="$ROOT" \
      T14S_LOCAL="$T14S_FIXTURE" \
      stage_a_handoff t14s
  ')" || fail "offline local handoff failed (must not need GitHub API)"
else
  out="$(_run_local_handoff)" || fail "dry handoff t14s failed"
fi
echo "$out" | grep -q '^local:' || fail "expected local resolution: $out"
echo "$out" | grep -qx 'HW_PROFILE=t14s' || fail "expected HW_PROFILE=t14s: $out"
echo "$out" | grep -q 'T14S_LIB_DIR=' || fail "expected T14S_LIB_DIR: $out"
# Resolve must sit after local checkout attempts (not before)
python3 - "$ROOT/provision/lib/stage-a-handoff.sh" <<'PY' || fail "resolve must follow local checkout"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
i_local = t.find('Explicit file')
i_remote = t.find('base="$(t14s_resolve_base_url)"')
assert i_local >= 0 and i_remote > i_local, (i_local, i_remote)
PY

out="$(
  STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT="$ROOT" \
    T14S_LOCAL="$T14S_FIXTURE" \
    stage_a_handoff p15
)" || fail "dry handoff p15 failed"
echo "$out" | grep -qx 'HW_PROFILE=p15' || fail "expected HW_PROFILE=p15: $out"

# Default in-repo lookup (no T14S_LOCAL, no sibling): must resolve $ROOT/stage-a
out="$(
  STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT="$ROOT" \
    STAGE_A_INSTALL_SH='' STAGE_A_LOCAL='' T14S_INSTALL_SH='' T14S_LOCAL='' HOME=/nonexistent \
    stage_a_handoff t14s
)" || fail "default in-repo handoff failed"
echo "$out" | grep -qx "local:$ROOT/stage-a/install.sh" \
  || fail "default handoff must resolve in-repo stage-a: $out"

# Shim dir (no lib/) passed via T14S_LOCAL must be skipped in favor of real stage-a/
out="$(
  STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT="$ROOT" \
    STAGE_A_INSTALL_SH='' STAGE_A_LOCAL='' T14S_INSTALL_SH='' \
    T14S_LOCAL="$ROOT/t14s-arch-install" HOME=/nonexistent \
    stage_a_handoff t14s
)" || fail "shim dir skip handoff failed"
echo "$out" | grep -qx "local:$ROOT/stage-a/install.sh" \
  || fail "handoff must skip shim dir without lib/: $out"
echo "$out" | grep -qx "T14S_LIB_DIR=$ROOT/stage-a/lib" \
  || fail "handoff must set T14S_LIB_DIR to stage-a/lib: $out"

# STAGE_A_LOCAL alias
out="$(
  STAGE_A_DRY_PRINT=1 STAGE_A_DOTFILES_ROOT=/nonexistent HOME=/nonexistent \
    STAGE_A_LOCAL="$T14S_FIXTURE" T14S_LOCAL='' \
    stage_a_handoff t14s
)" || fail "STAGE_A_LOCAL handoff failed"
echo "$out" | grep -qx "local:$T14S_FIXTURE/install.sh" \
  || fail "STAGE_A_LOCAL must resolve fixture: $out"

# Forced fetch: STAGE_A_REF / T14S_REF / STAGE_A_BASE_URL override (no network)
out="$(
  STAGE_A_DRY_PRINT=1 \
    STAGE_A_INSTALL_SH='' STAGE_A_LOCAL=/nonexistent \
    T14S_INSTALL_SH='' T14S_LOCAL=/nonexistent \
    STAGE_A_DOTFILES_ROOT=/nonexistent \
    HOME=/nonexistent \
    T14S_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    stage_a_handoff t14s
)" || fail "dry fetch handoff with T14S_REF failed"
echo "$out" | grep -q '^fetch:https://raw.githubusercontent.com/HelllGuest/dotfiles/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/stage-a/install.sh' \
  || fail "expected T14S_REF override in fetch URL: $out"
out="$(
  STAGE_A_DRY_PRINT=1 \
    STAGE_A_INSTALL_SH='' STAGE_A_LOCAL=/nonexistent \
    T14S_INSTALL_SH='' T14S_LOCAL=/nonexistent \
    STAGE_A_DOTFILES_ROOT=/nonexistent \
    HOME=/nonexistent \
    STAGE_A_REF=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee T14S_REF='' \
    stage_a_handoff p15
)" || fail "dry fetch handoff with STAGE_A_REF failed"
echo "$out" | grep -q '^fetch:https://raw.githubusercontent.com/HelllGuest/dotfiles/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/stage-a/install.sh' \
  || fail "expected STAGE_A_REF override in fetch URL: $out"
out="$(
  STAGE_A_DRY_PRINT=1 \
    STAGE_A_INSTALL_SH='' STAGE_A_LOCAL=/nonexistent \
    T14S_INSTALL_SH='' T14S_LOCAL=/nonexistent \
    STAGE_A_DOTFILES_ROOT=/nonexistent \
    HOME=/nonexistent \
    STAGE_A_BASE_URL=http://10.0.2.2:8765 T14S_BASE_URL='' \
    stage_a_handoff t14s
)" || fail "dry fetch handoff with STAGE_A_BASE_URL failed"
echo "$out" | grep -qx 'fetch:http://10.0.2.2:8765/install.sh' \
  || fail "expected STAGE_A_BASE_URL override in fetch URL: $out"
grep -q 't14s_resolve_base_url' "$ROOT/provision/lib/stage-a-handoff.sh" \
  || fail "stage-a-handoff must resolve main SHA via t14s_resolve_base_url"
grep -q "application/vnd.github.sha" "$ROOT/provision/lib/stage-a-handoff.sh" \
  || fail "stage-a-handoff must use GitHub commits API Accept: sha"

# In-repo canonical Stage A owns hardware seeds
CANON="$ROOT/stage-a"
[[ -f $CANON/install.sh && -f $CANON/lib/80-chroot-setup.sh ]] \
  || fail "missing in-repo Stage A tree at $CANON"
# Chroot code = entry script + its stages (lib/chroot/, when split).
CANON_CHROOT=("$CANON/lib/80-chroot-setup.sh")
[[ -d $CANON/lib/chroot ]] && CANON_CHROOT+=("$CANON"/lib/chroot/*.sh)
grep -q 'amd_iommu=on' "${CANON_CHROOT[@]}" \
  || fail "canonical Stage A missing amd_iommu"
grep -q 'nvidia_drm.modeset=1' "${CANON_CHROOT[@]}" \
  || fail "canonical Stage A missing nvidia modeset"
grep -q 'thinkpad-charge-thresholds' "${CANON_CHROOT[@]}" \
  || fail "canonical Stage A missing charge thresholds"
grep -q 'github-cli glab' "${CANON_CHROOT[@]}" \
  || fail "canonical Stage A devtools must include github-cli glab"
grep -q 'btop fastfetch' "${CANON_CHROOT[@]}" \
  || fail "canonical Stage A cli bundle must include btop fastfetch"

grep -q 'INSTALLER=' "$ROOT/provision/scripts/arch-install-vmtest.sh" \
  || fail "arch-install-vmtest must support INSTALLER="
grep -q 'STAGE_A_HANDOFF_URL=http://10.0.2.2' "$ROOT/provision/scripts/arch-install-vmtest.sh" \
  || fail "vmtest must print STAGE_A_HANDOFF_URL for local lib/"
grep -q 'T14S_BASE_URL=http://10.0.2.2' "$ROOT/provision/scripts/arch-install-vmtest.sh" \
  || fail "vmtest must print T14S_BASE_URL for local Stage A tree"
grep -q 'failed to fetch' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "wrappers must fail clearly when handoff curl fails"

# Cross-boundary parity: Stage A embedded ThinkPad fallbacks must stay byte-identical
# to canonical system/ files and templates (prevents silent drift on pure-curl ISO installs).
python3 - "$ROOT" <<'PY' || fail "Stage A vs system/ ThinkPad policy parity drift"
from pathlib import Path
import re, sys

root = Path(sys.argv[1])
chroot = (root / "stage-a/lib/chroot/03-initramfs-cmdline.sh").read_text()

def extract_heredoc(call_prefix: str, rel: str) -> str:
    pat = re.compile(
        rf'^[ \t]*{re.escape(call_prefix)}\s+{re.escape(rel)}\b[^\n]*<<\'EOF\'\n(.*?)\nEOF$',
        re.M | re.S,
    )
    m = pat.search(chroot)
    assert m, f"missing fallback heredoc for {call_prefix} {rel}"
    return m.group(1) + "\n"

for rel in [
    "etc/systemd/sleep.conf.d/s2idle.conf",
    "etc/udev/rules.d/61-thinkpad-charge-limit.rules",
    "etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules",
    "etc/systemd/logind.conf.d/thinkpad-lid.conf",
    "templates/thinkpad-charge-thresholds.conf",
]:
    want = (root / "system" / rel).read_text()
    got = extract_heredoc("_sys_install", rel)
    assert got == want, f"drift in {rel}:\n--- system\n{want}--- stage-a\n{got}"

for rel in [
    "templates/apply-charge-thresholds.sh.tmpl",
    "templates/thinkpad-charge-thresholds.service.tmpl",
]:
    want = (root / "system" / rel).read_text()
    got = extract_heredoc("_sys_render_tmpl", rel)
    assert got == want, f"drift in {rel}:\n--- system\n{want}--- stage-a\n{got}"
PY

# DMI + charge policy single-source parity: stage-a/lib/05-policy.sh vs provision/lib/dmi.sh
_pol_vals="$(bash -c 'source "$1"; printf "%s|%s|%s|%s" "$STAGE_A_DMI_T14S_RE" "$STAGE_A_DMI_P15_RE" "$CHARGE_START" "$CHARGE_END"' _ "$ROOT/stage-a/lib/05-policy.sh")"
_dmi_vals="$(bash -c 'source "$1"; printf "%s|%s|%s|%s" "$STAGE_A_DMI_T14S_RE" "$STAGE_A_DMI_P15_RE" "$CHARGE_START" "$CHARGE_END"' _ "$ROOT/provision/lib/dmi.sh")"
[[ $_pol_vals == "$_dmi_vals" ]] || fail "05-policy.sh and dmi.sh diverged: [$_pol_vals] vs [$_dmi_vals]"
# Standalone dmi.sh fallback (copied without stage-a/) must still match 05-policy.sh
_iso_dmi="$(mktemp -d)"
cp "$ROOT/provision/lib/dmi.sh" "$_iso_dmi/dmi.sh"
_iso_vals="$(bash -c 'source "$1"; printf "%s|%s|%s|%s" "$STAGE_A_DMI_T14S_RE" "$STAGE_A_DMI_P15_RE" "$CHARGE_START" "$CHARGE_END"' _ "$_iso_dmi/dmi.sh")"
rm -rf -- "$_iso_dmi"
[[ $_pol_vals == "$_iso_vals" ]] || fail "standalone dmi.sh fallback diverged from 05-policy.sh: [$_pol_vals] vs [$_iso_vals]"

# GitHub SHA resolver parity + behavioral validation (stubbed curl)
for _rf in \
  "$ROOT/stage-a/lib/05-policy.sh" \
  "$ROOT/stage-a/install.sh" \
  "$ROOT/t14s-arch-install/install.sh" \
  "$ROOT/provision/lib/stage-a-handoff.sh"
do
  grep -q 'application/vnd.github.sha' "$_rf" || fail "$_rf missing GitHub SHA Accept header"
  grep -q '\[0-9a-f\]{40}' "$_rf" || fail "$_rf missing 40-hex SHA validation"
done

_UT="$(mktemp -d)"
trap 'rm -rf -- "$T14S_FIXTURE_ROOT" "$_UT"' EXIT

# 1) stage_a_resolve_main_sha + invalid STAGE_A_REPO / STAGE_A_BRANCH rejection
mkdir -p "$_UT/bin"
cat >"$_UT/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "1234567890abcdef1234567890abcdef12345678"
STUB
chmod +x "$_UT/bin/curl"
_sha="$(PATH="$_UT/bin:$PATH" bash -c 'source "$1"; stage_a_resolve_main_sha' _ "$ROOT/stage-a/lib/05-policy.sh")" \
  || fail "stage_a_resolve_main_sha valid stub failed"
[[ $_sha == 1234567890abcdef1234567890abcdef12345678 ]] || fail "unexpected sha: $_sha"
if PATH="$_UT/bin:$PATH" STAGE_A_REPO="../evil/repo" bash -c 'source "$1"; stage_a_resolve_main_sha' _ "$ROOT/stage-a/lib/05-policy.sh" >/dev/null 2>&1; then
  fail "invalid STAGE_A_REPO must be rejected"
fi
if PATH="$_UT/bin:$PATH" STAGE_A_BRANCH="main/../../x" bash -c 'source "$1"; stage_a_resolve_main_sha' _ "$ROOT/stage-a/lib/05-policy.sh" >/dev/null 2>&1; then
  fail "invalid STAGE_A_BRANCH must be rejected"
fi

# 2) dmi_matches_p15_gen1 matches 20SU only (does not silently widen to P15 Gen 2 20YQ)
bash -c 'source "$1"; dmi_matches_p15_gen1 "20SUS0R700" && ! dmi_matches_p15_gen1 "ThinkPad P15 Gen 2i 20YQ0001US"' \
  _ "$ROOT/stage-a/lib/05-policy.sh" || fail "dmi_matches_p15_gen1 must match 20SU only"

# 3) ai/lib/jdk.sh pick_jdk21 (skips 17 + JRE without javac, picks highest >= 21, fails when empty)
mkdir -p "$_UT/jvm/java-17-openjdk/bin" "$_UT/jvm/java-21-openjdk/bin" \
         "$_UT/jvm/java-25-openjdk/bin" "$_UT/jvm/java-26-openjdk/bin" "$_UT/jvm-empty"
printf '#!/bin/sh\n' >"$_UT/jvm/java-17-openjdk/bin/javac"
printf '#!/bin/sh\n' >"$_UT/jvm/java-21-openjdk/bin/javac"
printf '#!/bin/sh\n' >"$_UT/jvm/java-25-openjdk/bin/javac"
chmod +x "$_UT/jvm/java-17-openjdk/bin/javac" "$_UT/jvm/java-21-openjdk/bin/javac" "$_UT/jvm/java-25-openjdk/bin/javac"
# java-26 intentionally lacks javac (JRE only)
_jdk="$(JDK_JVM_DIR="$_UT/jvm" bash -c 'source "$1"; pick_jdk21' _ "$ROOT/ai/lib/jdk.sh")" \
  || fail "pick_jdk21 failed on fixture"
[[ $_jdk == "$_UT/jvm/java-25-openjdk" ]] || fail "pick_jdk21 must pick highest full JDK >= 21 (got: $_jdk)"
if JDK_JVM_DIR="$_UT/jvm-empty" bash -c 'source "$1"; pick_jdk21' _ "$ROOT/ai/lib/jdk.sh" >/dev/null 2>&1; then
  fail "pick_jdk21 must return non-zero when no JDK >= 21 exists"
fi

# 4) provision/lib/vm-common.sh vm_find_ovmf
mkdir -p "$_UT/ovmf"
: >"$_UT/ovmf/OVMF_CODE.4m.fd"
: >"$_UT/ovmf/OVMF_VARS.4m.fd"
_ovmf="$(VM_OVMF_PATHS="/nonexistent/OVMF_CODE.fd:$_UT/ovmf/OVMF_CODE.4m.fd" \
  bash -c 'source "$1"; vm_find_ovmf && printf "%s|%s" "$OVMF_CODE" "$OVMF_VARS_SRC"' _ "$ROOT/provision/lib/vm-common.sh")" \
  || fail "vm_find_ovmf failed on fixture"
[[ $_ovmf == "$_UT/ovmf/OVMF_CODE.4m.fd|$_UT/ovmf/OVMF_VARS.4m.fd" ]] || fail "vm_find_ovmf mismatch: $_ovmf"
if VM_OVMF_PATHS="/nonexistent/OVMF_CODE.fd" bash -c 'source "$1"; vm_find_ovmf' _ "$ROOT/provision/lib/vm-common.sh"; then
  fail "vm_find_ovmf must fail when no OVMF pair exists"
fi

# 5) provision/lib/dmi.sh install_udev_rule (installs + reloads + triggers; skips when unchanged)
mkdir -p "$_UT/udev-bin" "$_UT/udev-dst"
cat >"$_UT/udev-bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$UDEV_LOG"
case "$1" in
  install)
    src="${*: -2:1}" dst="${*: -1:1}"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ;;
esac
STUB
chmod +x "$_UT/udev-bin/sudo"
printf 'ACTION!="remove", ENV{CHARGE_LIMIT}="70,80"\n' >"$_UT/rule.rules"
UDEV_LOG="$_UT/udev.log" PATH="$_UT/udev-bin:$PATH" \
  bash -c 'source "$1"; install_udev_rule "$2" "$3" power_supply; install_udev_rule "$2" "$3" power_supply' \
  _ "$ROOT/provision/lib/dmi.sh" "$_UT/rule.rules" "$_UT/udev-dst/61.rules" \
  || fail "install_udev_rule failed"
[[ $(grep -c 'udevadm control --reload-rules' "$_UT/udev.log") -eq 1 ]] \
  || fail "install_udev_rule must reload once and skip identical second run: $(cat "$_UT/udev.log")"
grep -q 'udevadm trigger --subsystem-match=power_supply' "$_UT/udev.log" \
  || fail "install_udev_rule must trigger requested subsystem"

# 6) 03-initramfs-cmdline.sh charge window validation + custom CHARGE_START/END (monorepo + fallback)
if CHARGE_START="70/evil" CHARGE_END="80" bash -c '
  source "$1"
  stage_a_validate_charge_window "$CHARGE_START" "$CHARGE_END"
' _ "$ROOT/stage-a/lib/05-policy.sh"; then
  fail "stage_a_validate_charge_window must reject non-integer CHARGE_START"
fi
if CHARGE_START=85 CHARGE_END=80 bash -c '
  source "$1"
  stage_a_validate_charge_window "$CHARGE_START" "$CHARGE_END"
' _ "$ROOT/stage-a/lib/05-policy.sh"; then
  fail "stage_a_validate_charge_window must reject START >= END"
fi

# 7) Headroom env in .shell-exports recomputes URLs when HEADROOM_PORT is overridden in .bashrc.local
mkdir -p "$_UT/home"
cp "$ROOT/stow/zsh/.shell-exports" "$_UT/home/.shell-exports"
printf 'export HEADROOM_PORT=9999\n' >"$_UT/home/.bashrc.local"
_hr="$(env -i HOME="$_UT/home" PATH="$PATH" bash -c '
  source "$HOME/.shell-exports"
  source "$HOME/.bashrc.local"
  _headroom_apply_env
  printf "%s|%s" "$ANTHROPIC_BASE_URL" "$OPENAI_BASE_URL"
')"
[[ $_hr == "http://127.0.0.1:9999|http://127.0.0.1:9999/v1" ]] \
  || fail ".bashrc.local HEADROOM_PORT override must update Headroom URLs (got: $_hr)"
printf 'export HEADROOM_PORT=9999\nexport ANTHROPIC_BASE_URL="https://custom.local"\n' >"$_UT/home/.bashrc.local"
_hr2="$(env -i HOME="$_UT/home" PATH="$PATH" bash -c '
  source "$HOME/.shell-exports"
  source "$HOME/.bashrc.local"
  _headroom_apply_env
  printf "%s|%s" "$ANTHROPIC_BASE_URL" "$OPENAI_BASE_URL"
')"
[[ $_hr2 == "https://custom.local|http://127.0.0.1:9999/v1" ]] \
  || fail "explicit ANTHROPIC_BASE_URL in .bashrc.local must be preserved (got: $_hr2)"

unset -v _pol_vals _dmi_vals _iso_dmi _iso_vals _rf _sha _jdk _ovmf _hr _hr2

echo "PASS: stage-a-handoff.test.sh"
