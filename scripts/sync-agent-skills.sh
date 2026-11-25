#!/usr/bin/env bash
# sync-agent-skills.sh — reproducible agent skill layout (X1 / P15 / any host)
#
# 1) Install/sync the shared ai-rules kit → ~/dev/ai-rules (Claude/Kiro skills + hooks)
# 2) Hub at ~/.agents/skills: kit skills + keep existing (caveman, REA, Cloudflare, …)
# 3) Mirror hub → Claude, Cursor, OpenCode, Kimi, Gemini CLI, Antigravity, Kiro, and Codex skill roots (symlinks)
# 4) Sync global rules (AGENTS.md / CLAUDE.md / GEMINI.md) across agent roots
#
# Soft link (Claude/Cursor/OpenCode/Gemini/Antigravity/Kiro/Codex): skip real non-symlink dirs (vendor /
# caveman-owned installs under OpenCode).
# Force link (Kimi only): replace real dirs with hub symlinks so stale
# copies cannot shadow the hub.
#
# Usage:
#   bash scripts/sync-agent-skills.sh
#   AI_RULES_TARGET=~/dev/ai-rules bash scripts/sync-agent-skills.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AI_RULES_SRC="${REPO_ROOT}/ai-rules"
AI_RULES_TARGET="${AI_RULES_TARGET:-$HOME/dev/ai-rules}"
AGENTS="${HOME}/.agents/skills"
CLAUDE="${HOME}/.claude/skills"
CURSOR="${HOME}/.cursor/skills"
OPENCODE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
# skills CLI kimi-cli global path + Kimi Code home brand skills
KIMI_AGENTS="${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills"
KIMI_CODE="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"
GEMINI_SKILLS="${HOME}/.gemini/skills"
AGY_SKILLS="${HOME}/.gemini/config/skills"
KIRO_SKILLS="${HOME}/.kiro/skills"
CODEX_SKILLS="${HOME}/.codex/skills"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

[[ -x "$AI_RULES_SRC/install.sh" ]] || die "missing $AI_RULES_SRC/install.sh (clone full dotfiles repo)"

# Ensure skill roots are real dirs before install.sh runs so mirroring
# hub skills never writes back into $AI_RULES_TARGET/skills.
for _sroot in "$CLAUDE" "$KIRO_SKILLS" "$GEMINI_SKILLS" "$AGY_SKILLS" "$CODEX_SKILLS"; do
  if [[ -L "$_sroot" ]]; then
    rm -f "$_sroot"
  fi
done
unset _sroot
mkdir -p "$AGENTS" "$CLAUDE" "$CURSOR" "$OPENCODE" "$KIMI_AGENTS" "$KIMI_CODE" \
  "$GEMINI_SKILLS" "$AGY_SKILLS" "$KIRO_SKILLS" "$CODEX_SKILLS"

say "ai-rules kit → $AI_RULES_TARGET"
bash "$AI_RULES_SRC/install.sh" "$AI_RULES_TARGET"

KIT_SKILLS="${AI_RULES_TARGET}/skills"
[[ -d "$KIT_SKILLS" ]] || die "kit skills missing: $KIT_SKILLS"

link_skill() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    ln -sfn "$src" "$dest"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    # Keep real dirs (vendor installs); do not clobber
    return 1
  fi
  ln -sfn "$src" "$dest"
  return 0
}

# Replace real dirs/files with a symlink to the hub (Kimi only).
force_link_skill() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    ln -sfn "$src" "$dest"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    rm -rf "$dest"
  fi
  ln -sfn "$src" "$dest"
  return 0
}

say "kit skills → $AGENTS (+ cursor)"
shopt -s nullglob
for skill_dir in "$KIT_SKILLS"/*/; do
  name="$(basename "$skill_dir")"
  src="$KIT_SKILLS/$name"
  if link_skill "$src" "$AGENTS/$name"; then
    echo "  agents/$name"
  else
    echo "  skip agents/$name (exists, not symlink)"
  fi
  if link_skill "$src" "$CURSOR/$name"; then
    echo "  cursor/$name"
  fi
done
shopt -u nullglob

# Host skills from this repo — keep agents copies fresh
for _host_skill in ghidra-cli-host obscura-host; do
  HOST_SKILL="${REPO_ROOT}/skills/${_host_skill}"
  if [[ -f "$HOST_SKILL/SKILL.md" ]]; then
    rm -rf "${AGENTS:?}/${_host_skill}"
    cp -a "$HOST_SKILL" "${AGENTS}/${_host_skill}"
    echo "  refreshed agents/${_host_skill}"
  fi
done
unset _host_skill HOST_SKILL

say "mirror $AGENTS → claude + cursor + opencode + kimi + gemini + antigravity + kiro + codex"
shopt -s nullglob
for skill_dir in "$AGENTS"/*/; do
  name="$(basename "$skill_dir")"
  # Resolve to absolute path for stable symlinks
  src="$(readlink -f "$skill_dir" 2>/dev/null || printf '%s' "$skill_dir")"
  [[ -d "$src" ]] || continue
  for dest_root in "$CLAUDE" "$CURSOR" "$GEMINI_SKILLS" "$AGY_SKILLS" "$KIRO_SKILLS" "$CODEX_SKILLS"; do
    dest="$dest_root/$name"
    if link_skill "$src" "$dest"; then
      echo "  $(basename "$(dirname "$dest_root")")-$(basename "$dest_root")/$name"
    fi
  done
  # OpenCode: soft link only — caveman installer owns real skill dirs here
  dest="$OPENCODE/$name"
  if link_skill "$src" "$dest"; then
    echo "  opencode/$name"
  else
    echo "  skip opencode/$name (exists, not symlink)"
  fi
  # Kimi: force-link so hub always wins over stale copies
  for dest_root in "$KIMI_AGENTS" "$KIMI_CODE"; do
    dest="$dest_root/$name"
    if force_link_skill "$src" "$dest"; then
      case "$dest_root" in
        "$KIMI_AGENTS") label="config-agents/$name" ;;
        "$KIMI_CODE") label="kimi-code/$name" ;;
      esac
      echo "  $label"
    fi
  done
done
shopt -u nullglob

# Sync global rules (AGENTS.md / CLAUDE.md / GEMINI.md) across agent roots
if [[ -f "${AI_RULES_TARGET}/AGENTS.md" ]]; then
  say "sync global AGENTS.md / CLAUDE.md / GEMINI.md rules"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.agents/AGENTS.md"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.claude/AGENTS.md"
  if [[ ! -f "${HOME}/.claude/CLAUDE.md" ]]; then
    printf '@AGENTS.md\n' > "${HOME}/.claude/CLAUDE.md"
  fi
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.gemini/AGENTS.md"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.gemini/GEMINI.md"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.gemini/config/AGENTS.md"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.gemini/config/GEMINI.md"
  ln -sfn "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.codex/AGENTS.md"
  cp -a "${AI_RULES_TARGET}/AGENTS.md" "${KIMI_CODE_HOME:-$HOME/.kimi-code}/AGENTS.md"
  mkdir -p "${HOME}/.kimi"
  ln -sfn "${KIMI_CODE_HOME:-$HOME/.kimi-code}/AGENTS.md" "${HOME}/.kimi/AGENTS.md"
  mkdir -p "${HOME}/.kiro/steering"
  cp -a "${AI_RULES_TARGET}/AGENTS.md" "${HOME}/.kiro/steering/agents.md"
  if [[ -d "${HOME}/.cursor" ]]; then
    mkdir -p "${HOME}/.cursor/rules"
    cp -a "${AI_RULES_TARGET}/cursor-mdc/00-agents-pointer.mdc" "${HOME}/.cursor/rules/00-agents-pointer.mdc"
  fi
  # OpenCode global AGENTS.md: keep shared ai-rules above any fenced <!-- caveman-begin --> block
  python3 - "${AI_RULES_TARGET}/AGENTS.md" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md" <<'PY'
import sys
from pathlib import Path

base_path, oc_path = Path(sys.argv[1]), Path(sys.argv[2])
base_text = base_path.read_text().strip()
oc_path.parent.mkdir(parents=True, exist_ok=True)
caveman_block = ""
if oc_path.is_file() and not oc_path.is_symlink():
    existing = oc_path.read_text()
    b_idx = existing.find("<!-- caveman-begin -->")
    e_idx = existing.find("<!-- caveman-end -->")
    if b_idx != -1 and e_idx != -1 and e_idx > b_idx:
        caveman_block = existing[b_idx : e_idx + len("<!-- caveman-end -->")].strip()
if oc_path.is_symlink():
    oc_path.unlink()
merged = base_text + ("\n\n" + caveman_block if caveman_block else "") + "\n"
oc_path.write_text(merged)
PY
fi

_skill_count() { find "$1" -mindepth 1 -maxdepth 1 | wc -l; }
echo
echo "agents=$(_skill_count "$AGENTS") claude=$(_skill_count "$CLAUDE") cursor=$(_skill_count "$CURSOR") opencode=$(_skill_count "$OPENCODE") kimi-agents=$(_skill_count "$KIMI_AGENTS") kimi-code=$(_skill_count "$KIMI_CODE") gemini=$(_skill_count "$GEMINI_SKILLS") agy=$(_skill_count "$AGY_SKILLS") kiro=$(_skill_count "$KIRO_SKILLS") codex=$(_skill_count "$CODEX_SKILLS")"
say "sync-agent-skills done"
