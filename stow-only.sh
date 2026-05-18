#!/bin/bash

# stow-only.sh
# Applies symlinks for dotfiles that don't require root.

set -e

echo "Applying dotfiles..."

# Ensure ~/.config exists
mkdir -p "$HOME/.config"

STOW_CMD="stow"
if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow not found. Using minimal-stow fallback..."
    STOW_CMD="./scripts/minimal-stow.sh"
    chmod +x scripts/minimal-stow.sh
fi

cd stow
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$STOW_CMD" == "stow" ]; then
        stow -R "$dir"
    else
        "../$STOW_CMD" "$dir"
    fi
done
cd ..

echo "Symlinks applied successfully!"
