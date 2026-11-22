#!/usr/bin/env bash
# gnome-console-setup.sh — optimize GNOME Console (kgx) via dconf

set -euo pipefail

echo "→ Configuring GNOME Console (kgx)..."

dconf write /org/gnome/Console/font-scale 1.2
dconf write /org/gnome/Console/scrollback-lines 100000
dconf write /org/gnome/Console/theme "'night'"
dconf write /org/gnome/Console/audible-bell false
dconf write /org/gnome/Console/visual-bell false
dconf write /org/gnome/Console/transparency true

PROFILE_PATH="/org/gnome/terminal/legacy/profiles:/"
DEFAULT_PROFILE=$(dconf read /org/gnome/terminal/legacy/profiles:/default 2>/dev/null | tr -d "'")

if [[ -n "$DEFAULT_PROFILE" ]]; then
    P="${PROFILE_PATH}:${DEFAULT_PROFILE}"
    dconf write "${P}/use-system-font" false
    dconf write "${P}/font" "'JetBrainsMono Nerd Font 11'"
    dconf write "${P}/use-transparent-background" true
    dconf write "${P}/background-transparency-percent" 5
    dconf write "${P}/scrollback-unlimited" true
    dconf write "${P}/audible-bell" false
    dconf write "${P}/bold-is-bright" true
    dconf write "${P}/cursor-shape" "'block'"
    dconf write "${P}/cursor-blink-mode" "'on'"
fi

# GNOME media-keys / custom-keybindings live in gnome/dconf/user.conf (do not overwrite here).

# kitty is primary (Super+Return, xdg-terminals.list); keep MIME handler in sync.
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default kitty.desktop x-scheme-handler/terminal 2>/dev/null || true
fi

echo "✓ GNOME Console configured"
