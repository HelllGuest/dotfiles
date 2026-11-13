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

patch_shell_version() {
    local meta="$1" ver="$2"
    [[ -f "$meta" ]] || return 0
    python3 - "$meta" "$ver" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    meta = json.load(f)
sv = list(meta.get("shell-version") or [])
if ver not in sv:
    sv.append(ver)
    meta["shell-version"] = sv
    with open(path, "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    print(f"patched {path} shell-version ← {ver}")
PY
}

install_gnome_clipboard() {
    local uuid="gnome-clipboard@b00f.github.io"
    local tmp src zip dir got
    # Pin commit + zip digest (bump together). Floating main is refused.
    local ref="${GNOME_CLIPBOARD_REF:-6eca59f2efd9441df3bfbdfc27df0ce35d16b881}"
    local sha="${GNOME_CLIPBOARD_SHA256:-d56f73e11e070035971b0d51ca5139296d4ac918e720b3724d8782668f9f6988}"
    tmp="$(mktemp -d)"
    info "GitHub build ${uuid} @ ${ref:0:12}"
    "$CURL_BIN" -fsSL -o "$tmp/src.zip" \
        "https://github.com/b00f/gnome-clipboard/archive/${ref}.zip"
    command -v sha256sum >/dev/null 2>&1 || die "sha256sum required"
    got="$(sha256sum "$tmp/src.zip" | awk '{print $1}')"
    [[ "$got" == "$sha" ]] \
        || die "gnome-clipboard SHA-256 mismatch (got $got want $sha). If you bumped GNOME_CLIPBOARD_REF, refresh GNOME_CLIPBOARD_SHA256."
    unzip -qo "$tmp/src.zip" -d "$tmp"
    src="$(find "$tmp" -maxdepth 1 -type d -name 'gnome-clipboard-*' | head -1)"
    [[ -n "$src" ]] || die "gnome-clipboard source tree missing"
    make -C "$src" build
    zip="$src/${uuid}.shell-extension.zip"
    [[ -f "$zip" ]] || die "clipboard zip missing after build"

    dir="$EXT_ROOT/$uuid"
    rm -rf "$dir"
    mkdir -p "$dir"
    unzip -qo "$zip" -d "$dir"
    patch_shell_version "$dir/metadata.json" "51"
    if [[ -d "$dir/schemas" ]]; then
        glib-compile-schemas "$dir/schemas"
    fi
    find "$dir" -type d -exec chmod 755 {} +
    find "$dir" -type f -exec chmod 644 {} +
    [[ -f "$dir/extension.js" ]] || die "clipboard extension.js missing after install"
    rm -rf "$tmp"
}

mkdir -p "$EXT_ROOT"

# Official Shell-51 EGO builds
install_ego_zip "blur-my-shell@aunetx" "${BLUR_MY_SHELL_TAG:-75939}" "Blur my Shell"
install_ego_zip "caffeine@patapon.info" "${CAFFEINE_TAG:-76057}" "Caffeine"

# Clipboard: EGO lags; build from GitHub main
install_gnome_clipboard

# Dash2Dock: EGO ≤50 metadata; install script patches 51 (unofficial)
bash "$REPO_ROOT/scripts/install-dash2dock.sh"

echo "✓ Fetched GNOME extensions into $EXT_ROOT"
echo "  Enable: bash $REPO_ROOT/scripts/install-extensions.sh"
echo "  Wayland: log out → log in so Shell reloads extensions (Meta.restart is disabled)."
