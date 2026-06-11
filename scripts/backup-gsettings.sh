#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/gnome/dconf/user.conf"

echo "Backing up GNOME settings to $OUT..."
dconf dump / > "$OUT"
echo "Done: $OUT"
