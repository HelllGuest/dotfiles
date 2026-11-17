#!/usr/bin/env bash
# install-flatpaks.sh — install apps from packages/flatpak.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$REPO_ROOT/packages/flatpak.txt"

if [[ ! -f "$LIST" ]]; then
    exit 0
fi

if ! command -v flatpak >/dev/null 2>&1; then
    echo "✗ flatpak not installed: apps in packages/flatpak.txt not installed (sudo pacman -S flatpak)" >&2
    exit 1
fi

# shellcheck source=lib/pkg-lists.sh
source "$REPO_ROOT/scripts/lib/pkg-lists.sh"
mapfile -t refs < <(list_entries "$LIST")
if [[ ${#refs[@]} -eq 0 ]]; then
    exit 0
fi

sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Always install system-wide to match arch-install.sh; --or-update makes reruns idempotent.
if ! sudo flatpak install --system --or-update -y flathub "${refs[@]}"; then
    echo "Batch failed — retrying one app at a time..."
    for ref in "${refs[@]}"; do
        sudo flatpak install --system --or-update -y flathub "$ref" \
            || echo "✗ flatpak install failed: $ref" >&2
    done
fi

installed="$(flatpak list --system --app --columns=application)"
missing=()
for ref in "${refs[@]}"; do
    grep -qx "$ref" <<<"$installed" || missing+=("$ref")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "✗ flatpaks not installed: ${missing[*]}" >&2
    exit 1
fi
echo "✓ all ${#refs[@]} flatpaks installed"
