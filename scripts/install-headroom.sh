#!/usr/bin/env bash
# install-headroom.sh — Headroom context optimizer (pipx, user-local)
# https://github.com/headroomlabs-ai/headroom

set -euo pipefail

if ! command -v pipx >/dev/null 2>&1; then
    echo "Installing python-pipx (pacman)..."
    sudo pacman -S --needed --noconfirm python-pipx
fi

if command -v headroom >/dev/null 2>&1; then
    echo "✓ headroom already installed ($(headroom --version 2>/dev/null || echo unknown))"
    exit 0
fi

echo "Installing headroom-ai[all] via pipx (may take a few minutes)..."
pipx install "headroom-ai[all]"

echo "✓ headroom installed: $(headroom --version)"
