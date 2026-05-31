#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_FILE="$REPO_ROOT/gnome/extensions.txt"

if ! command -v dconf >/dev/null 2>&1; then
    echo "dconf not found. Install it first."
    exit 1
fi

if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "gnome-extensions not found."
    exit 1
fi

if [[ ! -f "$EXT_FILE" ]]; then
    echo "Extension list not found: $EXT_FILE"
    exit 1
fi

echo "Enabling GNOME extensions..."

while read -r extension; do
    [[ -z "$extension" || "$extension" =~ ^# ]] && continue
    echo "  $extension"
    gnome-extensions enable "$extension" 2>/dev/null || \
        echo "    ⚠ not installed or incompatible"
done < "$EXT_FILE"

echo "✓ Extension enable pass complete."
