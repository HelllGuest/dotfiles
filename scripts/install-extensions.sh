#!/bin/bash

# Ensure dconf is available
if ! command -v dconf >/dev/null 2>&1; then
    echo "dconf not found. Install it first."
    exit 1
fi

echo "Installing GNOME extensions..."

# Using a loop to enable extensions listed in gnome/extensions.txt
while read -r extension; do
    if [ -n "$extension" ]; then
        echo "Enabling $extension..."
        gnome-extensions enable "$extension" || echo "Failed to enable $extension. Is it installed?"
    fi
done < gnome/extensions.txt
