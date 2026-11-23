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

PACKAGE="$(realpath "$PACKAGE")"
TARGET="$(realpath -s "$TARGET")"
[[ "$PACKAGE" != "/" ]] || { echo "Error: refusing to stow /" >&2; exit 1; }
echo "Linking $PACKAGE to $TARGET..."

# Collect entries first so a conflict fails before any symlink is created.
mapfile -d '' -t entries < <(find "$PACKAGE" \( -type f -o -type l \) -print0)

for src in "${entries[@]}"; do
    rel_path="${src#"$PACKAGE/"}"
    dest="$TARGET/$rel_path"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        echo "Error: $dest exists and is not a symlink — refusing to overwrite" >&2
        exit 1
    fi
    # Refuse to traverse an existing symlinked or non-directory parent under TARGET.
    parent="$(dirname "$dest")"
    while [[ "$parent" != "$TARGET" && "$parent" != "/" && "$parent" != "." ]]; do
        if [[ -L "$parent" ]]; then
            echo "Error: parent dir $parent is a symlink — refusing to link into it" >&2
            exit 1
        fi
        if [[ -e "$parent" && ! -d "$parent" ]]; then
            echo "Error: parent path $parent exists and is not a directory — refusing to overwrite" >&2
            exit 1
        fi
        parent="$(dirname "$parent")"
    done
done

for src in "${entries[@]}"; do
    rel_path="${src#"$PACKAGE/"}"
    dest="$TARGET/$rel_path"
    mkdir -p "$(dirname "$dest")"
    ln -snf "$src" "$dest"
    echo "  $rel_path -> $dest"
done
