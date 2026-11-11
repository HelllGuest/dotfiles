#!/usr/bin/env bash
# install-caveman.sh — JuliusBrussee/caveman for all detected agents (X1 / P15)
#
# Pins release tag v4.1.0. Downloads the installer, verifies SHA-256, optionally
# dry-runs, then installs plugins/skills/hooks for every agent present.
# Safe to re-run.
#
# Env:
#   CAVEMAN_TAG              override tag (default v4.1.0; must match SHA)
#   CAVEMAN_INSTALL_SHA256   override expected digest of install.sh
#   CAVEMAN_DRY_RUN=1        run upstream --dry-run only
#   SKIP_SKILL_SYNC=1        skip sync-agent-skills.sh (install.sh batches sync)
#
# Usage:
#   bash scripts/install-caveman.sh
#   CAVEMAN_DRY_RUN=1 bash scripts/install-caveman.sh

set -euo pipefail

export PATH="${HOME}/.opencode/bin:${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

CAVEMAN_TAG="${CAVEMAN_TAG:-v4.1.0}"
# sha256 of https://raw.githubusercontent.com/JuliusBrussee/caveman/v4.1.0/install.sh
CAVEMAN_INSTALL_SHA256="${CAVEMAN_INSTALL_SHA256:-2e39b2a9b4ce47620757abc8a55ad33a23dd65217f8a998135108f92f83c00a1}"
INSTALL_URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/${CAVEMAN_TAG}/install.sh"
CAVEMAN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/caveman"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v curl >/dev/null 2>&1 || die "curl required"
command -v npm >/dev/null 2>&1 || die "npm required (fnm/node first)"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum required"

say "fetch caveman installer ${CAVEMAN_TAG}"
curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP" "$INSTALL_URL"
chmod +x "$TMP"

got="$(sha256sum "$TMP" | awk '{print $1}')"
if [[ "$got" != "$CAVEMAN_INSTALL_SHA256" ]]; then
  die "caveman install.sh SHA-256 mismatch (got $got want $CAVEMAN_INSTALL_SHA256). Refusing to run. If you bumped CAVEMAN_TAG, refresh CAVEMAN_INSTALL_SHA256."
fi
say "SHA-256 ok"

if [[ "${CAVEMAN_DRY_RUN:-0}" == "1" ]]; then
  say "dry-run"
  bash "$TMP" --dry-run --non-interactive
  exit 0
fi

# Clear hub symlinks in OpenCode skills so Caveman's owned-install journal can write real dirs
OPENCODE_SKILLS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
if [[ -d "$OPENCODE_SKILLS" ]]; then
  for _s in caveman ultracave megacave caveman-commit caveman-review caveman-help \
            caveman-stats caveman-compress cavecrew; do
    [[ -L "$OPENCODE_SKILLS/$_s" ]] && rm -f "$OPENCODE_SKILLS/$_s"
  done
  unset _s
fi

# Keep a pinned local clone at ~/.local/share/caveman so OpenCode/Cursor/Antigravity/Claude
# hooks and plugins have stable on-disk files without repeated npx git clones.
if command -v git >/dev/null 2>&1; then
  mkdir -p "$(dirname "$CAVEMAN_DIR")"
  if [[ -d "$CAVEMAN_DIR/.git" ]]; then
    git -C "$CAVEMAN_DIR" fetch --depth 1 origin "refs/tags/${CAVEMAN_TAG}:refs/tags/${CAVEMAN_TAG}" >/dev/null 2>&1 || true
    git -C "$CAVEMAN_DIR" checkout -B main "${CAVEMAN_TAG}" >/dev/null 2>&1 || true
  else
    rm -rf "$CAVEMAN_DIR"
    git clone --depth 1 --branch "${CAVEMAN_TAG}" https://github.com/JuliusBrussee/caveman.git "$CAVEMAN_DIR" >/dev/null 2>&1 || true
    git -C "$CAVEMAN_DIR" checkout -B main "${CAVEMAN_TAG}" >/dev/null 2>&1 || true
  fi
fi

say "install caveman for detected agents"
if [[ -f "$CAVEMAN_DIR/installer/install.js" ]]; then
  CAVEMAN_REF="$CAVEMAN_TAG" node "$CAVEMAN_DIR/installer/install.js" --non-interactive --force \
    || bash "$TMP" --non-interactive --force
else
  bash "$TMP" --non-interactive --force
fi

# Ensure Claude marketplace + plugin if claude CLI exists (use ~/.claude/tmp to avoid EXDEV across /tmp tmpfs)
if command -v claude >/dev/null 2>&1; then
  say "claude plugin marketplace + caveman@caveman (best-effort)"
  mkdir -p "${HOME}/.claude/tmp"
  TMPDIR="${HOME}/.claude/tmp" claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
  TMPDIR="${HOME}/.claude/tmp" claude plugin install -y caveman@caveman 2>/dev/null || true
  rmdir "${HOME}/.claude/tmp" 2>/dev/null || true
fi

# Stage native Antigravity plugin under ~/.gemini/config/plugins/caveman when agy CLI did not already install it
if [[ -d "$CAVEMAN_DIR/skills" && -f "$CAVEMAN_DIR/src/rules/caveman-activate.md" ]]; then
  AGY_PLUGIN_DIR="${HOME}/.gemini/config/plugins/caveman"
  if ! command -v agy >/dev/null 2>&1 || [[ ! -f "$AGY_PLUGIN_DIR/plugin.json" ]]; then
    mkdir -p "$AGY_PLUGIN_DIR/rules" "$AGY_PLUGIN_DIR/skills"
    cat > "$AGY_PLUGIN_DIR/plugin.json" <<'EOF'
{
  "name": "caveman",
  "description": "Caveman: terse replies, every technical fact kept",
  "homepage": "https://github.com/JuliusBrussee/caveman"
}
EOF
    cp -a "$CAVEMAN_DIR/src/rules/caveman-activate.md" "$AGY_PLUGIN_DIR/rules/AGENTS.md"
    for _s in caveman ultracave megacave caveman-commit caveman-review caveman-help \
              caveman-stats caveman-compress cavecrew; do
      if [[ -d "$CAVEMAN_DIR/skills/$_s" ]]; then
        rm -rf "$AGY_PLUGIN_DIR/skills/$_s"
        cp -a "$CAVEMAN_DIR/skills/$_s" "$AGY_PLUGIN_DIR/skills/$_s"
      fi
    done
    unset _s
    say "staged Antigravity plugin → $AGY_PLUGIN_DIR"
  fi
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/agent-skills.sh
source "$REPO_ROOT/scripts/lib/agent-skills.sh"
agent_skills_maybe_sync "$REPO_ROOT"

say "install-caveman done"
echo "  activate in chat: /caveman   (or /ultracave /megacave)"
echo "  stop: stop caveman | normal mode"
echo "  status file (Claude): ~/.claude/.caveman-active"
