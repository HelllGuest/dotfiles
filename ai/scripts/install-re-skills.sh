#!/usr/bin/env bash
# install-re-skills.sh — reverse-engineering Agent Skills (leanrea, playbooks, Android, Ghidra, firmware)
#
# Reads packages/agent-skills-re.txt. Installs globally via skills CLI for
# Cursor, Claude Code, OpenCode, and Kimi Code CLI when present.
# Manifest lines: owner/repo  or  owner/repo:skill1,skill2
# REA MCP + reverse-engineer-anything: ai/scripts/install-rea.sh (separate).
#
# Env:
#   AGENT_SKILLS_RE_FILE  override manifest path
#   SKIP_SKILL_SYNC=1     skip sync-agent-skills.sh at end
#   DISABLE_TELEMETRY=1   defaulted here (privacy)
#
# Usage:
#   bash ai/scripts/install-re-skills.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGENT_SKILLS_RE_FILE="${AGENT_SKILLS_RE_FILE:-$REPO_ROOT/packages/agent-skills-re.txt}"
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-1}"
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# shellcheck source=../lib/agent-skills.sh
source "$REPO_ROOT/ai/lib/agent-skills.sh"

command -v npx >/dev/null 2>&1 || agent_skills_die "npx required (fnm/node first)"

agent_skills_prepare_dirs
agent_skills_install_manifest "$AGENT_SKILLS_RE_FILE"
agent_skills_maybe_sync "$REPO_ROOT"

agent_skills_say "install-re-skills done ($((AGENT_SKILLS_PACK_COUNT - AGENT_SKILLS_FAILED))/${AGENT_SKILLS_PACK_COUNT} packs ok)"
[[ "$AGENT_SKILLS_FAILED" -eq 0 ]] || exit 1
