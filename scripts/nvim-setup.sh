#!/usr/bin/env bash
# nvim-setup.sh — stow Neovim config, sync lazy.nvim plugins and Treesitter parsers

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"
MIN_NEOVIM_MINOR=10

echo "→ Neovim setup..."

if ! command -v nvim >/dev/null 2>&1; then
  echo "Installing neovim..."
  sudo pacman -S --needed --noconfirm neovim
fi

NVIM_VER=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
NVIM_MINOR=$(echo "$NVIM_VER" | cut -d. -f2)
if [[ "$NVIM_MINOR" -lt "$MIN_NEOVIM_MINOR" ]]; then
  echo "Neovim $NVIM_VER found — 0.10+ required." >&2
  exit 1
fi
echo "  ✓ Neovim $NVIM_VER"

sudo pacman -S --needed --noconfirm git gcc make ripgrep fd tree-sitter-cli 2>/dev/null || \
  pacman -S --needed --noconfirm git gcc make ripgrep fd tree-sitter-cli 2>/dev/null || true

mkdir -p "$HOME/.config"
cd "$STOW_DIR"
if command -v stow >/dev/null 2>&1; then
  stow -R -t "$HOME" nvim
else
  echo "GNU stow required." >&2
  exit 1
fi

PALETTE="$REPO_ROOT/stow/nvim/.config/nvim/lua/palette.lua"
if [[ ! -f "$PALETTE" && -f "$REPO_ROOT/scripts/theme-switch.sh" ]]; then
  bash "$REPO_ROOT/scripts/theme-switch.sh" zukitwo >/dev/null 2>&1 || true
fi

echo "→ Installing plugins (headless)..."
nvim --headless "+Lazy! sync" +qa 2>&1 | tail -8 || {
  echo "Lazy sync failed — run: nvim" >&2
  exit 1
}

echo "→ Installing Treesitter parsers..."
nvim --headless "+lua require('nvim-treesitter').install({'lua','vim','vimdoc','bash','markdown','markdown_inline','json','python','typescript','tsx','javascript','go','rust','toml','yaml','css','html','dockerfile','gitcommit','gitignore'}):wait(300000)" +qa 2>&1 | tail -5 || true

echo "  Mason finishes LSP/DAP tools on first interactive nvim launch (:Mason)."
echo ""
echo "✓ Neovim ready."
echo "  :Mason   — monitor tool installs"
echo "  <Space>ff — find files   |  <Space>tt — run file tests"
echo "  s / S    — flash jump    |  <Space>gd — diffview"
