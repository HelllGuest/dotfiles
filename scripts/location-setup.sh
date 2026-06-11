#!/usr/bin/env bash
# location-setup.sh — GeoClue location spoofing (home Dubai + Proton VPN sync)
#
# - Disables GeoClue IP/WiFi lookup (no real-location leak)
# - Home coords in stow/system/etc/geolocation (Dubai)
# - vpn-location-sync.sh updates /etc/geolocation to VPN exit when proton0 is up
# - NetworkManager dispatcher triggers sync on connect/disconnect
# - GNOME panel extension proton-vpn@helllguest shows spoofed location + manual sync
#
# Does NOT spoof browser geolocation (WebRTC/IP).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOW_DIR="$REPO_ROOT/stow"
GEO_FILE="$REPO_ROOT/stow/system/etc/geolocation"
GEOCLUE_DROPIN="$REPO_ROOT/stow/system/etc/geoclue/conf.d/99-static-dubai.conf"
NM_DISPATCHER="$REPO_ROOT/stow/system/etc/NetworkManager/dispatcher.d/99-vpn-location"
POLKIT_RULE="$REPO_ROOT/stow/system/etc/polkit-1/rules.d/50-vpn-location-sync.rules"
VPN_SYNC="$REPO_ROOT/scripts/vpn-location-sync.sh"

if [[ ! -f "$GEO_FILE" ]]; then
  echo "Missing: $GEO_FILE" >&2
  exit 1
fi

chmod +x "$VPN_SYNC"
mkdir -p "$HOME/.local/bin"
ln -sf "$VPN_SYNC" "$HOME/.local/bin/vpn-location-sync"

echo "→ Installing vpn-location-sync to /usr/local/bin..."
sudo install -m 0755 -o root -g root "$VPN_SYNC" /usr/local/bin/vpn-location-sync

echo "→ Installing GeoClue config (static file only, no IP/WiFi)..."
sudo install -m 0644 -o root -g root "$GEOCLUE_DROPIN" /etc/geoclue/conf.d/99-static-dubai.conf

echo "→ Installing NetworkManager VPN location dispatcher..."
sudo install -m 0755 -o root -g root "$NM_DISPATCHER" /etc/NetworkManager/dispatcher.d/99-vpn-location

if [[ -f "$POLKIT_RULE" ]]; then
  echo "→ Installing polkit rule (passwordless sync for $(whoami))..."
  sudo install -m 0644 -o root -g root "$POLKIT_RULE" /etc/polkit-1/rules.d/50-vpn-location-sync.rules
fi

echo "→ Syncing location (VPN exit if connected, else home)..."
sudo /usr/local/bin/vpn-location-sync sync

if command -v gsettings >/dev/null 2>&1; then
  echo "→ Enabling GNOME location (coords from /etc/geolocation only)..."
  gsettings set org.gnome.system.location enabled true
fi

if command -v gnome-extensions >/dev/null 2>&1; then
  echo "→ Enabling Proton VPN panel extension..."
  gnome-extensions enable proton-vpn@helllguest 2>/dev/null || \
    echo "  ⚠ enable after GNOME Shell restart if needed"
fi

if [[ -f "$REPO_ROOT/scripts/network-dns-setup.sh" ]]; then
  echo "→ Applying trusted DNS on active NetworkManager connection..."
  bash "$REPO_ROOT/scripts/network-dns-setup.sh" || true
fi

echo ""
echo "✓ Location spoofing ready."
echo "  Home:     stow/system/etc/geolocation (Dubai)"
echo "  VPN:      auto-sync on proton0 up/down"
echo "  Manual:   vpn-location-sync  |  panel menu → Sync location now"
echo "  Panel:    proton-vpn@helllguest → Spoofed location section"
echo ""
cat /etc/geolocation 2>/dev/null | head -n 6
