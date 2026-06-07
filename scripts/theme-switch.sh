#!/bin/bash

# theme-switch.sh
# Usage: ./theme-switch.sh [palette_name]

PALETTE_NAME=$1
PALETTE_DIR="theming/palettes"

if [ -z "$PALETTE_NAME" ]; then
    echo "Usage: ts [palette_name]"
    echo "Available palettes:"
    ls "$PALETTE_DIR"/*.json | xargs -n 1 basename | sed 's/\.json//' | grep -v "base"
    exit 1
fi

PALETTE_FILE="${PALETTE_DIR}/${PALETTE_NAME}.json"
if [ ! -f "$PALETTE_FILE" ]; then
    echo "Palette $PALETTE_NAME not found in ${PALETTE_DIR}/"
    exit 1
fi

echo "Switching to theme: $PALETTE_NAME"

# 1. Handle Inheritance and Extract values using jq
# Merge base and current palette if 'extends' exists
PARENT=$(jq -r '.extends // empty' "$PALETTE_FILE")
if [ -n "$PARENT" ] && [ -f "$PARENT" ]; then
    echo "Merging with $PARENT"
    # Merge nested objects properly
    MERGED_PALETTE=$(jq -s '.[0] * .[1]' "$PARENT" "$PALETTE_FILE")
else
    MERGED_PALETTE=$(cat "$PALETTE_FILE")
fi

BG=$(echo "$MERGED_PALETTE" | jq -r '.background')
FG=$(echo "$MERGED_PALETTE" | jq -r '.foreground')
ACCENT=$(echo "$MERGED_PALETTE" | jq -r '.accent')
WALLPAPER=$(echo "$MERGED_PALETTE" | jq -r '.wallpaper // empty')
RADIUS=$(echo "$MERGED_PALETTE" | jq -r '.border_radius // "12px"')
SIGMA=$(echo "$MERGED_PALETTE" | jq -r '.blur_sigma // "30"')

# Starship specific extractions
SS_SUCCESS=$(echo "$MERGED_PALETTE" | jq -r '.starship.success')
SS_ERROR=$(echo "$MERGED_PALETTE" | jq -r '.starship.error')
SS_DIR=$(echo "$MERGED_PALETTE" | jq -r '.starship.directory')

# 2. Process Templates
mkdir -p theming/generated

process_template() {
    local template=$1
    local output=$2
    sed -e "s/{{background}}/$BG/g" \
        -e "s/{{foreground}}/$FG/g" \
        -e "s/{{accent}}/$ACCENT/g" \
        -e "s/{{border_radius}}/$RADIUS/g" \
        -e "s/{{blur_sigma}}/$SIGMA/g" \
        -e "s/{{starship.success}}/$SS_SUCCESS/g" \
        -e "s/{{starship.error}}/$SS_ERROR/g" \
        -e "s/{{starship.directory}}/$SS_DIR/g" \
        "$template" > "${output}.tmp"

    if command -v sass >/dev/null 2>&1; then
        sass "${output}.tmp" "${output}.css"
        echo "Compiled $output.css"
    else
        mv "${output}.tmp" "${output}.scss"
        echo "sass not found, kept as scss."
    fi
}

process_template "theming/templates/gtk.scss" "theming/generated/gtk"

# Update Starship (Crampack preset palette)
CRAMPACK_PALETTE=$(echo "$MERGED_PALETTE" | jq -r '.crampack_palette // "mellow"')
SS_CFG="stow/starship/.config/starship.toml"
if [ -f "$SS_CFG" ]; then
    sed -i "s/^palette = \".*\"/palette = \"$CRAMPACK_PALETTE\"/" "$SS_CFG"
    cp "$SS_CFG" "$HOME/.config/starship.toml" 2>/dev/null || true
    echo "Updated Starship Crampack palette: $CRAMPACK_PALETTE"
fi

# 3. Update Wallpaper
if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
    echo "Updating wallpaper to $WALLPAPER"
    gsettings set org.gnome.desktop.background picture-uri "file://$(realpath "$WALLPAPER")"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$(realpath "$WALLPAPER")"
fi

# 4. Update Terminal themes (Kitty / Ghostty)
T_BG="$BG"
T_FG="$FG"
T_ACCENT="$ACCENT"
T_BLACK=$(echo "$MERGED_PALETTE" | jq -r '.black // .nord1 // .background')
T_RED=$(echo "$MERGED_PALETTE" | jq -r '.red // .nord11 // .starship.error // "#f7768e"')
T_GREEN=$(echo "$MERGED_PALETTE" | jq -r '.green // .nord14 // .starship.success // "#9ece6a"')
T_YELLOW=$(echo "$MERGED_PALETTE" | jq -r '.yellow // .nord13 // "#e0af68"')
T_BLUE=$(echo "$MERGED_PALETTE" | jq -r '.blue // .nord9 // .accent')
T_MAGENTA=$(echo "$MERGED_PALETTE" | jq -r '.magenta // .nord15 // "#bb9af7"')
T_CYAN=$(echo "$MERGED_PALETTE" | jq -r '.cyan // .nord8 // "#7dcfff"')
T_WHITE=$(echo "$MERGED_PALETTE" | jq -r '.white // .nord4 // .foreground')
T_BR_BLACK=$(echo "$MERGED_PALETTE" | jq -r '.bright_black // .nord3 // .black // .nord1 // .background')
T_BR_RED=$(echo "$MERGED_PALETTE" | jq -r '.bright_red // .red // .nord11 // .starship.error // "#f7768e"')
T_BR_GREEN=$(echo "$MERGED_PALETTE" | jq -r '.bright_green // .green // .nord14 // .starship.success // "#9ece6a"')
T_BR_YELLOW=$(echo "$MERGED_PALETTE" | jq -r '.bright_yellow // .yellow // .nord13 // "#e0af68"')
T_BR_BLUE=$(echo "$MERGED_PALETTE" | jq -r '.bright_blue // .blue // .nord9 // .accent')
T_BR_MAGENTA=$(echo "$MERGED_PALETTE" | jq -r '.bright_magenta // .magenta // .nord15 // "#bb9af7"')
T_BR_CYAN=$(echo "$MERGED_PALETTE" | jq -r '.bright_cyan // .cyan // .nord8 // "#7dcfff"')
T_BR_WHITE=$(echo "$MERGED_PALETTE" | jq -r '.bright_white // .white // .nord5 // .foreground')
T_CURSOR=$(echo "$MERGED_PALETTE" | jq -r '.cursor // .accent')

strip_hash() { echo "${1//#/}"; }

KITTY_STOW="stow/kitty/.config/kitty/current-theme.conf"
KITTY_HOME="$HOME/.config/kitty/current-theme.conf"
if [ -d "stow/kitty" ]; then
    cat <<EOF > "$KITTY_STOW"
# Generated theme: $PALETTE_NAME
foreground              $T_FG
background              $T_BG
selection_foreground    $T_BG
selection_background    $T_ACCENT
cursor                  $T_CURSOR
cursor_text_color       $T_BG
url_color               $T_BLUE

active_tab_foreground   $T_BG
active_tab_background   $T_ACCENT
inactive_tab_foreground $T_FG
inactive_tab_background $T_BLACK
tab_bar_background      $T_BLACK

active_border_color     $T_BLUE
inactive_border_color   $T_BR_BLACK
bell_border_color       $T_RED

color0  $T_BLACK
color8  $T_BR_BLACK
color1  $T_RED
color9  $T_BR_RED
color2  $T_GREEN
color10 $T_BR_GREEN
color3  $T_YELLOW
color11 $T_BR_YELLOW
color4  $T_BLUE
color12 $T_BR_BLUE
color5  $T_MAGENTA
color13 $T_BR_MAGENTA
color6  $T_CYAN
color14 $T_BR_CYAN
color7  $T_WHITE
color15 $T_BR_WHITE
EOF
    cp "$KITTY_STOW" "$KITTY_HOME" 2>/dev/null || true
    echo "Updated Kitty theme."
fi

GHOSTTY_STOW="stow/ghostty/.config/ghostty/theme.conf"
GHOSTTY_HOME="$HOME/.config/ghostty/theme.conf"
if [ -d "stow/ghostty" ]; then
    cat <<EOF > "$GHOSTTY_STOW"
# Generated theme: $PALETTE_NAME
background = $(strip_hash "$T_BG")
foreground = $(strip_hash "$T_FG")
selection-background = $(strip_hash "$T_ACCENT")
selection-foreground = $(strip_hash "$T_BG")
cursor-color = $(strip_hash "$T_CURSOR")
cursor-text = $(strip_hash "$T_BG")
palette-generate = true
palette = 0=#$(strip_hash "$T_BLACK")
palette = 1=#$(strip_hash "$T_RED")
palette = 2=#$(strip_hash "$T_GREEN")
palette = 3=#$(strip_hash "$T_YELLOW")
palette = 4=#$(strip_hash "$T_BLUE")
palette = 5=#$(strip_hash "$T_MAGENTA")
palette = 6=#$(strip_hash "$T_CYAN")
palette = 7=#$(strip_hash "$T_WHITE")
palette = 8=#$(strip_hash "$T_BR_BLACK")
palette = 9=#$(strip_hash "$T_RED")
palette = 10=#$(strip_hash "$T_GREEN")
palette = 11=#$(strip_hash "$T_YELLOW")
palette = 12=#$(strip_hash "$T_BLUE")
palette = 13=#$(strip_hash "$T_MAGENTA")
palette = 14=#$(strip_hash "$T_CYAN")
palette = 15=#$(strip_hash "$T_WHITE")
EOF
    cp "$GHOSTTY_STOW" "$GHOSTTY_HOME" 2>/dev/null || true
    echo "Updated Ghostty theme."
fi

# 4.5 Delta diff colors (git-delta)
DELTA_THEME="stow/git/.config/git/delta-theme.conf"
if [ -d "stow/git" ]; then
    T_PLUS_BG=$(echo "$MERGED_PALETTE" | jq -r '.green // .starship.success // "#73d216"')
    T_MINUS_BG=$(echo "$MERGED_PALETTE" | jq -r '.red // .starship.error // "#cc0000"')
    T_ZERO=$(echo "$MERGED_PALETTE" | jq -r '.bright_black // .black // "#555753"')
    T_GUTTER=$(echo "$MERGED_PALETTE" | jq -r '.black // .background // "#1e2021"')
    cat <<EOF > "$DELTA_THEME"
# Generated by theme-switch.sh — delta diff colors
[delta]
	plus-style                  = syntax "#1a3a2a"
	plus-emph-style             = syntax "#2a5a3a"
	minus-style                 = syntax "#3a1a2a"
	minus-emph-style            = syntax "#5a1a3a"
	line-numbers-plus-style     = "$T_PLUS_BG"
	line-numbers-minus-style    = "$T_MINUS_BG"
	line-numbers-zero-style     = "$T_ZERO"
	line-numbers-left-style     = "$T_GUTTER"
	line-numbers-right-style    = "$T_GUTTER"
EOF
    cp "$DELTA_THEME" "$HOME/.config/git/delta-theme.conf" 2>/dev/null || true
    echo "Updated delta theme."
fi

# 4.6 GDM login screen background (solid, matches palette)
GDM_DCONF="stow/gdm/etc/dconf/db/gdm.d/00-login-screen"
if [ -f "$GDM_DCONF" ]; then
    sed -i "s|primary-color='#[^']*'|primary-color='$BG'|g" "$GDM_DCONF"
    sed -i "s|secondary-color='#[^']*'|secondary-color='$BG'|g" "$GDM_DCONF"
    if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
        sudo dconf update 2>/dev/null && echo "Updated GDM login screen colors."
    else
        echo "GDM login colors saved in stow (run scripts/gdm-setup.sh to deploy)."
    fi
fi

# 5. Update Neovim Palette (Lua)
NVIM_PALETTE="stow/nvim/.config/nvim/lua/palette.lua"
cat <<EOF > "$NVIM_PALETTE"
-- Generated Neovim Palette
local M = {}
M.background = "$BG"
M.foreground = "$FG"
M.accent = "$ACCENT"
M.success = "$SS_SUCCESS"
M.error = "$SS_ERROR"
M.directory = "$SS_DIR"
return M
EOF
echo "Updated Neovim palette."

# 5. Apply GTK 3.0 & 4.0 Styles
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cp theming/generated/gtk.css "$HOME/.config/gtk-3.0/gtk.css"
cp theming/generated/gtk.css "$HOME/.config/gtk-4.0/gtk.css"

# 6. Set Icon and GTK3 Theme
if gsettings get org.gnome.desktop.interface icon-theme | grep -qv "Papirus-Dark"; then
    echo "Setting icon theme to Papirus-Dark..."
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
fi

# Set GTK3 theme for non-libadwaita apps (skip when Night Theme Switcher manages GTK)
if gnome-extensions list --enabled 2>/dev/null | grep -q 'nightthemeswitcher@romainvigier.fr'; then
    echo "Skipping GTK theme override (Night Theme Switcher active)."
else
    gsettings set org.gnome.desktop.interface gtk-theme "Zukitwo-dark"
fi

# 7. Update Flatpak Theme (if present)
if command -v flatpak >/dev/null 2>&1; then
    echo "Syncing theme to Flatpak..."
    # Give flatpaks access to local themes and force dark mode env
    flatpak override --user --env=GTK_THEME=Adwaita-dark
    # BleachBit specific fix if it's still stubborn
    flatpak override --user --env=GTK_THEME=Adwaita-dark org.bleachbit.BleachBit
fi

# Revert GNOME Shell theme to Default if it was set to Generated-Theme
CURRENT_SHELL_THEME=$(gsettings get org.gnome.shell.extensions.user-theme name)
if [ "$CURRENT_SHELL_THEME" == "'Generated-Theme'" ]; then
    gsettings set org.gnome.shell.extensions.user-theme name "Default"
fi
# Leave color-scheme to Night Theme Switcher when active (v82 toggles prefer-light/dark).
if ! gnome-extensions list --enabled 2>/dev/null | grep -q 'nightthemeswitcher@romainvigier.fr'; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
fi

# Save current theme state
echo "$PALETTE_NAME" > "theming/generated/current_theme.txt"

echo "Theme update complete for $PALETTE_NAME."
