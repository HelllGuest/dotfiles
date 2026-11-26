#!/usr/bin/env bash
# input helpers — synaptics I2C phantom Mouse detection

list_phantom_syna_mice() {
  local name_path name input_dir inhibited
  for name_path in /sys/class/input/input*/name; do
    [[ -f "$name_path" ]] || continue
    name="$(cat "$name_path")"
    [[ "$name" =~ ^SYNA.*06CB:.*\ Mouse$ ]] || continue
    input_dir="$(dirname "$name_path")"
    inhibited="$(cat "$input_dir/inhibited" 2>/dev/null || echo 0)"
    printf 'Device:           %s (inhibited=%s)\n' "$name" "$inhibited"
  done
}

# True when a synaptics I2C phantom Mouse node is kernel-inhibited (breaks clicks).
phantom_syna_mouse_inhibited() {
  [[ "$(list_phantom_syna_mice)" == *"(inhibited=1)"* ]]
}
