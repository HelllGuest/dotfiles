#!/usr/bin/env bash
# install-ponytail.sh — DietrichGebert/ponytail ("lazy senior dev") for all detected agents
#
# Pins release tag v5.3.3. Clones/updates a persistent checkout at
# ~/.local/share/ponytail so Cursor hooks and OpenCode plugins resolve on disk,
# installs the 6 ponytail skills into ~/.agents/skills, and wires Claude Code,
# Cursor, OpenCode, Gemini CLI, Antigravity, and Kiro. Safe to re-run.
#
# Env:
#   PONYTAIL_TAG         override tag (default v5.3.3)
#   PONYTAIL_DIR         override checkout dir (default ~/.local/share/ponytail)
#   SKIP_SKILL_SYNC=1    skip sync-agent-skills.sh (install.sh batches sync)
#
# Usage:
#   bash scripts/install-ponytail.sh

set -euo pipefail

export PATH="${HOME}/.opencode/bin:${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PONYTAIL_REPO="https://github.com/DietrichGebert/ponytail.git"
PONYTAIL_TAG="${PONYTAIL_TAG:-v5.3.3}"
# Commit SHA matching PONYTAIL_TAG; bump tag + commit together (refuses moved tags).
PONYTAIL_COMMIT="${PONYTAIL_COMMIT:-7801d061243d7b753bad0e0b3c057cd250b11755}"
PONYTAIL_DIR="${PONYTAIL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ponytail}"
AGENTS_SKILLS="${HOME}/.agents/skills"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
PONYTAIL_TMPS=()
trap '(( ${#PONYTAIL_TMPS[@]} )) && rm -rf -- "${PONYTAIL_TMPS[@]}"' EXIT

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v git >/dev/null 2>&1 || die "git required"
command -v node >/dev/null 2>&1 || die "node required (fnm/node first)"
[[ "$PONYTAIL_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "PONYTAIL_COMMIT must be a 40-char commit SHA"

say "sync DietrichGebert/ponytail (${PONYTAIL_TAG} @ ${PONYTAIL_COMMIT:0:12}) → ${PONYTAIL_DIR}"
mkdir -p "$(dirname "$PONYTAIL_DIR")"
if [[ -d "$PONYTAIL_DIR/.git" ]]; then
  git -C "$PONYTAIL_DIR" fetch --depth 1 origin "refs/tags/${PONYTAIL_TAG}:refs/tags/${PONYTAIL_TAG}" >/dev/null 2>&1 \
    || git -C "$PONYTAIL_DIR" fetch --depth 1 origin "$PONYTAIL_COMMIT" >/dev/null 2>&1 \
    || die "failed to fetch ponytail ${PONYTAIL_TAG}"
  git -C "$PONYTAIL_DIR" checkout -B main "${PONYTAIL_TAG}" >/dev/null 2>&1 \
    || git -C "$PONYTAIL_DIR" checkout -B main "${PONYTAIL_COMMIT}" >/dev/null 2>&1
else
  rm -rf "$PONYTAIL_DIR"
  git clone --depth 1 --branch "${PONYTAIL_TAG}" "$PONYTAIL_REPO" "$PONYTAIL_DIR" >/dev/null 2>&1
  git -C "$PONYTAIL_DIR" checkout -B main "${PONYTAIL_TAG}" >/dev/null 2>&1 || true
fi

got_commit="$(git -C "$PONYTAIL_DIR" rev-parse HEAD 2>/dev/null || true)"
[[ "$got_commit" == "$PONYTAIL_COMMIT" ]] \
  || die "ponytail ${PONYTAIL_TAG} resolved to ${got_commit:-unknown}, expected ${PONYTAIL_COMMIT} — refusing a moved tag"

[[ -f "$PONYTAIL_DIR/AGENTS.md" && -d "$PONYTAIL_DIR/skills/ponytail" ]] \
  || die "ponytail checkout incomplete at $PONYTAIL_DIR"

# 1. Hub skills (ponytail, ponytail-review, ponytail-audit, ponytail-debt, ponytail-gain, ponytail-help)
PONYTAIL_SKILLS=(ponytail ponytail-review ponytail-audit ponytail-debt ponytail-gain ponytail-help)
say "install ponytail skills → $AGENTS_SKILLS"
mkdir -p "$AGENTS_SKILLS"
for _skill in "${PONYTAIL_SKILLS[@]}"; do
  if [[ -d "$PONYTAIL_DIR/skills/$_skill" ]]; then
    rm -rf "${AGENTS_SKILLS:?}/$_skill"
    cp -a "$PONYTAIL_DIR/skills/$_skill" "${AGENTS_SKILLS}/$_skill"
    echo "  hub/$_skill"
  fi
done
unset _skill

# 2. Claude Code plugin (use ~/.claude/tmp to avoid EXDEV across /tmp tmpfs)
if command -v claude >/dev/null 2>&1; then
  say "claude plugin marketplace + ponytail@ponytail (best-effort)"
  mkdir -p "${HOME}/.claude/tmp"
  TMPDIR="${HOME}/.claude/tmp" claude plugin marketplace add DietrichGebert/ponytail 2>/dev/null || true
  TMPDIR="${HOME}/.claude/tmp" claude plugin install -y ponytail@ponytail 2>/dev/null || true
  rmdir "${HOME}/.claude/tmp" 2>/dev/null || true
fi

# 3. Cursor native hooks (merges sessionStart + beforeSubmitPrompt into ~/.cursor/hooks.json)
if command -v cursor >/dev/null 2>&1 || [[ -d "${HOME}/.cursor" ]]; then
  if [[ -f "$PONYTAIL_DIR/scripts/cursor-hooks.js" ]]; then
    say "cursor hooks → ~/.cursor/hooks.json"
    node "$PONYTAIL_DIR/scripts/cursor-hooks.js" install || warn "cursor-hooks install failed"
  fi
fi

# 4. OpenCode plugin + commands
if command -v opencode >/dev/null 2>&1 || [[ -d "$OPENCODE_DIR" ]]; then
  say "opencode plugin + commands → $OPENCODE_DIR"
  mkdir -p "$OPENCODE_DIR/commands"
  shopt -s nullglob
  for _cmd in "$PONYTAIL_DIR"/.opencode/command/ponytail*.md; do
    cp -a "$_cmd" "$OPENCODE_DIR/commands/$(basename "$_cmd")"
  done
  shopt -u nullglob
  unset _cmd
  if [[ -f "$OPENCODE_DIR/opencode.json" ]]; then
    python3 - "$OPENCODE_DIR/opencode.json" "$PONYTAIL_DIR/.opencode/plugins" <<'PY'
import json, sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
plugin_dir = sys.argv[2]
try:
    data = json.loads(cfg_path.read_text())
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    plugins = data.setdefault("plugin", [])
    if isinstance(plugins, list) and plugin_dir not in plugins:
        plugins.append(plugin_dir)
        cfg_path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"added {plugin_dir} to {cfg_path}")
PY
  fi
fi

# 5. Gemini CLI extension
if command -v gemini >/dev/null 2>&1; then
  say "gemini extension (ponytail)"
  if [[ -d "${HOME}/.gemini/extensions/ponytail" && ! -f "${HOME}/.gemini/extensions/ponytail/gemini-extension.json" ]]; then
    rm -rf "${HOME}/.gemini/extensions/ponytail"
  fi
  if [[ ! -f "${HOME}/.gemini/extensions/ponytail/gemini-extension.json" ]]; then
    mkdir -p "${HOME}/.cache"
    _gem_tmp="$(mktemp -d "${HOME}/.cache/ponytail-gemini.XXXXXX")"
    PONYTAIL_TMPS+=("$_gem_tmp")
    (
      cd "$_gem_tmp"
      GEMINI_CLI_TRUST_WORKSPACE=true gemini extensions uninstall ponytail >/dev/null 2>&1 || true
      GEMINI_CLI_TRUST_WORKSPACE=true gemini extensions install "$PONYTAIL_DIR" --consent >/dev/null 2>&1 \
        || warn "gemini extensions install ponytail failed"
    )
    rm -rf "$_gem_tmp"
    unset _gem_tmp
  fi
fi

# 6. Antigravity native plugin (~/.gemini/config/plugins/ponytail)
if command -v agy >/dev/null 2>&1 || [[ -d "${HOME}/.gemini/config" ]]; then
  AGY_PLUGIN_DIR="${HOME}/.gemini/config/plugins/ponytail"
  _agy_stage="$(mktemp -d "${TMPDIR:-/tmp}/ponytail-agy.XXXXXX")"
  PONYTAIL_TMPS+=("$_agy_stage")
  mkdir -p "$_agy_stage/ponytail/rules" "$_agy_stage/ponytail/skills"
  cat > "$_agy_stage/ponytail/plugin.json" <<'EOF'
{
  "name": "ponytail",
  "description": "Lazy senior dev mode for AI agents. The best code is the code you never wrote.",
  "homepage": "https://github.com/DietrichGebert/ponytail"
}
EOF
  cp -a "$PONYTAIL_DIR/AGENTS.md" "$_agy_stage/ponytail/rules/AGENTS.md"
  for _s in "${PONYTAIL_SKILLS[@]}"; do
    if [[ -d "$PONYTAIL_DIR/skills/$_s" ]]; then
      cp -a "$PONYTAIL_DIR/skills/$_s" "$_agy_stage/ponytail/skills/$_s"
    fi
  done
  unset _s
  if command -v agy >/dev/null 2>&1 && agy plugin install "$_agy_stage/ponytail" >/dev/null 2>&1; then
    say "installed Antigravity plugin via agy → $AGY_PLUGIN_DIR"
  else
    rm -rf "$AGY_PLUGIN_DIR"
    mkdir -p "$(dirname "$AGY_PLUGIN_DIR")"
    cp -a "$_agy_stage/ponytail" "$AGY_PLUGIN_DIR"
    say "staged Antigravity plugin → $AGY_PLUGIN_DIR"
  fi
  rm -rf "$_agy_stage"
  unset _agy_stage
fi

# 7. Kiro steering rule
if [[ -d "${HOME}/.kiro" && -f "$PONYTAIL_DIR/.kiro/steering/ponytail.md" ]]; then
  mkdir -p "${HOME}/.kiro/steering"
  cp -a "$PONYTAIL_DIR/.kiro/steering/ponytail.md" "${HOME}/.kiro/steering/ponytail.md"
  say "installed Kiro steering rule → ~/.kiro/steering/ponytail.md"
fi

# shellcheck source=lib/agent-skills.sh
source "$REPO_ROOT/scripts/lib/agent-skills.sh"
agent_skills_maybe_sync "$REPO_ROOT"

say "install-ponytail done"
echo "  commands: /ponytail [lite|full|ultra|off] | /ponytail-review | /ponytail-audit | /ponytail-debt"
