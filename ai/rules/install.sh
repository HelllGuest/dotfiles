#!/usr/bin/env bash
# Installs the shared AI dev environment for Cursor, Antigravity, Gemini CLI, Kiro, Claude Code.
# Safe to re-run. Canonical kit: ~/dev/ai-rules (override: ./install.sh /path)
set -euo pipefail

TARGET="${1:-$HOME/dev/ai-rules}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Sync kit -> $TARGET"
mkdir -p "$(dirname "$TARGET")"

# Match rsync -a --delete --exclude '.git/' --exclude '*.bak'
# (rsync does not delete excluded paths without --delete-excluded).
sync_kit_cp() {
  local src="$1" dst="$2" rel
  mkdir -p "$dst"
  cp -a "$src"/. "$dst"/
  while IFS= read -r -d '' f; do
    rel="${f#"$dst"/}"
    # Match rsync: --exclude '.git/' --exclude '*.bak' (keep those on dst)
    case "$rel" in
      .git|.git/*) continue ;;
    esac
    [[ "$rel" == *.bak ]] && continue
    if [[ ! -e "$src/$rel" && ! -L "$src/$rel" ]]; then
      rm -f "$f"
    fi
  done < <(find "$dst" \( -type f -o -type l \) ! -path '*/.git/*' -print0 2>/dev/null || true)
  # Drop empty dirs absent from src (deepest first); never touch .git
  while IFS= read -r -d '' d; do
    rel="${d#"$dst"/}"
    [[ -z "$rel" || "$rel" == "." ]] && continue
    case "$rel" in
      .git|.git/*) continue ;;
    esac
    if [[ ! -e "$src/$rel" ]]; then
      rmdir "$d" 2>/dev/null || true
    fi
  done < <(find "$dst" -depth -type d ! -path '*/.git' ! -path '*/.git/*' -print0 2>/dev/null || true)
}

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude '.git/' \
    --exclude '*.bak' \
    "$HERE/" "$TARGET/"
else
  echo "  ! rsync missing; using cp -a + orphan cleanup (same excludes as rsync)"
  sync_kit_cp "$HERE" "$TARGET"
fi
chmod +x "$TARGET/install.sh" "$TARGET/bin/agentsync" \
  "$TARGET/git-hooks/commit-msg" \
  "$TARGET/git-hooks/prepare-commit-msg" \
  "$TARGET/git-hooks/pre-commit" \
  "$TARGET/git-hooks/pre-push" 2>/dev/null || true
echo "  synced from $HERE"

echo "==> Skills: Claude Code + Kiro"
mkdir -p "$HOME/.claude" "$HOME/.kiro"
SRC_SKILLS="$TARGET/skills"

# Missing path: whole-dir symlink
# Symlink: retarget to kit
# Real directory: per-skill symlinks (keeps find-skills / caveman / etc.)
link_skills() {
  local dst="$1"
  local name entry skill_dir

  if [ -L "$dst" ]; then
    rm "$dst"
    ln -s "$SRC_SKILLS" "$dst"
    echo "  retargeted $dst -> $SRC_SKILLS"
    return
  fi

  if [ -d "$dst" ]; then
    echo "  merging into existing dir $dst"
    for skill_dir in "$SRC_SKILLS"/*/; do
      [ -d "$skill_dir" ] || continue
      name="$(basename "$skill_dir")"
      entry="$dst/$name"
      if [ -L "$entry" ] || [ ! -e "$entry" ]; then
        ln -sfn "$SRC_SKILLS/$name" "$entry"
        echo "    $name -> $SRC_SKILLS/$name"
      else
        echo "    ! $entry exists and is not a symlink; skip"
      fi
    done
    return
  fi

  ln -s "$SRC_SKILLS" "$dst"
  echo "  linked $dst -> $SRC_SKILLS"
}

link_skills "$HOME/.claude/skills"
link_skills "$HOME/.kiro/skills"

# Cursor keeps a mixed ~/.cursor/skills tree (many third-party skills). Always
# retarget only the kit skill names so AGENTS procedures stay in sync.
echo "==> Skills: Cursor (~/.cursor/skills kit names)"
CURSOR_SKILLS="${HOME}/.cursor/skills"
if [[ -d $CURSOR_SKILLS || -L $CURSOR_SKILLS ]]; then
  mkdir -p "$CURSOR_SKILLS"
  for skill_dir in "$SRC_SKILLS"/*/; do
    [[ -d $skill_dir ]] || continue
    name="$(basename "$skill_dir")"
    entry="$CURSOR_SKILLS/$name"
    rm -rf "$entry"
    ln -sfn "$SRC_SKILLS/$name" "$entry"
    echo "    $name -> $SRC_SKILLS/$name"
  done
else
  echo "  skip ($CURSOR_SKILLS missing)"
fi

# Google AI tools (Gemini CLI + Antigravity): keep real skill dirs (never whole-dir
# symlinks) so hub mirroring in sync-agent-skills.sh never writes back into the kit.
echo "==> Google AI: Gemini CLI + Antigravity rules & skills"
for _groot in "$HOME/.gemini/skills" "$HOME/.gemini/config/skills"; do
  [[ -L "$_groot" ]] && rm -f "$_groot"
  mkdir -p "$_groot"
  link_skills "$_groot"
done
unset _groot
ln -sfn "$TARGET/AGENTS.md" "$HOME/.gemini/AGENTS.md"
ln -sfn "$TARGET/AGENTS.md" "$HOME/.gemini/GEMINI.md"
ln -sfn "$TARGET/AGENTS.md" "$HOME/.gemini/config/AGENTS.md"
ln -sfn "$TARGET/AGENTS.md" "$HOME/.gemini/config/GEMINI.md"

echo "==> OpenAI Codex: rules & skills"
[[ -L "$HOME/.codex/skills" ]] && rm -f "$HOME/.codex/skills"
mkdir -p "$HOME/.codex/skills"
ln -sfn "$TARGET/AGENTS.md" "$HOME/.codex/AGENTS.md"
link_skills "$HOME/.codex/skills"

KIT_FAILED=()
kit_fail() { echo "  ✗ $*" >&2; KIT_FAILED+=("$*"); }

# Shared telemetry merge helpers (also sourced by security/lib/telemetry.sh).
# shellcheck source=lib/vscode-settings-merge.sh
source "$TARGET/lib/vscode-settings-merge.sh"

echo "==> Gemini CLI settings (telemetry opt-out)"
KIT_GEMINI="$TARGET/gemini-settings.json"
USER_GEMINI="$HOME/.gemini/settings.json"
if [[ ! -s "$USER_GEMINI" ]]; then
  gemini_merge_settings_telemetry "$USER_GEMINI" "$KIT_GEMINI"
  echo "  wrote $USER_GEMINI"
elif ! command -v jq >/dev/null 2>&1; then
  kit_fail "jq missing: telemetry opt-outs not merged into $USER_GEMINI (sudo pacman -S jq)"
elif gemini_merge_settings_telemetry "$USER_GEMINI" "$KIT_GEMINI"; then
  echo "  merged telemetry opt-outs into $USER_GEMINI"
else
  kit_fail "failed to merge telemetry opt-outs into $USER_GEMINI"
fi

echo "==> Claude Code settings (merge telemetry + no co-author)"
mkdir -p "$HOME/.claude"
KIT_CLAUDE="$TARGET/claude-settings.json"
USER_CLAUDE="$HOME/.claude/settings.json"
if [[ ! -s "$USER_CLAUDE" ]]; then
  claude_merge_settings_telemetry "$USER_CLAUDE" "$KIT_CLAUDE"
  echo "  wrote $USER_CLAUDE"
elif ! command -v jq >/dev/null 2>&1; then
  kit_fail "jq missing: telemetry/co-author flags not merged into $USER_CLAUDE (sudo pacman -S jq)"
elif claude_merge_settings_telemetry "$USER_CLAUDE" "$KIT_CLAUDE"; then
  echo "  merged kit telemetry/co-author flags into $USER_CLAUDE"
else
  kit_fail "failed to merge kit telemetry/co-author flags into $USER_CLAUDE"
fi

echo "==> VS Code family telemetry (Cursor / Antigravity / Kiro / VSCodium)"
TELEMETRY_KIT="$TARGET/vscode-family-telemetry.json"
# A step that could not do its job is reported and fails the run at the end.
merge_vscode_settings() {
  local settings="$1"
  local label="$2"
  local user_dir parent_ide
  user_dir="$(dirname "$settings")"
  parent_ide="$(dirname "$user_dir")"
  # Create User/ only if the IDE config root already exists (no orphan trees).
  if [[ ! -d "$user_dir" && -d "$parent_ide" ]]; then
    mkdir -p "$user_dir"
  fi
  if ! command -v jq >/dev/null 2>&1; then
    kit_fail "jq missing: telemetry opt-outs not merged into $label (sudo pacman -S jq)"
    return
  fi
  if vscode_merge_settings_telemetry "$settings" "$TELEMETRY_KIT"; then
    if [[ -f "$settings" ]]; then
      echo "  merged telemetry into $label"
    fi
  fi
}

# Discover common settings.json locations (IDE root or User/ must exist)
while IFS= read -r spath; do
  [[ -n "$spath" ]] || continue
  _user="$(dirname "$spath")"
  _ide="$(dirname "$_user")"
  [[ -d "$_user" || -d "$_ide" ]] || continue
  unset _user _ide
  merge_vscode_settings "$spath" "$spath"
done < <(vscode_settings_targets)

# Optional: stow-managed VS Code / VSCodium settings if present in a checkout
for STOW_SETTINGS in \
  "$HOME/dotfiles/stow/vscode/.config/Code/User/settings.json" \
  "$HOME/dotfiles/stow/vscode/.config/VSCodium/User/settings.json"
do
  if [[ -f "$STOW_SETTINGS" ]]; then
    merge_vscode_settings "$STOW_SETTINGS" "dotfiles stow $(basename "$(dirname "$(dirname "$(dirname "$STOW_SETTINGS")")")") settings"
  fi
done
unset STOW_SETTINGS

echo "==> Kiro CLI telemetry"
if command -v kiro-cli >/dev/null 2>&1; then
  kiro-cli settings telemetry.enabled false || true
  echo "  set telemetry.enabled=false via kiro-cli"
else
  echo "  kiro-cli not on PATH; skip"
fi

echo "==> agentsync helper -> ~/.local/bin"
mkdir -p "$HOME/.local/bin"
ln -sfn "$TARGET/bin/agentsync" "$HOME/.local/bin/agentsync"
echo "  agentsync ready (ensure ~/.local/bin is on PATH)"

echo "==> Global git hooks (strip + Conventional Commits + prefill + pre-commit + pre-push)"
echo "  WARN: core.hooksPath replaces ALL repo .git/hooks (husky/pre-commit ignored)."
echo "  Unset with: git config --global --unset core.hooksPath"
git config --global core.hooksPath "$TARGET/git-hooks"
echo "  git config --global core.hooksPath -> $TARGET/git-hooks"

# Sync this repo's AGENTS bridge if we are installing from a git checkout
if [[ -d "$HERE/../../.git" ]]; then
  ROOT="$(cd "$HERE/../.." && pwd)"
  echo "==> agentsync current checkout ($ROOT)"
  "$TARGET/bin/agentsync" "$ROOT" || kit_fail "agentsync failed for $ROOT"
elif [[ -d "$HERE/../.git" ]] || [[ -d "$HERE/.git" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
  if [[ -d "$ROOT/.git" ]]; then
    echo "==> agentsync current checkout ($ROOT)"
    "$TARGET/bin/agentsync" "$ROOT" || kit_fail "agentsync failed for $ROOT"
  fi
fi

cat <<EOF

==> Done. Day-to-day:

  agentsync /path/to/project     # AGENTS.md + CLAUDE.md/GEMINI.md (@AGENTS.md) + Cursor pointer
  # In chat: verify | double check | refactor | test | debug | optimize | explain | docs | security | commit | rephrase

Edit rules only in: $TARGET
(or edit the source tree and re-run install.sh)
EOF
if [[ ${#KIT_FAILED[@]} -gt 0 ]]; then
  echo "==> Finished with ${#KIT_FAILED[@]} failure(s):" >&2
  printf '  - %s\n' "${KIT_FAILED[@]}" >&2
  exit 1
fi
