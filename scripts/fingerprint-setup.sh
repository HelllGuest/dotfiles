#!/usr/bin/env bash
# fingerprint-setup.sh — Synaptics UWP WBDI (06CB:00BD) on ThinkPad X1 Yoga Gen 5
# Run manually after install: ~/dotfiles/scripts/fingerprint-setup.sh

set -euo pipefail

echo "→ Installing fprintd..."
sudo pacman -S --needed --noconfirm fprintd libfprint

echo "→ Checking device..."
if ! fprintd-list "$USER" 2>/dev/null | grep -q "finger"; then
    echo "Enroll a finger (follow prompts):"
    fprintd-enroll --finger right-index-finger "$USER"
fi

PAM_GDM="/etc/pam.d/gdm-password"
if ! grep -q "pam_fprintd" "$PAM_GDM" 2>/dev/null; then
    sudo sed -i '1s/^/auth        sufficient  pam_fprintd.so\n/' "$PAM_GDM"
    echo "Added pam_fprintd to $PAM_GDM"
else
    echo "pam_fprintd already in $PAM_GDM"
fi

sudo systemctl enable --now fprintd.service
echo "✓ Fingerprint auth ready for GDM (fingerprint OR password)"
