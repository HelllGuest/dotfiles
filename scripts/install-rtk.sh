#!/usr/bin/env bash
# install-rtk.sh — install SHA-256-pinned rtk (Rust Token Killer) CLI compressor.
#
# Installs to ~/.local/share/rtk/rtk and symlinks ~/.local/bin/rtk (never under
# ~/.headroom/bin, which Headroom purges on init/wrap).
#
# Env:
#   RTK_VERSION   default v1.2.1
#   RTK_SHA256    expected SHA-256 for rtk-x86_64-unknown-linux-musl.tar.gz
set -euo pipefail

RTK_VERSION="${RTK_VERSION:-v1.2.1}"
RTK_SHA256="${RTK_SHA256:-75f64525711be935657a6b228d929c24bd9d1ab7d640ea374a8b913e5b5bac05}"
RTK_ARCH="$(uname -m)"
RTK_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rtk"
RTK_BIN_LINK="${HOME}/.local/bin/rtk"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

[[ "$RTK_ARCH" == "x86_64" ]] || die "unsupported arch '$RTK_ARCH' (x86_64 musl pin only)"
[[ "${RTK_SHA256,,}" =~ ^[0-9a-f]{64}$ ]] || die "RTK_SHA256 must be 64 hex chars"
command -v curl >/dev/null 2>&1 || die "curl required"
command -v tar >/dev/null 2>&1 || die "tar required"

URL="https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-x86_64-unknown-linux-musl.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

say "fetching rtk ${RTK_VERSION} (x86_64-unknown-linux-musl)"
curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/rtk.tar.gz" "$URL" \
  || die "download failed: $URL"

got="$(sha256sum "$TMP/rtk.tar.gz" | awk '{print $1}')"
if [[ "$got" != "${RTK_SHA256,,}" ]]; then
  die "rtk SHA-256 mismatch (want ${RTK_SHA256,,}, got $got)"
fi

tar -xzf "$TMP/rtk.tar.gz" -C "$TMP"
bin="$(find "$TMP" -maxdepth 3 -type f -name rtk | head -1)"
[[ -n "$bin" ]] || die "rtk binary not found in archive"

mkdir -p "$RTK_INSTALL_DIR" "$(dirname "$RTK_BIN_LINK")"
install -m 0755 "$bin" "$RTK_INSTALL_DIR/rtk"
ln -sfn "$RTK_INSTALL_DIR/rtk" "$RTK_BIN_LINK"

say "rtk ready: $RTK_BIN_LINK ($("$RTK_BIN_LINK" --version 2>/dev/null | head -1 || echo "$RTK_VERSION"))"
