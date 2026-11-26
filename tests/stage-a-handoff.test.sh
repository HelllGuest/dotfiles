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

echo "PASS: stage-a-handoff.test.sh"
