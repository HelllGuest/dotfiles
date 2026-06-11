#!/bin/bash
# NVIDIA / hybrid-GPU settings (secondary profile on Optimus laptops)
echo "Applying NVIDIA profile..."

if ! command -v lspci >/dev/null 2>&1 || ! lspci -nn 2>/dev/null | grep -qiE 'vga|3d|display.*\[10de:'; then
    echo "No NVIDIA GPU detected — skipping."
    exit 0
fi

# Prefer distro packages when listed; do not fail install if drivers are already present
if [ -f "packages/pacman.txt" ] && grep -q '^nvidia' packages/pacman.txt 2>/dev/null; then
    echo "NVIDIA drivers listed in packages/pacman.txt — installed in the next step."
else
    echo "Tip: add nvidia-open-dkms (or nvidia-dkms) + nvidia-utils to packages/pacman.txt for hybrid graphics."
fi
