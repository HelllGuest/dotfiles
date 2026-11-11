#!/usr/bin/env bash
# install-foxcage.sh — grepular/foxcage: Firefox in a rootless Podman container
#
# Pins upstream commit FOXCAGE_REF (no release tags upstream). Downloads the
# single-file script + icon, verifies both SHA-256 digests, installs them to
# ~/.local/share/foxcage, links ~/.local/bin/foxcage, and runs `foxcage --install`
# (desktop entry + icon). The local icon next to the script keeps --install from
# fetching the unpinned icon from upstream main. Does not change the default
# browser. The container image builds on first launch, not here. Safe to re-run.
#
# Scope of the pin: only the foxcage script and icon. On first launch (and on
# rebuilds every 7 days / Firefox updates) foxcage downloads Firefox from
# Mozilla itself; that image content is not pinned here.
#
# Update (upstream has no tags):
#   ref=$(curl -fsS 'https://gitlab.com/api/v4/projects/81309831/repository/commits?ref_name=main&per_page=1' \
#         | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')
#   for f in foxcage foxcage.png; do
#     curl -fsSL "https://gitlab.com/grepular/foxcage/-/raw/$ref/$f" | sha256sum
#   done
#   Review the upstream diff, then update FOXCAGE_REF, FOXCAGE_SHA256,
#   FOXCAGE_ICON_SHA256 below and in tests/foxcage.test.sh.
#
# Env:
#   FOXCAGE_REF             override commit (must match both SHA-256 pins)
#   FOXCAGE_SHA256          override expected digest of the foxcage script
#   FOXCAGE_ICON_SHA256     override expected digest of foxcage.png
#
# Usage:
#   bash scripts/install-foxcage.sh
#   foxcage                     # first run builds the image
#   xdg-settings set default-web-browser foxcage.desktop   # optional
set -euo pipefail

FOXCAGE_REF="${FOXCAGE_REF:-349056e5afd0172330d93ea55413dcdd8c763fd0}"
# sha256 of foxcage and foxcage.png at FOXCAGE_REF
FOXCAGE_SHA256="${FOXCAGE_SHA256:-f9a87fc60e3c3b3b740ec0dcf64ac1c72287d65cc63269822dd805fb98d0a8fe}"
FOXCAGE_ICON_SHA256="${FOXCAGE_ICON_SHA256:-0df41fe24a1ebc1de3bc0a0714b24bfb19f75a49b05ebb719cd96ff9f4f3bf5d}"
RAW_URL="https://gitlab.com/grepular/foxcage/-/raw/${FOXCAGE_REF}"
DEST="${HOME}/.local/share/foxcage"
BIN="${HOME}/.local/bin"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

[[ $EUID -ne 0 ]] || die "run as your desktop user, not root (foxcage refuses root)"
[[ $FOXCAGE_REF =~ ^[0-9a-f]{40}$ ]] || die "FOXCAGE_REF must be a full 40-char commit SHA"
for c in curl sha256sum python3; do
  command -v "$c" >/dev/null 2>&1 || die "$c required"
done
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || die "foxcage needs Python 3.11+"

# Runtime deps: warn only — foxcage itself reports what is missing at launch.
missing=()
command -v podman >/dev/null 2>&1 || missing+=(podman)
command -v pasta >/dev/null 2>&1 || missing+=(passt)
command -v xdg-dbus-proxy >/dev/null 2>&1 || missing+=(xdg-dbus-proxy)
if ((${#missing[@]})); then
  echo "warning: missing runtime deps: ${missing[*]} — sudo pacman -S --needed ${missing[*]}" >&2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { # name expected-sha256
  local got
  curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP/$1" "$RAW_URL/$1"
  got="$(sha256sum "$TMP/$1" | awk '{print $1}')"
  [[ $got == "$2" ]] \
    || die "foxcage $1 SHA-256 mismatch (got $got want $2). Refusing to install. If you bumped FOXCAGE_REF, refresh the SHA-256 pins."
}

say "fetch foxcage @ ${FOXCAGE_REF:0:12}"
fetch foxcage "$FOXCAGE_SHA256"
fetch foxcage.png "$FOXCAGE_ICON_SHA256"
say "SHA-256 ok"

mkdir -p "$DEST" "$BIN"
install -m 755 "$TMP/foxcage" "$DEST/foxcage"
install -m 644 "$TMP/foxcage.png" "$DEST/foxcage.png"
ln -sfn "$DEST/foxcage" "$BIN/foxcage"
say "installed $DEST/foxcage -> $BIN/foxcage"

"$DEST/foxcage" --install
say "done — run: foxcage (first launch builds the container image)"
