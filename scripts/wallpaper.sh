#!/bin/bash

# Ensure directories exist
mkdir -p ~/Pictures/wallpapers

WALL=$(find ~/Pictures/wallpapers -type f | shuf -n 1)

if [ -z "$WALL" ]; then
    echo "No wallpapers found in ~/Pictures/wallpapers"
    exit 1
fi

echo "Setting wallpaper: $WALL"

# swww img "$WALL"
# matugen image "$WALL"
# wal -i "$WALL"

# Update GNOME wallpaper (example)
gsettings set org.gnome.desktop.background picture-uri "file://$WALL"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL"
