#!/usr/bin/env bash
# install-aur.sh — install AUR packages from packages/aur.txt (requires yay or paru)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST="$REPO_ROOT/packages/aur.txt"

if [[ ! -f "$LIST" ]]; then
    exit 0
fi

# shellcheck source=../lib/pkg-lists.sh
source "$REPO_ROOT/provision/lib/pkg-lists.sh"

if [[ -f "$REPO_ROOT/provision/scripts/bootstrap-aur.sh" ]]; then
    bash "$REPO_ROOT/provision/scripts/bootstrap-aur.sh" \
        || echo "WARN: bootstrap-aur.sh failed; using an existing helper if present" >&2
fi

mapfile -t pkgs < <(aur_targets)
if [[ ${#pkgs[@]} -eq 0 ]]; then
    exit 0
fi

AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    echo "✗ No AUR helper (yay/paru): ${#pkgs[@]} AUR packages not installed — bash provision/scripts/bootstrap-aur.sh" >&2
    exit 1
fi

mapfile -t to_install < <(printf '%s\n' "${pkgs[@]}" | missing_pkgs)
if [[ ${#to_install[@]} -eq 0 ]]; then
    echo "✓ all ${#pkgs[@]} AUR packages installed"
    exit 0
fi

# --sudoloop: builds can outlast the sudo timestamp; without it the final
# install prompt times out unattended and every built package is dropped.
aur() { "$AUR_HELPER" -S --needed --noconfirm --sudoloop "$@"; }

echo "Installing AUR packages via $AUR_HELPER: ${to_install[*]}"
if ! aur "${to_install[@]}"; then
    # One failing build aborts the batch; retry each so the rest still install.
    echo "Batch failed — retrying one package at a time..."
    mapfile -t retry < <(printf '%s\n' "${to_install[@]}" | missing_pkgs)
    for pkg in "${retry[@]}"; do
        aur "$pkg" || echo "✗ AUR build/install failed: $pkg" >&2
    done
fi

mapfile -t still < <(printf '%s\n' "${pkgs[@]}" | missing_pkgs)
if [[ ${#still[@]} -gt 0 ]]; then
    echo "✗ AUR packages not installed: ${still[*]} — $AUR_HELPER -S ${still[*]}" >&2
    exit 1
fi
echo "✓ all ${#pkgs[@]} AUR packages installed"
