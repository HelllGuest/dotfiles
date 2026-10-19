#!/usr/bin/env bash
# Smoke: AI installer scripts parse + pinned digests/refs stay wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/sync-agent-skills.sh" \
  "$ROOT/scripts/install-caveman.sh" \
  "$ROOT/scripts/install-android-ui-skills.sh" \
  "$ROOT/scripts/install-rea.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  [[ -x "$f" ]] || fail "not executable: $f"
  bash -n "$f" || fail "bash -n failed: $f"
done

grep -q 'CAVEMAN_TAG:-v4.0.1' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman tag pin missing"
grep -q 'c129b946a1f7f2e9eeeff5c1a747d7b43b2630c6b9e5fc7aa8297cece9cd3804' \
  "$ROOT/scripts/install-caveman.sh" || fail "caveman SHA-256 pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman SKIP_SKILL_SYNC missing"

grep -q '9a9f6c4f7afff72a4d38304add19b2eb740693e5' \
  "$ROOT/scripts/install-android-ui-skills.sh" || fail "compose commit pin missing"
grep -q 'MATERIAL_3_SKILL_REF:-v1.1.1' \
  "$ROOT/scripts/install-android-ui-skills.sh" || fail "material-3 tag pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-android-ui-skills.sh" \
  || fail "android-ui SKIP_SKILL_SYNC missing"

grep -q 'SKIP_SKILL_SYNC=1' "$ROOT/install.sh" || fail "install.sh must batch skill sync"
# Pre-sync (kit fallback) + post-sync (hub mirror after AI)
sync_count="$(grep -c 'bash scripts/sync-agent-skills.sh' "$ROOT/install.sh" || true)"
[[ "$sync_count" -eq 2 ]] \
  || fail "install.sh must call sync-agent-skills.sh twice (pre + post AI)"
grep -q '3\.5a Kit skills first' "$ROOT/install.sh" \
  || fail "install.sh missing pre-AI sync block (3.5a)"
grep -q '3\.5f Hub mirror after AI' "$ROOT/install.sh" \
  || fail "install.sh missing post-AI sync block (3.5f)"
grep -q 'check_agent_skill' "$ROOT/scripts/check.sh" || fail "check.sh skill probes missing"
grep -q 'git.new/crampack-sh' "$ROOT/README.md" \
  || fail "README must keep upstream Crampack one-liner after script removal"
grep -q 'pacman.txt' "$ROOT/CONTRIBUTING.md" \
  || fail "CONTRIBUTING profiles must mention pacman-then-profile"

echo "PASS: ai-install-scripts.test.sh"
