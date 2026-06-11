#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/gnome/dconf-settings.ini"

echo "Backing up GNOME settings..."
dconf dump /org/gnome/ > "$OUT"
echo "Done: $OUT"
