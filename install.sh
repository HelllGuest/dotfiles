#!/bin/bash

# Arch GNOME Rice Installer
# Run from a GNOME session terminal after first login (Stage B in README).
# dconf, extension enable, and gsettings steps need an active user session.

# Ensure we are in the repo root
cd "$(dirname "$0")"

echo "Starting installation..."

# Legacy touchpad udev/inhibit cleanup (if present from older dotfiles)
if [ -f "scripts/cleanup-input-overrides.sh" ]; then
    bash scripts/cleanup-input-overrides.sh || echo "Input override cleanup skipped."
fi

# 1. Install packages (before machine profile — NVIDIA/Optimus needs nvidia-* present)
if [ -f "packages/pacman.txt" ]; then
    echo "Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt || echo "Sudo failed. Skipping package installation."
fi

# 1.05 Machine profile (hostname override, else hardware detect)
# Runs after pacman so thinkpad-p15 can enable nvidia-*.service and rebuild UKIs.
if [ -f "scripts/apply-profile.sh" ]; then
    bash scripts/apply-profile.sh || echo "Profile application had some failures."
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
# shellcheck source=scripts/lib/skel.sh
source scripts/lib/skel.sh
remove_unmodified_skel "$PWD/stow"
cd stow || exit 1
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$dir" = "zram" ]; then
        echo "Skipping zram stow (use scripts/zram-setup.sh — /etc must not symlink into \$HOME)."
    elif [ "$dir" = "system" ]; then
        echo "Installing $dir as root-owned files (scripts/system-setup.sh — /etc must not symlink into \$HOME)."
        bash ../scripts/system-setup.sh || echo "System setup failed (sudo required)."
    elif [ "$dir" = "gdm" ]; then
        echo "Skipping gdm (handled by scripts/gdm-setup.sh)."
    elif [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir"
    else
        $STOW_CMD "$dir" "$HOME"
    fi
done
cd .. || exit 1

# 2.1 Bootstrap Node.js LTS via fnm (avoids bleeding-edge system node breaking native addons)
if command -v fnm >/dev/null 2>&1; then
    echo "Setting up Node.js LTS (22) via fnm..."
    eval "$(fnm env --shell bash)"
    fnm install 22 || echo "fnm install 22 failed — skipping."
    fnm default 22 || true
fi

# 2.2 Import shell history into atuin
if command -v atuin >/dev/null 2>&1; then
    atuin import auto 2>/dev/null && echo "Atuin history imported." || true
fi

# 2.3 Materialize zram config (early-boot safe; not a $HOME symlink)
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
if [ -f "scripts/ptyxis-setup.sh" ]; then
    bash scripts/ptyxis-setup.sh || echo "Ptyxis setup skipped."
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

# 3.5a Kit skills first (fallback if post-AI sync fails later)
if [ -f "scripts/sync-agent-skills.sh" ]; then
    bash scripts/sync-agent-skills.sh || echo "Agent skills pre-sync skipped."
fi

# 3.5b OpenCode + Kimi CLIs + MCP configs (before caveman so opencode is detected)
if [ -f "scripts/install-coding-agents.sh" ]; then
    if command -v npm >/dev/null 2>&1; then
        SKIP_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh || \
            echo "Coding agents failed — re-run: bash scripts/install-coding-agents.sh"
    else
        echo "Skipping OpenCode/Kimi (npm not on PATH)."
    fi
fi

# 3.5c Caveman (terse voice + ultracave/megacave; pinned installer + SHA-256)
if [ -f "scripts/install-caveman.sh" ]; then
    if command -v npm >/dev/null 2>&1; then
        SKIP_SKILL_SYNC=1 bash scripts/install-caveman.sh || \
            echo "Caveman install failed — re-run: bash scripts/install-caveman.sh"
    else
        echo "Skipping caveman (npm not on PATH)."
    fi
fi

# 3.5d Android UI skills (Compose anti-slop + Material 3; pinned refs)
if [ -f "scripts/install-android-ui-skills.sh" ]; then
    if command -v npx >/dev/null 2>&1; then
        SKIP_SKILL_SYNC=1 bash scripts/install-android-ui-skills.sh || \
            echo "Android UI skills failed — re-run: bash scripts/install-android-ui-skills.sh"
    else
        echo "Skipping Android UI skills (npx not on PATH)."
    fi
fi

# 3.5e ghidra-cli (optional Rust bridge; needs pacman ghidra + rust/cargo)
if [ -f "scripts/install-ghidra-cli.sh" ]; then
    if pacman -Q ghidra >/dev/null 2>&1; then
        bash scripts/install-ghidra-cli.sh || \
            echo "ghidra-cli install failed — re-run: bash scripts/install-ghidra-cli.sh"
    else
        echo "Skipping ghidra-cli (pacman package ghidra not installed)."
    fi
fi

# 3.5f REA (reverse-engineer-anything MCP + jadx JAR; needs npm from fnm)
if [ -f "scripts/install-rea.sh" ]; then
    if command -v npm >/dev/null 2>&1; then
        bash scripts/install-rea.sh || echo "REA install failed — re-run: bash scripts/install-rea.sh"
    else
        echo "Skipping REA (npm not on PATH — open a new shell after fnm, then: bash scripts/install-rea.sh)."
    fi
fi

# 3.5f2 RE agent skills (leanrea, reverse-engineering, android-RE, ghidra-iterative-re)
if [ -f "scripts/install-re-skills.sh" ]; then
    if command -v npx >/dev/null 2>&1; then
        SKIP_SKILL_SYNC=1 bash scripts/install-re-skills.sh || \
            echo "RE skills failed — re-run: bash scripts/install-re-skills.sh"
    else
        echo "Skipping RE skills (npx not on PATH)."
    fi
fi

# 3.5g Third-party skill packs (cloudflare, emil, vercel, … — packages/agent-skills.txt)
if [ -f "scripts/install-ecosystem-skills.sh" ]; then
    if command -v npx >/dev/null 2>&1; then
        SKIP_SKILL_SYNC=1 bash scripts/install-ecosystem-skills.sh || \
            echo "Ecosystem skills failed — re-run: bash scripts/install-ecosystem-skills.sh"
    else
        echo "Skipping ecosystem skills (npx not on PATH)."
    fi
fi

# 3.5h Hub mirror after AI installers (→ Claude/Cursor/OpenCode/Kimi)
if [ -f "scripts/sync-agent-skills.sh" ]; then
    bash scripts/sync-agent-skills.sh || echo "Agent skills post-sync skipped."
fi

# 3.5i Caveman OpenCode plugin (after hub sync; coding-agents skipped this in 3.5b)
if [ -f "scripts/install-coding-agents.sh" ] && command -v npm >/dev/null 2>&1; then
    if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ]; then
        ONLY_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh || \
            echo "Caveman OpenCode plugin refresh skipped."
    fi
fi

# 3.6 PhotoGIMP (Photoshop-like GIMP layout — optional)
if [ -f "scripts/install-photogimp.sh" ]; then
    bash scripts/install-photogimp.sh || echo "PhotoGIMP setup skipped."
fi

# 3.7 Dash2Dock Animated (EGO — before extension enable)
if [ -f "scripts/install-dash2dock.sh" ]; then
    bash scripts/install-dash2dock.sh || echo "Dash2Dock setup skipped."
fi

# 3.8 Enable GNOME Extensions (list in gnome/extensions.txt)
if [ -f "scripts/install-extensions.sh" ]; then
    bash scripts/install-extensions.sh || echo "Extension enable skipped."
fi

# 4. Privacy Hardening (before health check so telemetry probes reflect final state)
if [ -f "scripts/privacy-hardener.sh" ]; then
    bash scripts/privacy-hardener.sh
fi

# 4.5 Tailscale + UFW (optional; no-op if ufw inactive / tailscale absent)
if [ -f "scripts/ufw-tailscale.sh" ] && command -v tailscale >/dev/null 2>&1; then
    bash scripts/ufw-tailscale.sh || echo "Tailscale UFW rules skipped."
fi

# 5. Final Health Check
if [ -f "scripts/check.sh" ]; then
    bash scripts/check.sh
fi

if [ -f "scripts/validate-configs.sh" ]; then
    bash scripts/validate-configs.sh || echo "Config validation reported issues."
fi

echo "Installation complete!"
