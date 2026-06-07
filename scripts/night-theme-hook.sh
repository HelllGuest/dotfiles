#!/usr/bin/env bash
# night-theme-hook.sh — GTK/cursor day/night hook for Night Theme Switcher v82+
# NTS v82 only toggles org.gnome.desktop.interface color-scheme; Catppuccin GTK
# themes must be applied here via the extension's sunrise/sunset commands.
#
# Usage: night-theme-hook.sh day|night|sync

set -euo pipefail

mode="${1:-sync}"

if [[ "$mode" == "sync" ]]; then
    case "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo '')" in
        *prefer-dark*) mode=night ;;
        *prefer-light*) mode=day ;;
        *)
            hour=$(date +%H)
            if (( hour >= 6 && hour < 20 )); then
                mode=day
            else
                mode=night
            fi
            ;;
    esac
fi

case "$mode" in
    day)
        gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-latte-blue-standard+default'
        ;;
    night)
        gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-blue-standard+default'
        gsettings set org.gnome.desktop.interface cursor-theme 'catppuccin-mocha-dark-cursors'
        ;;
    *)
        echo "Usage: $(basename "$0") day|night|sync" >&2
        exit 1
        ;;
esac
