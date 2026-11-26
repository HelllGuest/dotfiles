#!/usr/bin/env bash
# build-st.sh — build and install riced st from builds/st
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/builds/st"

cd "$BUILD_DIR"
# PKGBUILD expects patch basenames beside PKGBUILD; keep canonical copies in patches/
for f in patches/*.diff; do
  ln -sfn "$f" "$(basename "$f")"
done
makepkg -sf --noconfirm
pkg=(st-*.pkg.tar.zst)
echo "Installing ${pkg[0]}..."
sudo pacman -U --noconfirm "${pkg[0]}"
echo "Done. Launch: st   (X11 / XWayland)"
