#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running health check..."

# 1. Check for required binaries
REQUIRED_BINARIES=("stow" "zsh" "starship" "nvim" "ghostty" "fastfetch" "dconf" "jq")
SHELL_BINARIES=("atuin" "fzf" "fd" "rg" "bat" "eza" "zoxide" "direnv" "delta")
for bin in "${REQUIRED_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        echo "✗ $bin is missing"
    fi
done

echo "--- Shell productivity tools ---"
for bin in "${SHELL_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        echo "✗ $bin is missing"
    fi
done

if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git" ]; then
    echo "✓ zinit is bootstrapped"
else
    echo "✗ zinit not bootstrapped (launch zsh once)"
fi

# 2. Check for symlinks
check_link() {
    local path=$1
    if [ -L "$path" ]; then
        echo "✓ Symlink exists: $path"
    elif [ -L "$(dirname "$path")" ] && [ -f "$path" ]; then
        echo "✓ Stowed via $(dirname "$path") -> $(readlink "$(dirname "$path")")"
    else
        echo "✗ Symlink missing: $path"
    fi
}

CHECK_LINKS=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.shell-git" "$HOME/.config/starship.toml" "$HOME/.config/atuin/config.toml" "$HOME/.config/nvim/init.lua" "$HOME/.config/fastfetch/config.jsonc")
for link in "${CHECK_LINKS[@]}"; do
    check_link "$link"
done

# 3. Check for fonts
NERD_FONT_COUNT=$(fc-list : family | grep -ci 'Nerd Font' || true)
if [ "$NERD_FONT_COUNT" -gt 0 ]; then
    echo "✓ Nerd Fonts installed ($NERD_FONT_COUNT families)"
else
    echo "✗ Nerd Fonts missing — run scripts/install-fonts.sh"
fi
if fc-list : family | grep -qi "JetBrainsMono"; then
    echo "✓ JetBrainsMono Nerd Font is installed"
else
    echo "✗ JetBrainsMono Nerd Font is missing"
fi

echo "--- GDM login screen ---"
if grep -q 'WaylandEnable=true' /etc/gdm/custom.conf 2>/dev/null; then
    echo "✓ GDM WaylandEnable=true"
else
    echo "✗ GDM WaylandEnable not set (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    echo "✓ GDM greeter dconf deployed"
else
    echo "✗ GDM greeter dconf missing"
fi
if [ -f /etc/systemd/system/gdm.service.d/override.conf ]; then
    if grep -q 'WAYLAND_DISPLAY' /etc/systemd/system/gdm.service.d/override.conf 2>/dev/null; then
        echo "✗ GDM override still sets WAYLAND_DISPLAY (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM override has no WAYLAND_DISPLAY"
    fi
else
    echo "✗ GDM systemd override missing (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    gdm_dconf_owner="$(stat -c '%U' /etc/dconf/db/gdm.d/00-login-screen 2>/dev/null || echo unknown)"
    if [ "$gdm_dconf_owner" = root ]; then
        echo "✓ GDM greeter dconf owned by root"
    else
        echo "✗ GDM greeter dconf owned by $gdm_dconf_owner (run scripts/gdm-setup.sh)"
    fi
fi
if [ -e /etc/dconf/profile/gdm ]; then
    if [ -L /etc/dconf/profile/gdm ] && readlink /etc/dconf/profile/gdm 2>/dev/null | grep -qE "$HOME|dotfiles"; then
        echo "✗ GDM dconf profile symlinks into home (run scripts/gdm-setup.sh)"
    elif [ -L /etc/dconf/profile/gdm ]; then
        echo "✗ GDM dconf profile is symlink (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM dconf profile is real file in /etc"
    fi
else
    echo "✗ GDM dconf profile missing (run scripts/gdm-setup.sh)"
fi
if systemctl show gdm.service -p DropInPaths --value 2>/dev/null | grep -q 'gdm.service.d/override.conf'; then
    echo "✓ GDM systemd drop-in loaded"
else
    echo "✗ GDM systemd drop-in not loaded (sudo systemctl daemon-reload)"
fi

echo "--- Git ---"
if [ -f "$HOME/.config/git/config" ]; then
    echo "✓ Git XDG config deployed"
else
    echo "✗ Git config missing (run scripts/git-setup.sh)"
fi
if command -v delta >/dev/null 2>&1; then
    echo "✓ delta is installed"
else
    echo "✗ delta is missing"
fi
if git config --get user.email >/dev/null 2>&1; then
    echo "✓ Git identity: $(git config --get user.name) <$(git config --get user.email)>"
else
    echo "✗ Git identity not set"
fi

echo "--- Neovim ---"
if [ -f "$HOME/.config/nvim/init.lua" ]; then
    echo "✓ Neovim config deployed"
else
    echo "✗ Neovim config missing (run scripts/nvim-setup.sh)"
fi
if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim" ]; then
    echo "✓ lazy.nvim bootstrapped"
else
    echo "✗ lazy.nvim not bootstrapped (run scripts/nvim-setup.sh)"
fi

echo "--- GNOME session ---"
if [ -f "$HOME/.config/gnome-session/scripts/tablet-mode-handler.sh" ]; then
    echo "✓ Tablet mode handler stowed"
else
    echo "✗ Tablet mode handler missing"
fi
ENABLED_EXT=$(gnome-extensions list --enabled 2>/dev/null | wc -l || echo 0)
if [ "$ENABLED_EXT" -ge 5 ] 2>/dev/null; then
    echo "✓ GNOME extensions enabled ($ENABLED_EXT)"
else
    echo "✗ Few GNOME extensions enabled (run scripts/gnome-session-setup.sh)"
fi

echo "--- Proton VPN ---"
if [ -f "$REPO_ROOT/scripts/proton-connectivity-check.sh" ]; then
    bash "$REPO_ROOT/scripts/proton-connectivity-check.sh" 2>/dev/null || echo "⚠ Proton API unreachable (run scripts/proton-connectivity-check.sh)"
else
    echo "✗ proton-connectivity-check.sh missing"
fi

echo "--- Config validation ---"
if [ -f "$REPO_ROOT/scripts/validate-configs.sh" ]; then
    bash "$REPO_ROOT/scripts/validate-configs.sh" 2>/dev/null || echo "⚠ Run scripts/validate-configs.sh for details"
fi

echo "Health check finished."
