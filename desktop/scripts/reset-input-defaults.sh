#!/usr/bin/env bash
# reset-input-defaults.sh — restore GNOME stock mouse/touchpad/keyboard settings

set -euo pipefail

if ! command -v gsettings >/dev/null 2>&1; then
  echo "gsettings not found." >&2
  exit 1
fi

schemas=(
  org.gnome.desktop.peripherals.touchpad
  org.gnome.desktop.peripherals.mouse
  org.gnome.desktop.peripherals.keyboard
)

echo "→ Resetting GNOME input settings to defaults..."
for schema in "${schemas[@]}"; do
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    gsettings reset "$schema" "$key"
  done < <(gsettings list-keys "$schema")
done

gsettings reset org.gnome.nautilus.preferences click-policy 2>/dev/null || true
gsettings reset org.gnome.desktop.a11y.applications screen-keyboard-enabled 2>/dev/null || true

echo "✓ GNOME input defaults restored."
