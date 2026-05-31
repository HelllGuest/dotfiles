#!/bin/bash

# Arch GNOME Rice Installer

# Ensure we are in the repo root
cd "$(dirname "$0")"

echo "Starting installation..."

# 0. Machine Profile Sourcing
HOST=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown")
if [ -f "profiles/${HOST}.sh" ]; then
    echo "Applying profile for ${HOST}..."
    source "profiles/${HOST}.sh" || echo "Profile application had some failures (likely sudo)."
else
    echo "No specific profile found for ${HOST}. Using default."
fi

# 1. Install packages
if [ -f "packages/pacman.txt" ]; then
    echo "Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt || echo "Sudo failed. Skipping package installation."
fi

# 1.1 Install Fonts
if [ -f "scripts/install-fonts.sh" ]; then
    bash scripts/install-fonts.sh || echo "Font installation failed. Skipping."
fi

# 2. Setup symlinks using Stow or Fallback
STOW_CMD="stow"
if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow not found. Using minimal-stow fallback..."
    STOW_CMD="../scripts/minimal-stow.sh"
    chmod +x scripts/minimal-stow.sh
fi

echo "Applying dotfiles..."
cd stow
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$dir" = "zram" ] || [ "$dir" = "system" ]; then
        if [ "$STOW_CMD" == "stow" ]; then
            sudo stow -R -t / "$dir" || echo "$dir stow failed (sudo required)."
        else
            echo "Skipping $dir (requires GNU Stow + sudo)."
        fi
    elif [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir"
    else
        $STOW_CMD "$dir" "$HOME"
    fi
done
cd ..

# 3. Restore GNOME settings
if [ -f "gnome/dconf-settings.ini" ]; then
    echo "Restoring GNOME settings..."
    dconf load /org/gnome/ < gnome/dconf-settings.ini
fi

# 4. Set initial wallpaper
if [ -f "scripts/wallpaper.sh" ]; then
    bash scripts/wallpaper.sh
fi

# 5. Install GNOME Extensions
if [ -f "scripts/install-extensions.sh" ]; then
    bash scripts/install-extensions.sh
fi

# 6. Final Health Check
if [ -f "scripts/check.sh" ]; then
    bash scripts/check.sh
fi

# 7. Privacy Hardening
if [ -f "scripts/privacy-hardener.sh" ]; then
    bash scripts/privacy-hardener.sh
fi

echo "Installation complete!"
