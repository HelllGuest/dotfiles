#!/bin/bash

echo "Applying privacy hardening (disabling telemetry and reporting)..."

# 1. GNOME Privacy Settings
if command -v gsettings >/dev/null 2>&1; then
    echo "Hardening GNOME privacy settings..."
    gsettings set org.gnome.desktop.privacy report-technical-problems false
    gsettings set org.gnome.desktop.privacy send-software-usage-stats false
    gsettings set org.gnome.desktop.privacy connectivity-checking false
    gsettings set org.gnome.desktop.privacy remember-recent-files false
    gsettings set org.gnome.desktop.privacy remember-app-usage false
    
    # Disable automatic update checks in GNOME Software
    gsettings set org.gnome.Software download-updates false
    
    # Disable location services (often phones home)
    gsettings set org.gnome.system.location enabled false
else
    echo "gsettings not found. Skipping GNOME hardening."
fi

# 2. Environment Variables to disable telemetry for common tools
# Adding these to stow/zsh/.zsh-exports
# DOTNET_CLI_TELEMETRY_OPTOUT=1
# POWERSHELL_TELEMETRY_OPTOUT=1

echo "Privacy hardening complete."
