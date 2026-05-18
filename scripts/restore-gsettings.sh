#!/bin/bash

echo "Restoring GNOME settings..."
dconf load /org/gnome/ < gnome/dconf-settings.ini
echo "Done."
