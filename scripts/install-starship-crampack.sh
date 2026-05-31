#!/bin/bash
# install-starship-crampack.sh
# Non-interactive installer for Crampack Starship presets.
# Upstream: https://github.com/Noktomezo/CrampackForStarship
# One-liner: bash <(curl -fsSL "https://git.new/crampack-sh")

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/Noktomezo/CrampackForStarship/refs/heads/main/themes"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_CFG="$REPO_ROOT/stow/starship/.config/starship.toml"
HOME_CFG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [preset]

Presets:
  1  Standard (Nerd Font)     [default]
  2  Plain text
  3  Emoji
  4  Full text

Environment:
  STARSHIP_CONFIG  Override destination path (default: ~/.config/starship.toml)
EOF
}

preset="${1:-1}"
case "$preset" in
    1|standard)     file="crampack.toml" ;;
    2|plain|plain-text) file="crampack-plain-text.toml" ;;
    3|emoji)        file="crampack-emoji.toml" ;;
    4|full|full-text) file="crampack-full-text.toml" ;;
    -h|--help)      usage; exit 0 ;;
    *)
        echo "Invalid preset: $preset" >&2
        usage >&2
        exit 1
        ;;
esac

if ! command -v starship >/dev/null 2>&1; then
    echo "Warning: starship not found in PATH. Config will be installed anyway." >&2
fi

mkdir -p "$(dirname "$STOW_CFG")" "$(dirname "$HOME_CFG")"

echo "Downloading Crampack preset: $file"
curl -fsSL "$BASE_URL/$file" -o "$STOW_CFG"
cp "$STOW_CFG" "$HOME_CFG"

echo "Installed to:"
echo "  $STOW_CFG"
echo "  $HOME_CFG"
echo "Reload your shell: exec zsh"
