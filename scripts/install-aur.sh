#!/usr/bin/env bash
# install-aur.sh — install AUR packages from packages/aur.txt (requires yay or paru)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$REPO_ROOT/packages/aur.txt"

if [[ ! -f "$LIST" ]]; then
    exit 0
fi

if [[ -f "$REPO_ROOT/scripts/bootstrap-aur.sh" ]]; then
    bash "$REPO_ROOT/scripts/bootstrap-aur.sh" || true
fi

mapfile -t pkgs < <(grep -v '^#' "$LIST" | grep -v '^[[:space:]]*$' || true)
if [[ ${#pkgs[@]} -eq 0 ]]; then
    exit 0
fi

AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    echo "No AUR helper (yay/paru) — install manually: yay -S --needed - < packages/aur.txt"
    exit 0
fi

to_install=()
for pkg in "${pkgs[@]}"; do
    if pacman -Qi "$pkg" &>/dev/null 2>&1; then
        echo "✓ $pkg already installed"
    else
        to_install+=("$pkg")
    fi
done

if [[ ${#to_install[@]} -eq 0 ]]; then
    exit 0
fi

echo "Installing AUR packages via $AUR_HELPER: ${to_install[*]}"
"$AUR_HELPER" -S --needed --noconfirm "${to_install[@]}"
