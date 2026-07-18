#!/bin/bash

# Arch GNOME Rice Installer
# Run from a GNOME session terminal after first login (Stage B in README).
# dconf, extension enable, and gsettings steps need an active user session.

# Ensure we are in the repo root
cd "$(dirname "$0")"

echo "Starting installation..."

# 0. Machine profile (hostname override, else hardware detect)
if [ -f "scripts/apply-profile.sh" ]; then
    bash scripts/apply-profile.sh || echo "Profile application had some failures."
fi

# Legacy touchpad udev/inhibit cleanup (if present from older dotfiles)
if [ -f "scripts/cleanup-input-overrides.sh" ]; then
    bash scripts/cleanup-input-overrides.sh || echo "Input override cleanup skipped."
fi

# 1. Install packages
if [ -f "packages/pacman.txt" ]; then
    echo "Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt || echo "Sudo failed. Skipping package installation."
fi

# 1.1 Install Flatpaks
if [ -f "scripts/install-flatpaks.sh" ]; then
    echo "Installing flatpak packages..."
    bash scripts/install-flatpaks.sh || echo "Flatpak install failed."
fi

# 1.15 Install AUR packages (optional — requires yay/paru)
if [ -f "scripts/install-aur.sh" ]; then
    echo "Installing AUR packages..."
    bash scripts/install-aur.sh || echo "AUR install failed or skipped."
fi

# 1.2 Install Fonts
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
cd stow || exit 1
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$dir" = "zram" ]; then
        echo "Skipping zram stow (use scripts/zram-setup.sh — /etc must not symlink into \$HOME)."
    elif [ "$dir" = "system" ]; then
        if [ "$STOW_CMD" == "stow" ]; then
            sudo stow -R -t / "$dir" || echo "$dir stow failed (sudo required)."
        else
            echo "Skipping $dir (requires GNU Stow + sudo)."
        fi
    elif [ "$dir" = "gdm" ]; then
        echo "Skipping gdm (handled by scripts/gdm-setup.sh)."
    elif [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir"
    else
        $STOW_CMD "$dir" "$HOME"
    fi
done
cd .. || exit 1

# 2.1 Import shell history into atuin
if command -v atuin >/dev/null 2>&1; then
    atuin import auto 2>/dev/null && echo "Atuin history imported." || true
fi

# 2.2 Materialize zram config (early-boot safe; not a $HOME symlink)
if [ -f "scripts/zram-setup.sh" ]; then
    bash scripts/zram-setup.sh || echo "zram setup skipped."
fi

# 3. Restore GNOME session (dconf + extensions + tablet handler)
if [ -f "scripts/gnome-session-setup.sh" ]; then
    bash scripts/gnome-session-setup.sh || echo "GNOME session setup skipped."
fi

if [ -f "scripts/location-setup.sh" ]; then
    bash scripts/location-setup.sh || echo "Location setup skipped."
fi

# 3.0 GNOME Console (kgx app settings only — shortcuts in gnome/dconf/user.conf)
if [ -f "scripts/gnome-console-setup.sh" ]; then
    SKIP_GNOME_MEDIA_KEYS=1 bash scripts/gnome-console-setup.sh || echo "GNOME Console setup skipped."
fi

# 3.2 GDM login screen (Wayland, greeter dconf, udev)
if [ -f "scripts/gdm-setup.sh" ]; then
    bash scripts/gdm-setup.sh || echo "GDM setup skipped."
fi

# 3.3 Git global config (interactive: identity, hooks, signing)
if [ -f "scripts/git-setup.sh" ]; then
    bash scripts/git-setup.sh || echo "Git setup skipped."
fi

# 3.4 Neovim (lazy.nvim, treesitter parsers)
if [ -f "scripts/nvim-setup.sh" ]; then
    bash scripts/nvim-setup.sh || echo "Neovim setup skipped."
fi

# 3.5 Headroom (Claude / Cursor context proxy — optional, pipx user-local)
if [ -f "scripts/headroom-setup.sh" ]; then
    bash scripts/headroom-setup.sh || echo "Headroom setup skipped."
fi

# 3.6 PhotoGIMP (Photoshop-like GIMP layout — optional)
if [ -f "scripts/install-photogimp.sh" ]; then
    bash scripts/install-photogimp.sh || echo "PhotoGIMP setup skipped."
fi

# 3.7 Dash2Dock Animated (EGO — before extension enable)
if [ -f "scripts/install-dash2dock.sh" ]; then
    bash scripts/install-dash2dock.sh || echo "Dash2Dock setup skipped."
fi

# 5. Install GNOME Extensions
if [ -f "scripts/install-extensions.sh" ]; then
    bash scripts/install-extensions.sh || echo "Extension enable skipped."
fi

# 6. Final Health Check
if [ -f "scripts/check.sh" ]; then
    bash scripts/check.sh
fi

if [ -f "scripts/validate-configs.sh" ]; then
    bash scripts/validate-configs.sh || echo "Config validation reported issues."
fi

# 7. Privacy Hardening
if [ -f "scripts/privacy-hardener.sh" ]; then
    bash scripts/privacy-hardener.sh
fi

echo "Installation complete!"
