#!/usr/bin/env bash
# sync-agent-skills.sh — reproducible agent skill layout (X1 / P15 / any host)
#
# 1) Install/sync the shared ai-rules kit → ~/dev/ai-rules (Claude/Kiro skills + hooks)
# 2) Hub at ~/.agents/skills: kit skills + keep existing (caveman, REA, Cloudflare, …)
# 3) Mirror hub → Claude, Cursor, OpenCode, and Kimi skill roots (symlinks)
#
# Soft link (Claude/Cursor/OpenCode): skip real non-symlink dirs (vendor /
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

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

[[ -x "$AI_RULES_SRC/install.sh" ]] || die "missing $AI_RULES_SRC/install.sh (clone full dotfiles repo)"

say "ai-rules kit → $AI_RULES_TARGET"
bash "$AI_RULES_SRC/install.sh" "$AI_RULES_TARGET"

KIT_SKILLS="${AI_RULES_TARGET}/skills"
[[ -d "$KIT_SKILLS" ]] || die "kit skills missing: $KIT_SKILLS"

mkdir -p "$AGENTS" "$CLAUDE" "$CURSOR" "$OPENCODE" "$KIMI_AGENTS" "$KIMI_CODE"

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

# Replace real dirs/files with a symlink to the hub (OpenCode/Kimi only).
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

# Host skill from this repo (ghidra-cli-host) — keep agents copy fresh
HOST_SKILL="${REPO_ROOT}/skills/ghidra-cli-host"
if [[ -f "$HOST_SKILL/SKILL.md" ]]; then
  rm -rf "${AGENTS}/ghidra-cli-host"
  cp -a "$HOST_SKILL" "${AGENTS}/ghidra-cli-host"
  echo "  refreshed agents/ghidra-cli-host"
fi

say "mirror $AGENTS → claude + cursor + opencode + kimi"
shopt -s nullglob
for skill_dir in "$AGENTS"/*/; do
  name="$(basename "$skill_dir")"
  # Resolve to absolute path for stable symlinks
  src="$(readlink -f "$skill_dir" 2>/dev/null || printf '%s' "$skill_dir")"
  [[ -d "$src" ]] || continue
  for dest_root in "$CLAUDE" "$CURSOR"; do
    dest="$dest_root/$name"
    if link_skill "$src" "$dest"; then
      echo "  $(basename "$dest_root")/$name"
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

echo
echo "agents=$(find "$AGENTS" -mindepth 1 -maxdepth 1 | wc -l) claude=$(find "$CLAUDE" -mindepth 1 -maxdepth 1 | wc -l) cursor=$(find "$CURSOR" -mindepth 1 -maxdepth 1 | wc -l) opencode=$(find "$OPENCODE" -mindepth 1 -maxdepth 1 | wc -l) kimi-agents=$(find "$KIMI_AGENTS" -mindepth 1 -maxdepth 1 | wc -l) kimi-code=$(find "$KIMI_CODE" -mindepth 1 -maxdepth 1 | wc -l)"
say "sync-agent-skills done"
