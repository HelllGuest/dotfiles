#!/usr/bin/env bash
# install-headroom.sh — Headroom context optimizer (pipx, user-local)
# https://github.com/headroomlabs-ai/headroom

set -euo pipefail

if ! command -v pipx >/dev/null 2>&1; then
    echo "Installing python-pipx (pacman)..."
    sudo pacman -S --needed --noconfirm python-pipx
fi

export PATH="${HOME}/.local/bin:${PATH}"

if command -v headroom >/dev/null 2>&1; then
    echo "Upgrading headroom-ai[all] via headroom update..."
    headroom update -y --extras all || pipx upgrade "headroom-ai"
else
    echo "Installing headroom-ai[all] via pipx (may take a few minutes)..."
    pipx install "headroom-ai[all]"
fi

echo "✓ headroom installed: $(headroom --version)"
