#!/usr/bin/env bash
# install-flatpaks.sh — install apps from packages/flatpak.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$REPO_ROOT/packages/flatpak.txt"

if [[ ! -f "$LIST" ]]; then
    exit 0
fi

if ! command -v flatpak >/dev/null 2>&1; then
    echo "flatpak not installed — skip flatpak apps"
    exit 0
fi

mapfile -t refs < <(grep -v '^#' "$LIST" | grep -v '^[[:space:]]*$' || true)
if [[ ${#refs[@]} -eq 0 ]]; then
    exit 0
fi

sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

# Always install system-wide to match arch-install.sh; --or-update makes reruns idempotent.
sudo flatpak install --system --or-update -y flathub "${refs[@]}"
