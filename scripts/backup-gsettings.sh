#!/bin/bash

echo "Backing up GNOME settings..."
dconf dump /org/gnome/ > gnome/dconf-settings.ini
echo "Done."
