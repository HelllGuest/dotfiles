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
check_link() {
    local path=$1
    if [ -L "$path" ]; then
        echo "✓ Symlink exists: $path"
    elif [ -L "$(dirname "$path")" ] && [ -f "$path" ]; then
        echo "✓ Stowed via $(dirname "$path") -> $(readlink "$(dirname "$path")")"
    else
        echo "✗ Symlink missing: $path"
    fi
}

CHECK_LINKS=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/starship.toml" "$HOME/.config/nvim/init.lua" "$HOME/.config/fastfetch/config.jsonc")
for link in "${CHECK_LINKS[@]}"; do
    check_link "$link"
done

# 3. Check for fonts
if fc-list : family | grep -qi "JetBrainsMono"; then
    echo "✓ JetBrainsMono Nerd Font is installed"
else
    echo "✗ JetBrainsMono Nerd Font is missing"
fi

echo "Health check finished."
