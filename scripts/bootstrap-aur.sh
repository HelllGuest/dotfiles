#!/usr/bin/env bash
# bootstrap-aur.sh — install paru when no AUR helper is present

set -euo pipefail

if command -v paru >/dev/null 2>&1 || command -v yay >/dev/null 2>&1; then
    exit 0
fi

echo "No AUR helper (yay/paru) — bootstrapping paru..."

sudo pacman -S --needed --noconfirm base-devel git

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru"
# shellcheck disable=SC2164
cd "$tmp/paru"
makepkg -si --noconfirm

command -v paru >/dev/null 2>&1 || { echo "paru bootstrap failed" >&2; exit 1; }
echo "✓ paru installed"
