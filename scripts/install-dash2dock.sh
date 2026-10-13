#!/usr/bin/env bash
# install-dash2dock.sh — Dash2Dock Animated (EGO #4994)
# https://github.com/icedman/dash2dock-lite
# AUR gnome-shell-extension-dash2dock-lite is stale; install from EGO zip.
# Upstream metadata lists Shell ≤50; we patch in 51 until EGO ships it.
# WARNING: metadata patch is unofficial — may clear OUT OF DATE without full API support.

set -euo pipefail

UUID="dash2dock-lite@icedman.github.com"
# EGO Shell-50 build (version_tag); override with DASH2DOCK_URL / DASH2DOCK_VERSION_TAG
VERSION_TAG="${DASH2DOCK_VERSION_TAG:-71180}"
VERSION="${DASH2DOCK_VERSION:-92}"
ZIP_URL="${DASH2DOCK_URL:-https://extensions.gnome.org/download-extension/${UUID}.shell-extension.zip?version_tag=${VERSION_TAG}}"
CURL_BIN="${DASH2DOCK_CURL:-/usr/bin/curl}"
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/${UUID}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/dash2dock.shell-extension.zip"

echo "Downloading Dash2Dock Animated (EGO tag ${VERSION_TAG}, ~v${VERSION})..."
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
    # Official zip still omits 51; allow load on current Arch gnome-shell
    if [[ -f "$EXT_DIR/metadata.json" ]]; then
        python3 - "$EXT_DIR/metadata.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    meta = json.load(f)
sv = list(meta.get("shell-version") or [])
if "51" not in sv:
    sv.append("51")
    meta["shell-version"] = sv
    with open(path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("patched metadata shell-version ← 51")
else:
    print("metadata already lists shell-version 51")
PY
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
# drop stale UUIDs
stale = {"clipd@devtochukwu"}
lst = [x for x in lst if x not in stale]
if uuid not in lst:
    lst.append(uuid)
gv = "[" + ", ".join("'" + x + "'" for x in lst) + "]"
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", gv])
print("enabled-extensions ←", uuid)
PY

gnome-extensions enable "$UUID" 2>/dev/null || true

echo "✓ Dash2Dock installed → $EXT_DIR"
echo "  UUID: $UUID (EGO ~v${VERSION} tag ${VERSION_TAG}; metadata allows Shell 51)"
echo "  Reload GNOME Shell to activate (Wayland: log out → log in)."
echo "  Prefs: gnome-extensions prefs $UUID"
