#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$REPO_ROOT/gnome/dconf-settings.ini"

if [[ ! -f "$IN" ]]; then
    echo "Missing: $IN" >&2
    exit 1
fi

echo "Restoring GNOME settings..."
dconf load /org/gnome/ < "$IN"
echo "Done."
