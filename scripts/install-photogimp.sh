#!/usr/bin/env bash
# install-photogimp.sh — GIMP + PhotoGIMP (Photoshop-like layout)
# Upstream: https://github.com/Diolinux/PhotoGIMP
# Release ships config under GIMP/3.0; GIMP 3.2+ uses ~/.config/GIMP/<major.minor>.

set -euo pipefail

PHOTO_URL="${PHOTO_URL:-https://github.com/Diolinux/PhotoGIMP/releases/download/3.0/PhotoGIMP-linux.zip}"
CURL_BIN="${PHOTO_CURL:-/usr/bin/curl}"

if ! command -v gimp >/dev/null 2>&1; then
    echo "Installing gimp (pacman)..."
    sudo pacman -S --needed --noconfirm gimp
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "Installing unzip (pacman)..."
    sudo pacman -S --needed --noconfirm unzip
fi

# Optional FITS plugin dependency (avoids file-fits .so warning)
if ! pacman -Q cfitsio &>/dev/null; then
    echo "Installing cfitsio (optional GIMP FITS plugin)..."
    sudo pacman -S --needed --noconfirm cfitsio || true
fi

GIMP_MM="$(gimp --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 3.2)"
GIMP_FULL="$(gimp --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "${GIMP_MM}.0")"
CFG_DIR="$HOME/.config/GIMP/${GIMP_MM}"

mkdir -p "$CFG_DIR"
BACKUP="$HOME/GIMP-${GIMP_MM}-backup-$(date +%Y%m%d)"
if [[ -n "$(find "$CFG_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    if [[ ! -d "$BACKUP" ]]; then
        cp -a "$CFG_DIR" "$BACKUP"
        echo "Backup: $BACKUP"
    else
        echo "Backup exists: $BACKUP (skip)"
    fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/PhotoGIMP-linux.zip"

echo "Downloading PhotoGIMP..."
"$CURL_BIN" -fsSL -o "$ZIP" "$PHOTO_URL"
unzip -qo "$ZIP" -d "$TMP/extract"

SRC=""
if [[ -d "$TMP/extract/PhotoGIMP-linux/.config/GIMP/3.0" ]]; then
    SRC="$TMP/extract/PhotoGIMP-linux"
elif [[ -d "$TMP/extract/.config/GIMP/3.0" ]]; then
    SRC="$TMP/extract"
else
    echo "ERROR: unexpected PhotoGIMP zip layout" >&2
    find "$TMP/extract" -maxdepth 4 -type d >&2 || true
    exit 1
fi

apply_photogimp_tree() {
    local dest="$1"
    mkdir -p "$dest"
    # rsync if available (exclude stale pluginrc); else cp + rm
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude='pluginrc' "$SRC/.config/GIMP/3.0/" "$dest/"
    else
        cp -a "$SRC/.config/GIMP/3.0/." "$dest/"
        rm -f "$dest/pluginrc"
    fi
    # PhotoGIMP ships config-version 3.0.0; bump to installed GIMP so prefs load cleanly.
    if [[ -f "$dest/gimprc" ]]; then
        sed -i "s/(config-version \"[^\"]*\")/(config-version \"${GIMP_FULL}\")/" "$dest/gimprc" || true
    fi
    # Never keep upstream pluginrc — protocol-version is tied to the build that generated it.
    rm -f "$dest/pluginrc"
}

echo "Applying PhotoGIMP → $CFG_DIR"
apply_photogimp_tree "$CFG_DIR"

# Flatpak GIMP uses a different config root; patch it too when installed.
FLAT_CFG="$HOME/.var/app/org.gimp.GIMP/config/GIMP/${GIMP_MM}"
if command -v flatpak >/dev/null 2>&1 && flatpak info org.gimp.GIMP &>/dev/null; then
    echo "Applying PhotoGIMP → $FLAT_CFG (Flatpak)"
    apply_photogimp_tree "$FLAT_CFG"
fi

mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons"
if [[ -d "$SRC/.local/share/applications" ]]; then
    cp -a "$SRC/.local/share/applications/." "$HOME/.local/share/applications/"
fi
if [[ -d "$SRC/.local/share/icons" ]]; then
    cp -a "$SRC/.local/share/icons/." "$HOME/.local/share/icons/"
fi

# Upstream .desktop Exec is Flatpak-only and hardcodes gimp-3.0 (broken on Flatpak 3.2).
# Prefer native pacman gimp → ~/.config/GIMP.
DESKTOP="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
if [[ -f "$DESKTOP" ]] && command -v gimp >/dev/null 2>&1; then
    sed -i 's|^Exec=.*|Exec=gimp %U|' "$DESKTOP"
    sed -i '/^X-Flatpak/d;/^DBusActivatable=/d' "$DESKTOP" || true
    chmod 644 "$DESKTOP"
    echo "Desktop: Name=PhotoGIMP Exec=gimp"
fi

# Hide stock pacman "GNU Image Manipulation Program" so menu shows PhotoGIMP once.
HIDE_GIMP="$HOME/.local/share/applications/gimp.desktop"
if [[ -f /usr/share/applications/gimp.desktop ]]; then
    cat > "$HIDE_GIMP" <<'EOF'
[Desktop Entry]
Name=GNU Image Manipulation Program
Exec=gimp %U
Icon=gimp
Type=Application
NoDisplay=true
EOF
    chmod 644 "$HIDE_GIMP"
    echo "Hid stock gimp.desktop (NoDisplay=true)"
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "✓ PhotoGIMP applied ($(gimp --version 2>/dev/null | head -1))"
echo "  Open: gimp   or app menu → PhotoGIMP"
echo "  Note: pacman + Flatpak GIMP both present; menu PhotoGIMP → native gimp"
echo "  Undo: rm -rf \"$CFG_DIR\" && cp -a \"$BACKUP\" \"$CFG_DIR\"   # if backup exists"
