#!/usr/bin/env bash
# install-caveman.sh — JuliusBrussee/caveman for all detected agents (X1 / P15)
#
# Pins release tag v4.0.1. Downloads the installer, verifies SHA-256, optionally
# dry-runs, then installs plugins/skills/hooks for every agent present.
# Safe to re-run.
#
# Env:
#   CAVEMAN_TAG              override tag (default v4.0.1; must match SHA)
#   CAVEMAN_INSTALL_SHA256   override expected digest of install.sh
#   CAVEMAN_DRY_RUN=1        run upstream --dry-run only
#   SKIP_SKILL_SYNC=1        skip sync-agent-skills.sh (install.sh batches sync)
#
# Usage:
#   bash scripts/install-caveman.sh
#   CAVEMAN_DRY_RUN=1 bash scripts/install-caveman.sh

set -euo pipefail

CAVEMAN_TAG="${CAVEMAN_TAG:-v4.0.1}"
# sha256 of https://raw.githubusercontent.com/JuliusBrussee/caveman/v4.0.1/install.sh
CAVEMAN_INSTALL_SHA256="${CAVEMAN_INSTALL_SHA256:-c129b946a1f7f2e9eeeff5c1a747d7b43b2630c6b9e5fc7aa8297cece9cd3804}"
INSTALL_URL="https://raw.githubusercontent.com/JuliusBrussee/caveman/${CAVEMAN_TAG}/install.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

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
  bash "$TMP" --dry-run
  exit 0
fi

say "install caveman for detected agents"
bash "$TMP"

# Ensure Claude marketplace + plugin if claude CLI exists (idempotent)
if command -v claude >/dev/null 2>&1; then
  say "claude plugin marketplace + caveman@caveman (best-effort)"
  claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
  claude plugin install caveman@caveman 2>/dev/null || true
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${SKIP_SKILL_SYNC:-0}" != "1" && -f "$REPO_ROOT/scripts/sync-agent-skills.sh" ]]; then
  say "mirror skills into agents/claude/cursor hubs"
  bash "$REPO_ROOT/scripts/sync-agent-skills.sh" || true
fi

say "install-caveman done"
echo "  activate in chat: /caveman   (or /ultracave /megacave)"
echo "  stop: stop caveman | normal mode"
echo "  status file (Claude): ~/.claude/.caveman-active"
