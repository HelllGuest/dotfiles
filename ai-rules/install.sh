#!/usr/bin/env bash
# Installs the shared AI dev environment for Cursor, Antigravity, Kiro, Claude Code.
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
    if [[ ! -e "$src/$rel" ]]; then
      rm -f "$f"
    fi
  done < <(find "$dst" -type f ! -path '*/.git/*' -print0 2>/dev/null || true)
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

echo "==> Claude Code settings (merge telemetry + no co-author)"
mkdir -p "$HOME/.claude"
KIT_CLAUDE="$TARGET/claude-settings.json"
USER_CLAUDE="$HOME/.claude/settings.json"
if [[ ! -f "$USER_CLAUDE" ]]; then
  cp "$KIT_CLAUDE" "$USER_CLAUDE"
  echo "  wrote $USER_CLAUDE"
elif command -v jq >/dev/null 2>&1; then
  TMP_MERGE="$(mktemp)"
  # Kit wins on includeCoAuthoredBy + env.*; keep user's hooks/plugins/theme
  jq -s '
    .[0] as $user | .[1] as $kit |
    $user * {
      includeCoAuthoredBy: $kit.includeCoAuthoredBy,
      env: (($user.env // {}) + ($kit.env // {}))
    }
  ' "$USER_CLAUDE" "$KIT_CLAUDE" > "$TMP_MERGE"
  mv "$TMP_MERGE" "$USER_CLAUDE"
  echo "  merged kit telemetry/co-author flags into $USER_CLAUDE"
else
  echo "  ! jq missing; install jq, or merge $KIT_CLAUDE by hand"
fi

echo "==> VS Code family telemetry (Cursor / Antigravity / Kiro / VSCodium)"
TELEMETRY_KIT="$TARGET/vscode-family-telemetry.json"
merge_vscode_settings() {
  local settings="$1"
  local label="$2"
  mkdir -p "$(dirname "$settings")"
  if [[ ! -f "$settings" ]]; then
    cp "$TELEMETRY_KIT" "$settings"
    echo "  wrote $label"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ! jq missing; skip merge for $label"
    return
  fi
  TMP_VS="$(mktemp)"
  jq -s '.[0] * .[1]' "$settings" "$TELEMETRY_KIT" > "$TMP_VS"
  mv "$TMP_VS" "$settings"
  echo "  merged telemetry into $label"
}

# Discover common settings.json locations (create/merge only real User dirs)
while IFS= read -r spath; do
  [[ -n "$spath" ]] || continue
  merge_vscode_settings "$spath" "$spath"
done <<EOF
${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json
$HOME/.cursor/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Kiro/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json
EOF

# Optional: stow-managed VS Code settings if present in a dotfiles checkout
STOW_CODE="$HOME/dotfiles/stow/vscode/.config/Code/User/settings.json"
if [[ -f "$STOW_CODE" ]] || [[ -d "$(dirname "$STOW_CODE")" ]]; then
  merge_vscode_settings "$STOW_CODE" "dotfiles stow vscode settings"
fi

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
chmod +x "$TARGET/bin/agentsync"
echo "  agentsync ready (ensure ~/.local/bin is on PATH)"

echo "==> Global git hooks (strip + Conventional Commits + prefill + pre-push)"
echo "  WARN: core.hooksPath replaces ALL repo .git/hooks (husky/pre-commit ignored)."
echo "  Unset with: git config --global --unset core.hooksPath"
git config --global core.hooksPath "$TARGET/git-hooks"
chmod +x "$TARGET/git-hooks/commit-msg" \
  "$TARGET/git-hooks/prepare-commit-msg" \
  "$TARGET/git-hooks/pre-push" 2>/dev/null || true
echo "  git config --global core.hooksPath -> $TARGET/git-hooks"

# Sync this repo's AGENTS bridge if we are installing from a git checkout
if [[ -d "$HERE/../.git" ]] || [[ -d "$HERE/.git" ]]; then
  ROOT="$(cd "$HERE/.." && pwd)"
  if [[ -d "$ROOT/.git" ]]; then
    echo "==> agentsync current checkout ($ROOT)"
    "$TARGET/bin/agentsync" "$ROOT" || true
  fi
fi

cat <<EOF

==> Done. Day-to-day:

  agentsync /path/to/project     # AGENTS.md + CLAUDE.md (@AGENTS.md) + Cursor pointer
  # In chat: verify | double check | refactor | test | debug | optimize | explain | docs | security | commit | rephrase

Edit rules only in: $TARGET
(or edit the source tree and re-run install.sh)
EOF
