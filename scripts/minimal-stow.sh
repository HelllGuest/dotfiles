#!/usr/bin/env bash

# minimal-stow.sh
# A simple bash alternative to GNU Stow for basic symlinking.
# Refuses to overwrite existing non-symlink files (matches GNU Stow safety).
# Usage: ./minimal-stow.sh <package_dir> [target_dir]
set -euo pipefail

PACKAGE="${1:-}"
TARGET="${2:-$HOME}"

if [[ -z "$PACKAGE" ]]; then
    echo "Usage: ./minimal-stow.sh <package_dir> [target_dir]" >&2
    exit 1
fi

if [[ ! -d "$PACKAGE" ]]; then
    echo "Error: Directory $PACKAGE does not exist." >&2
    exit 1
fi

PACKAGE="${PACKAGE%/}"
echo "Linking $PACKAGE to $TARGET..."

# Walk files and symlinks; NUL-delimited so spaces in paths (e.g. Antigravity IDE) work.
while IFS= read -r -d '' src; do
    rel_path="${src#"$PACKAGE/"}"
    dest="$TARGET/$rel_path"

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        echo "Error: $dest exists and is not a symlink — refusing to overwrite" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest")"
    ln -snf "$(realpath -s "$src")" "$dest"
    echo "  $rel_path -> $dest"
done < <(find "$PACKAGE" \( -type f -o -type l \) -print0)
