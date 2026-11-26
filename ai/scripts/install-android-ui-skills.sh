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
#   bash ai/scripts/install-android-ui-skills.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# main @ 2026-10-19; bump intentionally when refreshing
ANDROID_COMPOSE_DESIGN_REF="${ANDROID_COMPOSE_DESIGN_REF:-9a9f6c4f7afff72a4d38304add19b2eb740693e5}"
MATERIAL_3_SKILL_REF="${MATERIAL_3_SKILL_REF:-v1.1.1}"

# shellcheck source=../lib/agent-skills.sh
source "$REPO_ROOT/ai/lib/agent-skills.sh"

command -v npx >/dev/null 2>&1 || agent_skills_die "npx required (fnm/node first)"

agent_skills_say "android-compose-design @ ${ANDROID_COMPOSE_DESIGN_REF}"
npx --yes skills add "NI3singh/android-compose-design-skill@${ANDROID_COMPOSE_DESIGN_REF}" \
  --skill android-compose-design -g -y

agent_skills_say "material-3 @ ${MATERIAL_3_SKILL_REF}"
npx --yes skills add "hamen/material-3-skill@${MATERIAL_3_SKILL_REF}" \
  --skill material-3 -g -y

agent_skills_maybe_sync "$REPO_ROOT"

agent_skills_say "install-android-ui-skills done"
echo "  use: Android Compose / Material 3 UI tasks (auto-trigger)"
echo "  skills: android-compose-design, material-3"
