#!/usr/bin/env bash
# install-android-ui-skills.sh — Compose UI/UX agent skills (X1 / P15)
#
# Installs globally via skills CLI (pinned refs):
#   * NI3singh/android-compose-design-skill @ main tip (commit pin)
#   * hamen/material-3-skill @ v1.1.1
#
# Env:
#   ANDROID_COMPOSE_DESIGN_REF  override compose skill git ref
#   MATERIAL_3_SKILL_REF        override material-3 skill git ref
#   SKIP_SKILL_SYNC=1           skip sync-agent-skills.sh (install.sh batches sync)
#
# Usage:
#   bash scripts/install-android-ui-skills.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# main @ 2026-10-19; bump intentionally when refreshing
ANDROID_COMPOSE_DESIGN_REF="${ANDROID_COMPOSE_DESIGN_REF:-9a9f6c4f7afff72a4d38304add19b2eb740693e5}"
MATERIAL_3_SKILL_REF="${MATERIAL_3_SKILL_REF:-v1.1.1}"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

command -v npx >/dev/null 2>&1 || die "npx required (fnm/node first)"

say "android-compose-design @ ${ANDROID_COMPOSE_DESIGN_REF}"
npx --yes skills add "NI3singh/android-compose-design-skill@${ANDROID_COMPOSE_DESIGN_REF}" \
  --skill android-compose-design -g -y

say "material-3 @ ${MATERIAL_3_SKILL_REF}"
npx --yes skills add "hamen/material-3-skill@${MATERIAL_3_SKILL_REF}" \
  --skill material-3 -g -y

if [[ "${SKIP_SKILL_SYNC:-0}" != "1" && -f "$REPO_ROOT/scripts/sync-agent-skills.sh" ]]; then
  say "mirror skills into agents/claude/cursor hubs"
  bash "$REPO_ROOT/scripts/sync-agent-skills.sh" || true
fi

say "install-android-ui-skills done"
echo "  use: Android Compose / Material 3 UI tasks (auto-trigger)"
echo "  skills: android-compose-design, material-3"
