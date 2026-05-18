#!/bin/bash

echo "Running health check..."

# 1. Check for required binaries
REQUIRED_BINARIES=("stow" "zsh" "starship" "nvim" "ghostty" "fastfetch" "dconf" "jq" "sass")
for bin in "${REQUIRED_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        echo "✗ $bin is missing"
    fi
done

# 2. Check for symlinks
CHECK_LINKS=("$HOME/.zshrc" "$HOME/.config/starship.toml" "$HOME/.config/nvim/init.lua")
for link in "${CHECK_LINKS[@]}"; do
    if [ -L "$link" ]; then
        echo "✓ Symlink exists: $link"
    else
        echo "✗ Symlink missing: $link"
    fi
done

# 3. Check for fonts
if fc-list : family | grep -qi "JetBrainsMono"; then
    echo "✓ JetBrainsMono Nerd Font is installed"
else
    echo "✗ JetBrainsMono Nerd Font is missing"
fi

echo "Health check finished."
