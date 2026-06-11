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
elif [ -f "gnome/dconf-settings.ini" ]; then
    echo "Restoring GNOME settings (legacy ini)..."
    dconf load /org/gnome/ < gnome/dconf-settings.ini
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

# 5. Install GNOME Extensions
if [ -f "scripts/install-extensions.sh" ]; then
    bash scripts/install-extensions.sh
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
