#!/usr/bin/env bash
# fetch-gnome-extensions.sh — download/verify EGO extensions that are not pacman/AUR/stow-owned
# Targets the live extensions dir (folded stow symlink under proton-vpn package).
# Safe to re-run. Does not enable (see install-extensions.sh).
#
# Usage:
#   bash scripts/fetch-gnome-extensions.sh
#   bash scripts/fetch-gnome-extensions.sh --only <uuid>

set -euo pipefail

EXT_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"
CURL_BIN="${GNOME_EXT_CURL:-/usr/bin/curl}"
EGO_BASE="https://extensions.gnome.org/download-extension"
ONLY_UUID=""
if [[ $# -gt 0 ]]; then
    case "$1" in
        --only)
            [[ $# -eq 2 && -n "${2:-}" ]] || { echo "Usage: $0 [--only <uuid>]" >&2; exit 1; }
            ONLY_UUID="$2"
            ;;
        *)
            echo "Usage: $0 [--only <uuid>]" >&2
            exit 1
            ;;
    esac
fi
MATCHED=0
EGO_TMPS=()
trap '(( ${#EGO_TMPS[@]} )) && rm -rf -- "${EGO_TMPS[@]}"' EXIT

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
    local patch51="${4:-0}" expected_sha="${5:-}" url_override="${6:-}"
    [[ -z "$ONLY_UUID" || "$ONLY_UUID" == "$uuid" ]] || return 0
    MATCHED=1
    local tmp zip dir got_sha url
    tmp="$(mktemp -d)"
    EGO_TMPS+=("$tmp")
    zip="$tmp/${uuid}.shell-extension.zip"
    dir="$EXT_ROOT/$uuid"
    url="${url_override:-${EGO_BASE}/${uuid}.shell-extension.zip?version_tag=${version_tag}}"

    info "EGO ${label} (${uuid}, tag ${version_tag})"
    "$CURL_BIN" -fsSL -o "$zip" "$url"

    [[ ${expected_sha,,} =~ ^[0-9a-f]{64}$ ]] || {
        echo "✗ ${uuid}: expected 64-hex SHA-256 pin" >&2
        return 1
    }
    got_sha="$(sha256sum "$zip" | awk '{print $1}')"
    if [[ "$got_sha" != "${expected_sha,,}" ]]; then
        echo "✗ ${uuid}: SHA-256 mismatch (got $got_sha want ${expected_sha,,}) — refusing to unpack" >&2
        return 1
    fi

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
    return 0
}

# Shell-51 EGO builds (version_tag + SHA-256 pinned together).
install_ego_zip "caffeine@patapon.info" "${CAFFEINE_TAG:-76057}" "Caffeine" 0 \
    "${CAFFEINE_SHA256:-3ec59c6d1a62c26ba5c45128b084b62ef4e112fa66008768b5094df940e6a164}"
install_ego_zip "blur-my-shell@aunetx" "${BLUR_MY_SHELL_TAG:-78246}" "Blur My Shell" 0 \
    "${BLUR_MY_SHELL_SHA256:-065d53b27dff3bbdd867deeab0316c030da7702c8c313c2a734d0eb05cf4f4a7}"
install_ego_zip "status-tray@keithvassallo.com" "${STATUS_TRAY_TAG:-78680}" "Status Tray" 0 \
    "${STATUS_TRAY_SHA256:-949863dde58bf71b4a2b416333278c62253758b9027c2f51c59b04e57177d7de}"
install_ego_zip "tiling-assistant@leleat-on-github" "${TILING_ASSISTANT_TAG:-76100}" "Tiling Assistant" 0 \
    "${TILING_ASSISTANT_SHA256:-bd4ec3320cfa53aafa7a63d6f0fbc7642ee4afb4d29abc416fed9e43a9378c30}"
install_ego_zip "hotedge@jonathan.jdoda.ca" "${HOTEDGE_TAG:-74490}" "Hot Edge" 0 \
    "${HOTEDGE_SHA256:-4b816de2c335b2518d368b557f604099d82698112acbb2b9ea838f7473c67352}"
install_ego_zip "kiwimenu@kemma" "${KIWIMENU_TAG:-77866}" "Kiwi Menu" 0 \
    "${KIWIMENU_SHA256:-a458d5229b2ea3dcaa8881c28c7b522a86904f80a6ae933398ef485e865f51e9}"
install_ego_zip "copyous@boerdereinar.dev" "${COPYOUS_TAG:-76772}" "Copyous" 0 \
    "${COPYOUS_SHA256:-fe9eb3b039040b777228e578ebc6b66042f8781e0dae78abf69d9927f1695537}"
install_ego_zip "wiggly@mojarch" "${WIGGLY_TAG:-76032}" "Wiggly" 0 \
    "${WIGGLY_SHA256:-51d994ed3bd7b37a93d60b20fef40ae6356c8206dbad0beafa897e42dce09028}"
# EGO lags Shell 51 on these three; zip + metadata patch.
install_ego_zip "custom-osd@neuromorph" "${CUSTOM_OSD_TAG:-55755}" "Custom OSD" 1 \
    "${CUSTOM_OSD_SHA256:-a5b497ba2ac846b8a78e1c3df9b2764d95886a4530630edb619b7745398a157a}"
install_ego_zip "restartto@tiagoporsch.github.io" "${RESTARTTO_TAG:-73214}" "Restart To" 1 \
    "${RESTARTTO_SHA256:-16edfd59e432f8bf1aed4e02e2d87a49512367537019d2c2acb1e8517fd410af}"
install_ego_zip "dash2dock-lite@icedman.github.com" "${DASH2DOCK_VERSION_TAG:-71180}" "Dash2Dock Animated" 1 \
    "${DASH2DOCK_SHA256:-14db6849ba6edcb63f25032007e182d2b7d842568e9c1386587d7a08c6c53abe}" \
    "${DASH2DOCK_URL:-}"

if [[ -n "$ONLY_UUID" && $MATCHED -eq 0 ]]; then
    echo "✗ unknown extension UUID: $ONLY_UUID" >&2
    exit 1
fi

if [[ -z "$ONLY_UUID" ]]; then
    echo "✓ Fetched GNOME extensions into $EXT_ROOT"
    echo "  Enable: bash $(cd "$(dirname "$0")" && pwd)/install-extensions.sh"
    echo "  Wayland: log out → log in so Shell reloads extensions (Meta.restart is disabled)."
fi
