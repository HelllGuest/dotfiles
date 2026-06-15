#!/usr/bin/env bash
# vpn-location-sync.sh — sync /etc/geolocation with Proton VPN exit or home (Dubai)
#
# When proton0 is up: geolocate the VPN exit IP (one HTTPS request via the tunnel)
# and write /etc/geolocation so GeoClue + Night Theme Switcher use VPN sun times.
# When VPN is down: restore the home location from stow/system/etc/geolocation.
#
# Triggered by NetworkManager dispatcher (99-vpn-location). Manual: vpn-location-sync

set -euo pipefail

resolve_repo_root() {
    if [[ -n "${DOTFILES_ROOT:-}" && -f "${DOTFILES_ROOT}/stow/system/etc/geolocation" ]]; then
        printf '%s\n' "$DOTFILES_ROOT"
        return 0
    fi
    local real_user="${SUDO_USER:-${USER}}"
    if [[ -n "$real_user" && -f "/home/${real_user}/dotfiles/stow/system/etc/geolocation" ]]; then
        printf '%s\n' "/home/${real_user}/dotfiles"
        return 0
    fi
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/../stow/system/etc/geolocation" ]]; then
        cd "${script_dir}/.." && pwd
        return 0
    fi
    return 1
}

REPO_ROOT="$(resolve_repo_root || true)"
if [[ -z "$REPO_ROOT" ]]; then
    log() { printf '[vpn-location-sync] %s\n' "$*"; }
    log "ERROR: could not find dotfiles repo (set DOTFILES_ROOT)" >&2
    exit 1
fi
HOME_GEO="$REPO_ROOT/stow/system/etc/geolocation"
GEO_FILE="/etc/geolocation"
VPN_IF="${VPN_IF:-proton0}"
ACTION="${1:-sync}"

log() { printf '[vpn-location-sync] %s\n' "$*"; }

write_geolocation() {
    local lat="$1" lon="$2" label="$3"
    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<EOF
# ${label}
# Updated by vpn-location-sync.sh at $(date -Iseconds)
${lat}
${lon}
5
1000
EOF
    install -m 0644 -o root -g root "$tmp" "$GEO_FILE"
    rm -f "$tmp"
    log "wrote $GEO_FILE → $label ($lat, $lon)"
}

restart_geoclue() {
    if systemctl is-active geoclue.service >/dev/null 2>&1; then
        systemctl restart geoclue.service
    else
        systemctl start geoclue.service 2>/dev/null || true
    fi
    log "geoclue restarted"
}

fetch_vpn_coords() {
    local json="" lat lon city country
    # Prefer lookup bound to the VPN iface so we never touch the real egress.
    if ip link show "$VPN_IF" 2>/dev/null | grep -q 'LOWER_UP'; then
        json="$(curl -sf --max-time 15 --interface "$VPN_IF" https://ipapi.co/json/ 2>/dev/null || true)"
    fi
    if [[ -z "$json" ]]; then
        json="$(curl -sf --max-time 15 https://ipapi.co/json/ 2>/dev/null || true)"
    fi
    if [[ -z "$json" ]]; then
        log "ERROR: could not geolocate VPN exit IP" >&2
        return 1
    fi
    lat="$(echo "$json" | jq -r '.latitude // empty')"
    lon="$(echo "$json" | jq -r '.longitude // empty')"
    city="$(echo "$json" | jq -r '.city // "unknown"')"
    country="$(echo "$json" | jq -r '.country_name // .country // "unknown"')"
    if [[ -z "$lat" || -z "$lon" ]]; then
        log "ERROR: invalid geolocation response" >&2
        return 1
    fi
    write_geolocation "$lat" "$lon" "Proton VPN exit — ${city}, ${country}"
}

restore_home_location() {
    if [[ ! -f "$HOME_GEO" ]]; then
        log "ERROR: missing home geolocation template: $HOME_GEO" >&2
        return 1
    fi
    install -m 0644 -o root -g root "$HOME_GEO" "$GEO_FILE"
    log "restored home location from $HOME_GEO"
}

vpn_is_up() {
    # WireGuard (proton0) reports operstate UNKNOWN but has LOWER_UP when connected.
    ip link show "$VPN_IF" 2>/dev/null | grep -q 'LOWER_UP' \
        || nmcli -t -f GENERAL.STATE device show "$VPN_IF" 2>/dev/null | grep -q 'connected'
}

apply_sync() {
    if vpn_is_up; then
        fetch_vpn_coords
    else
        restore_home_location
    fi
    restart_geoclue
}

case "$ACTION" in
    up|vpn-up|connectivity-change|sync)
        apply_sync
        ;;
    down|pre-down|vpn-down)
        restore_home_location
        restart_geoclue
        ;;
    *)
        log "unknown action '$ACTION', running sync"
        apply_sync
        ;;
esac
