#!/bin/bash

# install-fonts.sh
# Top Nerd Fonts for terminals, Starship (Crampack), and editors.

set -euo pipefail

echo "Installing fonts..."

NERD_FONTS=(
    # Terminal / prompt staples
    ttf-jetbrains-mono-nerd
    ttf-meslo-nerd
    ttf-firacode-nerd
    ttf-cascadia-mono-nerd
    ttf-cascadia-code-nerd
    ttf-hack-nerd
    # Popular coding fonts
    ttf-iosevka-nerd
    ttf-iosevkaterm-nerd
    ttf-victor-mono-nerd
    ttf-ibmplex-mono-nerd
    ttf-sourcecodepro-nerd
    ttf-dejavu-nerd
    otf-geist-mono-nerd
    otf-commit-mono-nerd
    # Symbol fallback for mixed font configs
    ttf-nerd-fonts-symbols-common
)

UI_FONTS=(
    inter-font
    noto-fonts
    noto-fonts-emoji
)

sudo pacman -S --needed --noconfirm \
    "${NERD_FONTS[@]}" \
    "${UI_FONTS[@]}" \
    || echo "Sudo failed. Fonts not installed."

fc-cache -fv
echo "Fonts installed and cache updated."

echo ""
echo "Installed Nerd Fonts:"
fc-list : family | grep -i 'Nerd Font' | sort -u
