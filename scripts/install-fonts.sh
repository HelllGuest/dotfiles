#!/bin/bash

echo "Installing fonts..."
sudo pacman -S --needed --noconfirm \
    inter-font \
    ttf-jetbrains-mono-nerd \
    noto-fonts \
    noto-fonts-emoji \
    ttf-fira-code \
    ttf-cascadia-code || echo "Sudo failed. Fonts not installed."

fc-cache -fv
echo "Fonts installed and cache updated."
