# shellcheck shell=bash
# lib/agent-skills.sh — shared Agent Skills CLI helpers
# Sourced by install-ecosystem-skills.sh / install-re-skills.sh (REPO_ROOT set by caller).

agent_skills_die() { echo "error: $*" >&2; exit 1; }
agent_skills_say() { printf '>> %s\n' "$*"; }
agent_skills_warn() { echo "warning: $*" >&2; }

# Ensure skills CLI can detect/link Cursor, Claude, OpenCode, Kimi, Gemini/Antigravity, Codex, hub.
agent_skills_prepare_dirs() {
  mkdir -p \
    "${HOME}/.cursor/skills" \
    "${HOME}/.claude/skills" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills" \
    "${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills" \
    "${HOME}/.kimi" \
    "${HOME}/.gemini/skills" \
    "${HOME}/.gemini/config/skills" \
    "${HOME}/.codex/skills" \
    "${HOME}/.agents/skills"
  local kimi_skills="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"
  local link="${HOME}/.kimi/skills"
  if [[ -d "$link" && ! -L "$link" ]]; then
    agent_skills_warn "replace real dir with symlink: $link"
    rm -rf "$link"
  fi
  ln -sfnT "$kimi_skills" "$link"
}

# Global CLI agent flags (skills add -a …).
AGENT_SKILLS_CLI_AGENTS=(-a cursor -a claude-code -a opencode -a kimi-code-cli)

# Read manifest → nameref array (skip comments / blank lines).
# Usage: agent_skills_read_manifest "$file" packs_array_name
agent_skills_read_manifest() {
  local file=$1
  local -n _as_out=$2
  [[ -f "$file" ]] || agent_skills_die "missing manifest: $file"
  mapfile -t _as_out < <(
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$file" | awk 'NF'
  )
  [[ ${#_as_out[@]} -gt 0 ]] || agent_skills_die "no packs in $file"
}

# Parse owner/repo[:skill1,skill2] → pack + skill_args nameref array.
# Callers must not pass variables named _as_pack / _as_skill_args (nameref clash).
agent_skills_parse_entry() {
  local entry=$1
  local -n _as_pack=$2
  local -n _as_skill_args=$3
  local skills_spec="" s
  local -a _sks=()
  _as_pack="${entry%%:*}"
  _as_skill_args=(--skill '*')
  if [[ "$entry" == *:* ]]; then
    skills_spec="${entry#*:}"
  fi
  if [[ -n "$skills_spec" ]]; then
    _as_skill_args=()
    IFS=',' read -ra _sks <<<"$skills_spec"
    for s in "${_sks[@]}"; do
      s="${s// /}"
      [[ -n "$s" ]] && _as_skill_args+=(--skill "$s")
    done
    [[ ${#_as_skill_args[@]} -gt 0 ]] || _as_skill_args=(--skill '*')
  fi
}

# Install every manifest entry via npx skills.
# Sets AGENT_SKILLS_FAILED and AGENT_SKILLS_PACK_COUNT. Caller needs npx on PATH.
agent_skills_install_manifest() {
  local file=$1
  local packs=() entry pack skill_args=()
  AGENT_SKILLS_FAILED=0
  agent_skills_read_manifest "$file" packs
  for entry in "${packs[@]}"; do
    agent_skills_parse_entry "$entry" pack skill_args
    agent_skills_say "skills add ${pack} ${skill_args[*]} (global)"
    if ! npx --yes skills add "$pack" "${skill_args[@]}" -g -y "${AGENT_SKILLS_CLI_AGENTS[@]}" 2>&1; then
      agent_skills_warn "failed: $entry"
      AGENT_SKILLS_FAILED=$((AGENT_SKILLS_FAILED + 1))
    fi
  done
  # shellcheck disable=SC2034 # read by callers after sourcing this helper
  AGENT_SKILLS_PACK_COUNT=${#packs[@]}
}

agent_skills_maybe_sync() {
  local root="${1:-${REPO_ROOT:-}}"
  if [[ "${SKIP_SKILL_SYNC:-0}" != "1" && -n "$root" && -f "$root/ai/scripts/sync-agent-skills.sh" ]]; then
    agent_skills_say "mirror hub → claude/cursor/opencode/kimi/gemini/antigravity/kiro/codex"
    bash "$root/ai/scripts/sync-agent-skills.sh" || true
  fi
}
