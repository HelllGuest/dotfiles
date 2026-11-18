#!/usr/bin/env bash
# Thin Stage A wrappers → HelllGuest/t14s-arch-install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/lib/stage-a-handoff.sh" \
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
grep -q 'HelllGuest/t14s-arch-install' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "arch-install-t14s must document canonical repo"
grep -q 'HelllGuest/t14s-arch-install' "$ROOT/scripts/arch-install-p15.sh" \
  || fail "arch-install-p15 must document canonical repo"

# Resolution: local checkout. Use a fixture so CI / hosts without a sibling
# ~/t14s-arch-install still exercise the local path (no network).
# shellcheck source=../scripts/lib/stage-a-handoff.sh
source "$ROOT/scripts/lib/stage-a-handoff.sh"
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
    source "$ROOT/scripts/lib/stage-a-handoff.sh"
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
python3 - "$ROOT/scripts/lib/stage-a-handoff.sh" <<'PY' || fail "resolve must follow local checkout"
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

# Forced fetch: T14S_REF override (no network) → same commit for install URL
out="$(
  STAGE_A_DRY_PRINT=1 \
    T14S_INSTALL_SH='' T14S_LOCAL=/nonexistent \
    STAGE_A_DOTFILES_ROOT=/nonexistent \
    HOME=/nonexistent \
    T14S_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    stage_a_handoff t14s
)" || fail "dry fetch handoff with T14S_REF failed"
echo "$out" | grep -q '^fetch:https://raw.githubusercontent.com/HelllGuest/t14s-arch-install/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/install.sh' \
  || fail "expected T14S_REF override in fetch URL: $out"
grep -q 't14s_resolve_base_url' "$ROOT/scripts/lib/stage-a-handoff.sh" \
  || fail "stage-a-handoff must resolve main SHA via t14s_resolve_base_url"
grep -q "application/vnd.github.sha" "$ROOT/scripts/lib/stage-a-handoff.sh" \
  || fail "stage-a-handoff must use GitHub commits API Accept: sha"

# Canonical repo still owns hardware seeds (when sibling present)
CANON="$ROOT/../t14s-arch-install"
if [[ -f $CANON/install.sh && -f $CANON/lib/80-chroot-setup.sh ]]; then
  # Chroot code = entry script + its stages (lib/chroot/, when split).
  CANON_CHROOT=("$CANON/lib/80-chroot-setup.sh")
  [[ -d $CANON/lib/chroot ]] && CANON_CHROOT+=("$CANON"/lib/chroot/*.sh)
  grep -q 'amd_iommu=on' "${CANON_CHROOT[@]}" \
    || fail "canonical Stage A missing amd_iommu"
  grep -q 'nvidia_drm.modeset=1' "${CANON_CHROOT[@]}" \
    || fail "canonical Stage A missing nvidia modeset"
  grep -q 'thinkpad-charge-thresholds' "${CANON_CHROOT[@]}" \
    || fail "canonical Stage A missing charge thresholds"
  grep -q 'github-cli glab' "$CANON/lib/50-packages.sh" \
    || fail "canonical base must include github-cli glab"
  grep -q 'htop btop fastfetch' "$CANON/lib/50-packages.sh" \
    || fail "canonical base must include htop btop fastfetch"
else
  echo "NOTE: skip canonical seed checks (no sibling t14s-arch-install)"
fi

grep -q 'INSTALLER=' "$ROOT/scripts/arch-install-vmtest.sh" \
  || fail "arch-install-vmtest must support INSTALLER="
grep -q 'STAGE_A_HANDOFF_URL=http://10.0.2.2' "$ROOT/scripts/arch-install-vmtest.sh" \
  || fail "vmtest must print STAGE_A_HANDOFF_URL for local lib/"
grep -q 'T14S_BASE_URL=http://10.0.2.2' "$ROOT/scripts/arch-install-vmtest.sh" \
  || fail "vmtest must print T14S_BASE_URL for local Stage A tree"
grep -q 'failed to fetch' "$ROOT/scripts/arch-install-t14s.sh" \
  || fail "wrappers must fail clearly when handoff curl fails"

echo "PASS: stage-a-handoff.test.sh"
