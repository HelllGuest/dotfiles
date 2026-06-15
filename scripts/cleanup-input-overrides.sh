#!/usr/bin/env bash
# cleanup-input-overrides.sh — remove legacy touchpad inhibit/udev rules only
# GNOME mouse/touchpad/keyboard settings use stock defaults (not set in dconf).

set -euo pipefail

if ! sudo -n true 2>/dev/null; then
  echo "⚠ sudo required to remove legacy udev/inhibit overrides."
  echo "  run: bash scripts/cleanup-input-overrides.sh"
  exit 0
fi

LEGACY_UDEV=(
  /etc/udev/rules.d/73-syna-phantom-mouse-ignore.rules
  /etc/udev/rules.d/73-synaptics-i2c-phantom-mouse-ignore.rules
)

echo "→ Removing legacy touchpad udev rules (if present)..."
for rule in "${LEGACY_UDEV[@]}"; do
  [[ -f "$rule" ]] && sudo rm -f "$rule"
done
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger --subsystem-match=input 2>/dev/null || true

echo "→ Uninhibiting any synaptics I2C Mouse nodes..."
for name_path in /sys/class/input/input*/name; do
  [[ -f "$name_path" ]] || continue
  name="$(cat "$name_path")"
  [[ "$name" =~ ^SYNA.*06CB:.*\ Mouse$ ]] || continue
  inhibited_file="$(dirname "$name_path")/inhibited"
  [[ -f "$inhibited_file" ]] || continue
  if [[ "$(cat "$inhibited_file")" != "0" ]]; then
    echo 0 | sudo tee "$inhibited_file" >/dev/null
    echo "  uninhibited: $name"
  fi
done

if [[ -f /etc/libinput/local-overrides.quirks ]]; then
  echo "→ Removing libinput local-overrides.quirks..."
  sudo rm -f /etc/libinput/local-overrides.quirks
fi

echo "✓ Legacy input overrides cleaned up."
