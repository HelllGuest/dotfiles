#!/bin/bash

# Ensure directories exist
mkdir -p ~/Pictures/wallpapers

# Check repo first, then fallback to Pictures
REPO_WALLS="$HOME/dotfiles/theming/wallpapers"
PICTURE_WALLS="$HOME/Pictures/wallpapers"

if [ -d "$REPO_WALLS" ] && [ "$(ls -A "$REPO_WALLS")" ]; then
    WALL=$(find "$REPO_WALLS" -type f | shuf -n 1)
else
    WALL=$(find "$PICTURE_WALLS" -type f | shuf -n 1)
fi

if [ -z "$WALL" ]; then
    echo "No wallpapers found in repo or ~/Pictures/wallpapers"
    exit 1
fi

echo "Setting wallpaper: $WALL"

# swww img "$WALL"
# matugen image "$WALL"
# wal -i "$WALL"

# Update GNOME wallpaper (example)
gsettings set org.gnome.desktop.background picture-uri "file://$WALL"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL"
