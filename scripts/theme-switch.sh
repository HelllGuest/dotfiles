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
    
    case "$template" in
        *.scss)
            if command -v sass >/dev/null 2>&1; then
                sass "${output}.tmp" "${output}.css"
                echo "Compiled $output.css"
            else
                mv "${output}.tmp" "${output}.scss"
                echo "sass not found, kept as scss."
            fi
            ;;
        *.toml)
            mv "${output}.tmp" "${output}.toml"
            echo "Generated $output.toml"
            ;;
    esac
}

process_template "theming/templates/gtk.scss" "theming/generated/gtk"
process_template "theming/templates/starship.toml" "theming/generated/starship"

# Update Starship Config
SS_CFG="stow/starship/.config/starship.toml"
if [ -f "$SS_CFG" ]; then
    cp theming/generated/starship.toml "$SS_CFG"
fi
cp theming/generated/starship.toml "$HOME/.config/starship.toml" 2>/dev/null || true

# 3. Update Wallpaper
if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
    echo "Updating wallpaper to $WALLPAPER"
    gsettings set org.gnome.desktop.background picture-uri "file://$(realpath "$WALLPAPER")"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$(realpath "$WALLPAPER")"
fi

# 4. Update Terminal (Kitty/Ghostty)
KITTY_STOW="stow/kitty/.config/kitty/current-theme.conf"
KITTY_HOME="$HOME/.config/kitty/current-theme.conf"
if [ -d "stow/kitty" ]; then
    cat <<EOF > "$KITTY_STOW"
# Generated theme: $PALETTE_NAME
background $BG
foreground $FG
selection_background $ACCENT
selection_foreground $BG
cursor $ACCENT
active_tab_background $ACCENT
active_tab_foreground $BG
inactive_tab_background $BG
inactive_tab_foreground $FG
EOF
    cp "$KITTY_STOW" "$KITTY_HOME" 2>/dev/null || true
    echo "Updated Kitty theme."
fi

GHOSTTY_STOW="stow/ghostty/.config/ghostty/theme.conf"
GHOSTTY_HOME="$HOME/.config/ghostty/theme.conf"
if [ -d "stow/ghostty" ]; then
     cat <<EOF > "$GHOSTTY_STOW"
background = $BG
foreground = $FG
selection-background = $ACCENT
selection-foreground = $BG
palette = 0=$BG
palette = 8=$BG
EOF
    cp "$GHOSTTY_STOW" "$GHOSTTY_HOME" 2>/dev/null || true
    echo "Updated Ghostty theme."
fi

# 4. Update Neovim Palette (Lua)
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

# Set GTK3 theme for non-libadwaita apps
gsettings set org.gnome.desktop.interface gtk-theme "Zukitwo-dark"

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
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Save current theme state
echo "$PALETTE_NAME" > "theming/generated/current_theme.txt"

echo "Theme update complete for $PALETTE_NAME."
