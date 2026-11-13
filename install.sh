#!/bin/bash

# Arch GNOME Rice Installer
# Run from a GNOME session terminal after first login (Stage B in README).
# dconf, extension enable, and gsettings steps need an active user session.

# Ensure we are in the repo root
cd "$(dirname "$0")" || exit 1

# Ensure user-local tool paths are on PATH on fresh first-boot bash sessions
for _p in "$HOME/.opencode/bin" "$HOME/.npm-global/bin" "${PNPM_HOME:-$HOME/.local/share/pnpm}" "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_p:"*) ;;
        *) export PATH="$_p:$PATH" ;;
    esac
done
unset _p

# Critical steps set this; optional tools stay soft-skip. Exit 1 at end if set.
INSTALL_FAILED=0
INSTALL_FAIL_REASONS=()
fail_step() {
    echo "$1"
    INSTALL_FAILED=1
    INSTALL_FAIL_REASONS+=("$1")
}

echo "Starting installation..."

# Legacy touchpad udev/inhibit cleanup (if present from older dotfiles)
if [ -f "scripts/cleanup-input-overrides.sh" ]; then
    bash scripts/cleanup-input-overrides.sh || echo "Input override cleanup skipped."
fi

# 1. Install packages (before machine profile — NVIDIA/Optimus needs nvidia-* present)
if [ -f "packages/pacman.txt" ]; then
    echo "Installing pacman packages..."
    # pacman does not skip "#" lines on stdin ("target not found: # …" aborts
    # the whole transaction), so strip comments/blank lines first.
    # tuned-ppd provides+conflicts power-profiles-daemon; asking for PPD would make
    # --noconfirm refuse the removal and abort the whole transaction.
    pkg_list="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' packages/pacman.txt)"
    if pacman -Q tuned-ppd >/dev/null 2>&1; then
        pkg_list="$(printf '%s\n' "$pkg_list" | grep -vx 'power-profiles-daemon' || true)"
    fi
    if [ -f "scripts/lib/dmi.sh" ]; then
        # shellcheck source=scripts/lib/dmi.sh
        source scripts/lib/dmi.sh
        if is_thinkpad_t14s; then
            # Drop Intel/NVIDIA Optimus stack (incl. egl-wayland) on AMD T14s.
            pkg_list="$(printf '%s\n' "$pkg_list" | grep -vxE 'intel-media-driver|vulkan-intel|nvidia-open-dkms|nvidia-prime|nvidia-utils|egl-wayland' || true)"
        fi
    fi
    if [ -n "$pkg_list" ]; then
        printf '%s\n' "$pkg_list" | sudo pacman -S --needed --noconfirm - \
            || fail_step "Package install failed (sudo / network / conflict) — see pacman output above."
    fi
    unset pkg_list
fi

# 1.05 Machine profile (hostname override, else hardware detect)
# Runs after pacman so thinkpad-p15 can enable nvidia-*.service and rebuild UKIs.
if [ -f "scripts/apply-profile.sh" ]; then
    bash scripts/apply-profile.sh \
        || fail_step "Profile application failed (sudo / hardware setup) — see output above."
fi

# 1.06 Stage B configurator (firewalld / ollama / profile) — TTY only
if [ "${SKIP_CONFIGURE:-0}" != 1 ] && [ -t 0 ] && [ -f scripts/configure.sh ]; then
    if [ "${CONFIGURE:-0}" = 1 ] || [ "${CONFIGURE:-}" = Y ]; then
        bash scripts/configure.sh || echo "configure.sh reported issues."
    else
        echo "Stage B modules: run  bash scripts/configure.sh  (or CONFIGURE=1 ./install.sh)"
    fi
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
        bash ../scripts/system-setup.sh || fail_step "System setup failed (sudo required)."
    elif [ "$dir" = "gdm" ]; then
        echo "Skipping gdm (handled by scripts/gdm-setup.sh)."
    elif [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir" \
            || fail_step "stow failed for package: $dir"
    else
        $STOW_CMD "$dir" "$HOME" \
            || fail_step "minimal-stow failed for package: $dir"
    fi
done
cd .. || exit 1

# 2.1 Bootstrap Node.js LTS via fnm (avoids bleeding-edge system node breaking native addons)
if command -v fnm >/dev/null 2>&1; then
    echo "Setting up Node.js LTS (22) via fnm..."
    eval "$(fnm env --shell bash)"
    fnm install 22 || echo "fnm install 22 failed — skipping."
    fnm default 22 || true
    fnm use 22 || true
    eval "$(fnm env --shell bash)"
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

# 3.5c1 Ponytail (lazy senior dev mode; pinned tag + skills/hooks/plugins)
if [ -f "scripts/install-ponytail.sh" ]; then
    if command -v node >/dev/null 2>&1; then
        SKIP_SKILL_SYNC=1 bash scripts/install-ponytail.sh || \
            echo "Ponytail install failed — re-run: bash scripts/install-ponytail.sh"
    else
        echo "Skipping ponytail (node not on PATH)."
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

# 3.5f REA backends live in lab-re (JDK21/Ghidra/jadx). Host install-rea is
# optional only (needs host JDK>=21); prefer: lab-re --check && lab-re

# 3.5f1 Obscura headless browser + MCP (OpenCode/Cursor/Claude)
if [ -f "scripts/install-obscura.sh" ]; then
    bash scripts/install-obscura.sh || echo "Obscura install failed — re-run: bash scripts/install-obscura.sh"
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

# 3.5j AI stack extras (Continue FIM config, P15 OpenCode↔ollama, hr-proxy unit).
# Cores (Headroom / coding-agents / Caveman / Ponytail) already ran above.
if [ -f "scripts/ai-stack-setup.sh" ]; then
    AI_STACK_EXTRAS_ONLY=1 bash scripts/ai-stack-setup.sh \
        || echo "AI stack extras skipped — re-run: AI_STACK_EXTRAS_ONLY=1 bash scripts/ai-stack-setup.sh"
fi

# 3.5k Local LLM on P15 (ollama-cuda + qwen pulls; no-op on other hosts).
# Opt out: SKIP_OLLAMA=1 ./install.sh
if [ "${SKIP_OLLAMA:-0}" != 1 ] && [ -f "scripts/ollama-setup.sh" ]; then
    bash scripts/ollama-setup.sh \
        || echo "ollama setup skipped — re-run: bash scripts/ollama-setup.sh"
fi

# 3.6 PhotoGIMP (Photoshop-like GIMP layout — optional)
if [ -f "scripts/install-photogimp.sh" ]; then
    bash scripts/install-photogimp.sh || echo "PhotoGIMP setup skipped."
fi

# 3.6a foxcage: Firefox in a rootless Podman container (pinned commit + SHA-256)
if [ "${SKIP_FOXCAGE:-0}" = 1 ]; then
    echo "Skipping foxcage (SKIP_FOXCAGE=1)."
elif ! command -v podman >/dev/null 2>&1; then
    echo "Skipping foxcage (podman not installed)."
elif [ -f "scripts/install-foxcage.sh" ]; then
    bash scripts/install-foxcage.sh || echo "foxcage install failed — re-run: bash scripts/install-foxcage.sh"
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
    bash scripts/privacy-hardener.sh || fail_step "Privacy hardener failed."
fi

# 4.5 Tailscale + firewalld (optional; no-op if firewalld inactive / tailscale absent)
if [ -f "scripts/firewalld-tailscale.sh" ] && command -v tailscale >/dev/null 2>&1; then
    bash scripts/firewalld-tailscale.sh || echo "Tailscale firewalld rules skipped."
fi

# 5. Final Health Check
if [ -f "scripts/check.sh" ]; then
    bash scripts/check.sh \
        || fail_step "Health check reported failures (✗) — see output above."
fi

if [ -f "scripts/validate-configs.sh" ]; then
    bash scripts/validate-configs.sh || echo "Config validation reported issues."
fi

if [ "$INSTALL_FAILED" -ne 0 ]; then
    echo "Installation finished with failures:"
    for _r in "${INSTALL_FAIL_REASONS[@]}"; do
        echo "  - $_r"
    done
    unset _r
    exit 1
fi

echo "Installation complete!"
