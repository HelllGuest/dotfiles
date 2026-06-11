#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running post-update maintenance..."

# Install any new flatpaks from packages/flatpak.txt, then update
if [ -f "$REPO_ROOT/scripts/install-flatpaks.sh" ]; then
    bash "$REPO_ROOT/scripts/install-flatpaks.sh" || true
fi
if command -v flatpak >/dev/null 2>&1; then
    echo "Updating Flatpaks..."
    flatpak update -y
fi

# Update Neovim plugins
if command -v nvim >/dev/null 2>&1; then
    echo "Updating Neovim plugins..."
    nvim --headless "+Lazy! sync" +qa 2>&1 | tail -3 || true
    nvim --headless "+lua require('nvim-treesitter').install({'lua','vim','vimdoc'}):wait(120000)" +qa 2>&1 | tail -2 || true
fi

# Update font cache
echo "Updating font cache..."
fc-cache -fv

# Update tldr if present
if command -v tldr >/dev/null 2>&1; then
    echo "Updating tldr..."
    tldr --update
fi

echo "Maintenance complete!"
