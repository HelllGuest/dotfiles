#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="$REPO_ROOT/gnome/dconf/user.conf"

if [[ ! -f "$IN" ]]; then
    echo "Missing: $IN" >&2
    exit 1
fi

echo "Restoring GNOME settings from $IN..."
dconf load / < "$IN"
echo "Done."
