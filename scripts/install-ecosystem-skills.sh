#!/usr/bin/env bash
# install-ecosystem-skills.sh — pinned third-party Agent Skills packs (fresh Arch)
#
# Reads packages/agent-skills.txt and installs each pack globally via skills CLI.
# Targets Cursor, Claude Code, OpenCode, and Kimi Code CLI when present.
# Caveman / Compose / Material 3 stay in their dedicated installers.
#
# Env:
#   AGENT_SKILLS_FILE   override manifest path
#   SKIP_SKILL_SYNC=1   skip sync-agent-skills.sh at end
#   DISABLE_TELEMETRY=1 defaulted here (privacy)
#
# Usage:
#   bash scripts/install-ecosystem-skills.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_SKILLS_FILE="${AGENT_SKILLS_FILE:-$REPO_ROOT/packages/agent-skills.txt}"
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-1}"
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v npx >/dev/null 2>&1 || die "npx required (fnm/node first)"
[[ -f "$AGENT_SKILLS_FILE" ]] || die "missing manifest: $AGENT_SKILLS_FILE"

# Ensure detect paths exist so skills CLI can link agents
mkdir -p \
  "${HOME}/.cursor/skills" \
  "${HOME}/.claude/skills" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills" \
  "${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills" \
  "${HOME}/.kimi" \
  "${HOME}/.agents/skills"
_kimi_skills="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"
_link="${HOME}/.kimi/skills"
if [[ -d "$_link" && ! -L "$_link" ]]; then
  warn "replace real dir with symlink: $_link"
  rm -rf "$_link"
fi
ln -sfnT "$_kimi_skills" "$_link"
unset _kimi_skills _link

AGENTS=(-a cursor -a claude-code -a opencode -a kimi-code-cli)

mapfile -t PACKS < <(
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$AGENT_SKILLS_FILE" \
    | awk 'NF'
)
[[ ${#PACKS[@]} -gt 0 ]] || die "no packs in $AGENT_SKILLS_FILE"

failed=0
for pack in "${PACKS[@]}"; do
  say "skills add ${pack} (global)"
  if ! npx --yes skills add "$pack" --skill '*' -g -y "${AGENTS[@]}" 2>&1; then
    warn "failed: $pack"
    failed=$((failed + 1))
  fi
done

if [[ "${SKIP_SKILL_SYNC:-0}" != "1" && -f "$REPO_ROOT/scripts/sync-agent-skills.sh" ]]; then
  say "mirror hub → claude/cursor/opencode/kimi"
  bash "$REPO_ROOT/scripts/sync-agent-skills.sh" || true
fi

say "install-ecosystem-skills done ($(( ${#PACKS[@]} - failed ))/${#PACKS[@]} packs ok)"
[[ "$failed" -eq 0 ]] || exit 1
