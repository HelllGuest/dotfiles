#!/usr/bin/env bash
# install-extensions.sh — fetch missing zips (optional) then enable gnome/extensions.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_FILE="$REPO_ROOT/gnome/extensions.txt"
# Set GNOME_EXT_FETCH=1 to download/build zips first (session setup does this).
FETCH="${GNOME_EXT_FETCH:-0}"

if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "gnome-extensions not found — install gnome-shell-extensions and run from a GNOME session." >&2
    exit 1
fi

if [[ ! -f "$EXT_FILE" ]]; then
    echo "Extension list not found: $EXT_FILE"
    exit 1
fi

if [[ "$FETCH" == "1" && -f "$REPO_ROOT/scripts/fetch-gnome-extensions.sh" ]]; then
    bash "$REPO_ROOT/scripts/fetch-gnome-extensions.sh"
fi

echo "Enabling GNOME extensions..."

while read -r extension; do
    [[ -z "$extension" || "$extension" =~ ^# ]] && continue
    echo "  $extension"
    gnome-extensions enable "$extension" 2>/dev/null || \
        echo "    ⚠ not installed or incompatible"
done < "$EXT_FILE"

# Drop stale UUIDs that break enabled-extensions
python3 - <<'PY'
import ast
import subprocess

raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True
).strip()
s = raw.split(" ", 1)[-1] if raw.startswith("@as") else raw
lst = [x for x in ast.literal_eval(s) if x != "clipd@devtochukwu"]
gv = "[" + ", ".join(repr(x) for x in lst) + "]"
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", gv])
PY

echo "✓ Extension enable pass complete."
echo "  Wayland: log out → log in to clear OUT OF DATE and load metadata patches."
