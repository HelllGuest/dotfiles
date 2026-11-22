#!/usr/bin/env bash
# fetch-gnome-extensions.sh — download/build extensions that are not pacman/AUR/stow-owned
# Targets the live extensions dir (folded stow symlink under proton-vpn package).
# Safe to re-run. Does not enable (see install-extensions.sh).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
CURL_BIN="${GNOME_EXT_CURL:-/usr/bin/curl}"
EGO_BASE="https://extensions.gnome.org/download-extension"

info() { echo "→ $*"; }

# Ensure metadata allows Shell 51 (unofficial when upstream zip lags).
patch_shell_51() {
    local meta="$EXT_ROOT/$1/metadata.json"
    [[ -f $meta ]] || return 0
    python3 - "$meta" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    meta = json.load(f)
sv = list(meta.get("shell-version") or [])
if "51" not in sv:
    sv.append("51")
    meta["shell-version"] = sv
    with open(path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print("  patched metadata shell-version ← 51")
PY
}

install_ego_zip() {
    local uuid="$1" version_tag="$2" label="$3"
    local patch51="${4:-0}"
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
    if [[ -d $dir/schemas ]]; then
        glib-compile-schemas "$dir/schemas"
    fi
    rm -rf "$tmp"
    [[ $patch51 == 1 ]] && patch_shell_51 "$uuid"
}

mkdir -p "$EXT_ROOT"

# Shell-51 EGO builds (version_tag from extensions.gnome.org shell_version_map).
install_ego_zip "caffeine@patapon.info" "${CAFFEINE_TAG:-76057}" "Caffeine"
install_ego_zip "blur-my-shell@aunetx" "${BLUR_MY_SHELL_TAG:-78246}" "Blur My Shell"
install_ego_zip "status-tray@keithvassallo.com" "${STATUS_TRAY_TAG:-78680}" "Status Tray"
install_ego_zip "tiling-assistant@leleat-on-github" "${TILING_ASSISTANT_TAG:-76100}" "Tiling Assistant"
install_ego_zip "hotedge@jonathan.jdoda.ca" "${HOTEDGE_TAG:-74490}" "Hot Edge"
install_ego_zip "kiwimenu@kemma" "${KIWIMENU_TAG:-77866}" "Kiwi Menu"
install_ego_zip "copyous@boerdereinar.dev" "${COPYOUS_TAG:-76772}" "Copyous"
install_ego_zip "wiggly@mojarch" "${WIGGLY_TAG:-76032}" "Wiggly"
# EGO lags Shell 51 on these two; zip + metadata patch (same idea as Dash2Dock).
install_ego_zip "custom-osd@neuromorph" "${CUSTOM_OSD_TAG:-55755}" "Custom OSD" 1
install_ego_zip "restartto@tiagoporsch.github.io" "${RESTARTTO_TAG:-73214}" "Restart To" 1

# Dash2Dock: EGO ≤50 metadata; install script patches 51 (unofficial)
bash "$REPO_ROOT/scripts/install-dash2dock.sh"

echo "✓ Fetched GNOME extensions into $EXT_ROOT"
echo "  Enable: bash $REPO_ROOT/scripts/install-extensions.sh"
echo "  Wayland: log out → log in so Shell reloads extensions (Meta.restart is disabled)."
