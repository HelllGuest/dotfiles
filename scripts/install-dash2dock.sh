#!/usr/bin/env bash
# install-dash2dock.sh — Dash2Dock Animated (EGO #4994) for GNOME 45–50
# https://github.com/icedman/dash2dock-lite
# AUR gnome-shell-extension-dash2dock-lite is stale (2022); install from EGO zip.

set -euo pipefail

UUID="dash2dock-lite@icedman.github.com"
# v92 supports GNOME Shell 50
VERSION="${DASH2DOCK_VERSION:-92}"
ZIP_URL="${DASH2DOCK_URL:-https://extensions.gnome.org/extension-data/dash2dock-liteicedman.github.com.v${VERSION}.shell-extension.zip}"
CURL_BIN="${DASH2DOCK_CURL:-/usr/bin/curl}"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/${UUID}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/dash2dock.shell-extension.zip"

echo "Downloading Dash2Dock Animated v${VERSION}..."
"$CURL_BIN" -fsSL -o "$ZIP" "$ZIP_URL"

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions install --force "$ZIP"
else
    mkdir -p "$EXT_DIR"
    unzip -qo "$ZIP" -d "$EXT_DIR"
fi

# Ensure readable perms + compiled schemas
if [[ -d "$EXT_DIR" ]]; then
    find "$EXT_DIR" -type d -exec chmod 755 {} +
    find "$EXT_DIR" -type f -exec chmod 644 {} +
    if [[ -d "$EXT_DIR/schemas" ]]; then
        glib-compile-schemas "$EXT_DIR/schemas"
    fi
fi

# Enable in gsettings (shell must reload before gnome-extensions sees it)
python3 - "$UUID" <<'PY'
import ast
import subprocess
import sys

uuid = sys.argv[1]
raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True
).strip()
s = raw.split(" ", 1)[-1] if raw.startswith("@as") else raw
lst = list(ast.literal_eval(s))
if uuid not in lst:
    lst.append(uuid)
gv = "[" + ", ".join("'" + x + "'" for x in lst) + "]"
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", gv])
print("enabled-extensions ←", uuid)
PY

gnome-extensions enable "$UUID" 2>/dev/null || true

echo "✓ Dash2Dock installed → $EXT_DIR"
echo "  UUID: $UUID (EGO v${VERSION})"
echo "  Reload GNOME Shell to activate (Wayland: log out → log in)."
echo "  Prefs: gnome-extensions prefs $UUID"
