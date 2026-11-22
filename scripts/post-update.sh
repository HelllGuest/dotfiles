#!/bin/bash
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
fail() { echo "warning: $*" >&2; FAILED=1; }

echo "Running post-update maintenance..."

# Install any new flatpaks from packages/flatpak.txt, then update
if [ -f "$REPO_ROOT/scripts/install-flatpaks.sh" ]; then
    bash "$REPO_ROOT/scripts/install-flatpaks.sh" || fail "install-flatpaks.sh failed"
fi
if command -v flatpak >/dev/null 2>&1; then
    echo "Updating Flatpaks..."
    flatpak update -y || fail "flatpak update failed"
fi

# Update Neovim plugins
if command -v nvim >/dev/null 2>&1; then
    echo "Updating Neovim plugins..."
    nvim --headless "+Lazy! sync" +qa 2>&1 | tail -3 \
        || fail "Lazy sync failed"
    nvim --headless "+lua require('nvim-treesitter').install({'lua','vim','vimdoc'}):wait(120000)" +qa 2>&1 | tail -2 \
        || fail "treesitter install failed"
fi

# Update font cache
echo "Updating font cache..."
fc-cache -fv || fail "fc-cache failed"

# Update tldr if present
if command -v tldr >/dev/null 2>&1; then
    echo "Updating tldr..."
    tldr --update || fail "tldr --update failed"
fi

# Pacman cache + unused Flatpak runtimes (weekly timer stays enabled)
if [ "${SKIP_OPS_HYGIENE:-0}" != 1 ] && [ -f "$REPO_ROOT/scripts/ops-hygiene.sh" ]; then
    bash "$REPO_ROOT/scripts/ops-hygiene.sh" || fail "ops-hygiene.sh failed"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "Maintenance finished with failures (see warnings above)."
    exit 1
fi
echo "Maintenance complete!"
