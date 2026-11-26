#!/usr/bin/env bash
# install-dash2dock.sh — Dash2Dock Animated (EGO #4994)
# https://github.com/icedman/dash2dock-lite
# Delegates verified EGO zip download + Shell-51 metadata patch to fetch-gnome-extensions.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UUID="dash2dock-lite@icedman.github.com"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/${UUID}"

GNOME_EXT_CURL="${DASH2DOCK_CURL:-${GNOME_EXT_CURL:-/usr/bin/curl}}" \
    bash "$REPO_ROOT/desktop/scripts/fetch-gnome-extensions.sh" --only "$UUID"

# Register in enabled-extensions directly (on Wayland, gnome-extensions enable
# cannot see a freshly downloaded extension until Shell reloads on re-login).
if command -v gsettings >/dev/null 2>&1; then
    python3 - "$UUID" <<'PY'
import ast, subprocess, sys

uuid = sys.argv[1]
try:
    raw = subprocess.check_output(
        ["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True
    ).strip()
except subprocess.CalledProcessError:
    raise SystemExit(0)
s = raw.split(" ", 1)[-1] if raw.startswith("@as") else raw
try:
    lst = ast.literal_eval(s)
except (SyntaxError, ValueError, MemoryError, TypeError):
    raise SystemExit(0)
if not isinstance(lst, list):
    raise SystemExit(0)
if uuid not in lst:
    lst.append(uuid)
    gv = "[" + ", ".join(repr(x) for x in lst) + "]"
    subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", gv])
PY
fi

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions enable "$UUID" 2>/dev/null || true
fi

echo "✓ Dash2Dock installed → $EXT_DIR"
echo "  Reload GNOME Shell to activate (Wayland: log out → log in)."
echo "  Prefs: gnome-extensions prefs $UUID"
