#!/bin/bash

# minimal-stow.sh
# A simple bash alternative to GNU Stow for basic symlinking.
# Usage: ./minimal-stow.sh [package_dir]

PACKAGE=$1
TARGET=${2:-$HOME}

if [ -z "$PACKAGE" ]; then
    echo "Usage: ./minimal-stow.sh [package_dir] [target_dir]"
    exit 1
fi

if [ ! -d "$PACKAGE" ]; then
    echo "Error: Directory $PACKAGE does not exist."
    exit 1
fi

echo "Linking $PACKAGE to $TARGET..."

# Walk through the package directory
find "$PACKAGE" -type f | while read -r src; do
    # Calculate the relative path from the package root
    rel_path=${src#$PACKAGE/}
    dest="$TARGET/$rel_path"
    
    # Ensure destination directory exists
    mkdir -p "$(dirname "$dest")"
    
    # Remove existing file or symlink
    rm -f "$dest"
    
    # Create symlink (using absolute path for source)
    ln -s "$(realpath "$src")" "$dest"
    echo "  $rel_path -> $dest"
done
