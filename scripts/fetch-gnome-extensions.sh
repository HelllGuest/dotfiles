#!/usr/bin/env bash
# fetch-gnome-extensions.sh — download/build extensions that are not pacman/AUR/stow-owned
# Targets the live extensions dir (folded stow symlink under proton-vpn package).
# Safe to re-run. Does not enable (see install-extensions.sh).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
CURL_BIN="${GNOME_EXT_CURL:-/usr/bin/curl}"
EGO_BASE="https://extensions.gnome.org/download-extension"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "→ $*"; }

install_ego_zip() {
    local uuid="$1" version_tag="$2" label="$3"
    local tmp zip dir
    tmp="$(mktemp -d)"
    zip="$tmp/${uuid}.shell-extension.zip"
    dir="$EXT_ROOT/$uuid"

    info "EGO ${label} (${uuid}, tag ${version_tag})"
    "$CURL_BIN" -fsSL -o "$zip" \
        "${EGO_BASE}/${uuid}.shell-extension.zip?version_tag=${version_tag}"

    rm -rf "$dir"
    mkdir -p "$dir"
    unzip -qo "$zip" -d "$dir"
    find "$dir" -type d -exec chmod 755 {} +
    find "$dir" -type f -exec chmod 644 {} +
    if [[ -d "$dir/schemas" ]]; then
        glib-compile-schemas "$dir/schemas"
    fi
    rm -rf "$tmp"
}

mkdir -p "$EXT_ROOT"

# Official Shell-51 EGO build. Blur My Shell is not fetched here: Aura Glass
# (scripts/theme-setup.sh) builds its own patched copy into the same directory.
install_ego_zip "caffeine@patapon.info" "${CAFFEINE_TAG:-76057}" "Caffeine"

# Dash2Dock: EGO ≤50 metadata; install script patches 51 (unofficial)
bash "$REPO_ROOT/scripts/install-dash2dock.sh"

echo "✓ Fetched GNOME extensions into $EXT_ROOT"
echo "  Enable: bash $REPO_ROOT/scripts/install-extensions.sh"
echo "  Wayland: log out → log in so Shell reloads extensions (Meta.restart is disabled)."
