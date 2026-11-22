#!/usr/bin/env bash
# install-dash2dock.sh — Dash2Dock Animated (EGO #4994)
# https://github.com/icedman/dash2dock-lite
# Delegates verified EGO zip download + Shell-51 metadata patch to fetch-gnome-extensions.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UUID="dash2dock-lite@icedman.github.com"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/${UUID}"

GNOME_EXT_CURL="${DASH2DOCK_CURL:-${GNOME_EXT_CURL:-/usr/bin/curl}}" \
    bash "$REPO_ROOT/scripts/fetch-gnome-extensions.sh" --only "$UUID"

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions enable "$UUID" 2>/dev/null || true
fi

echo "✓ Dash2Dock installed → $EXT_DIR"
echo "  Reload GNOME Shell to activate (Wayland: log out → log in)."
echo "  Prefs: gnome-extensions prefs $UUID"
