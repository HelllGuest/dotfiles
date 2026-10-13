#!/usr/bin/env bash
# ptyxis-setup.sh — rice Ptyxis to match kitty/ghostty (gsettings/dconf)

set -euo pipefail

echo "→ Configuring Ptyxis..."

# Ensure a default profile exists (first launch creates one).
if [[ -z "$(gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null | tr -d "'")" ]]; then
  timeout 3s ptyxis -e true >/dev/null 2>&1 || true
fi

gsettings set org.gnome.Ptyxis use-system-font false
gsettings set org.gnome.Ptyxis font-name 'JetBrainsMono Nerd Font 13'
gsettings set org.gnome.Ptyxis audible-bell false
gsettings set org.gnome.Ptyxis visual-bell false
gsettings set org.gnome.Ptyxis cursor-shape 'block'
gsettings set org.gnome.Ptyxis cursor-blink-mode 'on'
gsettings set org.gnome.Ptyxis default-columns 120
gsettings set org.gnome.Ptyxis default-rows 34
gsettings set org.gnome.Ptyxis disable-padding false
gsettings set org.gnome.Ptyxis prompt-on-close false
gsettings set org.gnome.Ptyxis restore-window-size false
gsettings set org.gnome.Ptyxis interface-style 'dark'

PROFILE="$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")"
if [[ -n "$PROFILE" ]]; then
  PATH_BASE="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${PROFILE}/"
  gsettings set "$PATH_BASE" opacity 0.95
  gsettings set "$PATH_BASE" scrollback-lines 50000
  gsettings set "$PATH_BASE" limit-scrollback true
  gsettings set "$PATH_BASE" bold-is-bright true
  gsettings set "$PATH_BASE" scroll-on-output false
  gsettings set "$PATH_BASE" scroll-on-keystroke true
  echo "  profile $PROFILE → opacity 0.95, scrollback 50000"
else
  echo "  WARN: no default profile UUID yet — open Ptyxis once, re-run this script"
fi

echo "✓ Ptyxis configured"
