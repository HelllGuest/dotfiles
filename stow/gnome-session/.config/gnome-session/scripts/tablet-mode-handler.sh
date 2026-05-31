#!/usr/bin/env bash
# tablet-mode-handler.sh — X1 Yoga Gen 5 convertible mode (iio-sensor-proxy + lid)

MODE_FILE="/tmp/.yoga-mode"

set_tablet_mode() {
  local mode="$1"
  echo "$mode" > "$MODE_FILE"

  case "$mode" in
    tablet|tent|stand)
      gsettings set org.gnome.desktop.peripherals.touchpad send-events disabled
      gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
      gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock false
      notify-send --icon=input-touchscreen "Tablet Mode" "Keyboard disabled, touch active" \
        --urgency=low --expire-time=2000 2>/dev/null || true
      ;;
    laptop)
      gsettings set org.gnome.desktop.peripherals.touchpad send-events enabled
      gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false
      gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock true
      notify-send --icon=input-keyboard "Laptop Mode" "Keyboard and touchpad active" \
        --urgency=low --expire-time=2000 2>/dev/null || true
      ;;
  esac
}

monitor_orientation() {
  dbus-monitor --system \
    "type='signal',interface='org.freedesktop.DBus.Properties',path='/net/hadess/SensorProxy'" \
  | while read -r line; do
      if echo "$line" | grep -q "AccelerometerOrientation"; then
        read -r _orientation_line
        LID_STATE=$(cat /proc/acpi/button/lid/LID*/state 2>/dev/null | grep -oE 'open|closed' | head -1)
        if [[ "$LID_STATE" == "closed" ]]; then
          set_tablet_mode "tablet"
        else
          set_tablet_mode "laptop"
        fi
      fi
    done
}

if [[ -n "${1:-}" ]]; then
  set_tablet_mode "$1"
else
  monitor_orientation
fi
