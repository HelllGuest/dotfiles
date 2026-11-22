#!/bin/bash
# Materialize zram-generator.conf into /etc (symlinks into $HOME break at early boot).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_ROOT}/stow/zram/etc/systemd/zram-generator.conf"
DEST="${ZRAM_DEST:-/etc/systemd/zram-generator.conf}"

if [ ! -f "$SRC" ]; then
    echo "Missing zram source: $SRC" >&2
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cp "$SRC" "$tmp"

if [ -L "$DEST" ]; then
    echo "Replacing zram symlink with real file (home not mounted at generator run)..."
    sudo rm -f "$DEST"
    sudo cp "$tmp" "$DEST"
elif [ ! -e "$DEST" ]; then
    sudo cp "$tmp" "$DEST"
elif ! cmp -s "$tmp" "$DEST"; then
    echo "Backing up existing $DEST..."
    sudo cp -a "$DEST" "${DEST}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$tmp" "$DEST"
else
    echo "$DEST already matches source."
fi
rm -f "$tmp"

sudo chmod 644 "$DEST"
echo "Installed $DEST"

if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl daemon-reload || true
fi
