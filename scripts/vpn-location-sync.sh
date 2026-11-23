#!/usr/bin/env bash
# vpn-location-sync.sh — sync /etc/geolocation with Proton VPN exit or home location
#
# When proton0 is up: geolocate the VPN exit IP (one HTTPS request via the tunnel)
# and write /etc/geolocation so GeoClue + Night Theme Switcher use VPN sun times.
# When VPN is down: restore the home location from stow/system/etc/geolocation.local
# (gitignored), else the tracked placeholder stow/system/etc/geolocation.
#
# Triggered by NetworkManager dispatcher (99-vpn-location). Manual: vpn-location-sync

set -euo pipefail

# Fixed path: a root script must not take the binary it runs from the env.
CURL=/usr/bin/curl
INSTALLED_HOME_GEO="/usr/local/share/vpn-location-sync/home.geolocation"

resolve_repo_root() {
    if [[ -n "${DOTFILES_ROOT:-}" && -f "${DOTFILES_ROOT}/stow/system/etc/geolocation" ]]; then
        printf '%s\n' "$DOTFILES_ROOT"
        return 0
    fi

    local real_user="" home_dir=""
    if [[ -n "${SUDO_USER:-}" ]]; then
        real_user="$SUDO_USER"
    elif [[ -n "${PKEXEC_UID:-}" ]]; then
        real_user="$(id -nu "$PKEXEC_UID" 2>/dev/null || true)"
    elif [[ -n "${USER:-}" && "$USER" != "root" ]]; then
        real_user="$USER"
    fi

    if [[ -n "$real_user" ]]; then
        home_dir="$(getent passwd "$real_user" 2>/dev/null | cut -d: -f6 || true)"
        if [[ -n "$home_dir" && -f "${home_dir}/dotfiles/stow/system/etc/geolocation" ]]; then
            printf '%s\n' "${home_dir}/dotfiles"
            return 0
        fi
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/../stow/system/etc/geolocation" ]]; then
        cd "${script_dir}/.." && pwd
        return 0
    fi
    return 1
}

# As root (NM dispatcher, or pkexec without a password via the polkit rule)
# never read a user-writable path: a symlink planted at the user's
# geolocation(.local) would make root copy any file (e.g. /etc/shadow) to the
# world-readable /etc/geolocation. Root only uses the root-owned copy that
# location-setup.sh installs; the repo lookup is for unprivileged runs.
HOME_GEO=""
if (( EUID == 0 )); then
    if [[ -f "$INSTALLED_HOME_GEO" && ! -L "$INSTALLED_HOME_GEO" \
          && "$(stat -c %u "$INSTALLED_HOME_GEO")" == 0 ]]; then
        HOME_GEO="$INSTALLED_HOME_GEO"
    fi
else
    REPO_ROOT="$(resolve_repo_root || true)"
    if [[ -n "$REPO_ROOT" ]]; then
        HOME_GEO="$REPO_ROOT/stow/system/etc/geolocation"
        [[ -f "$HOME_GEO.local" ]] && HOME_GEO="$HOME_GEO.local"
    elif [[ -f "$INSTALLED_HOME_GEO" ]]; then
        HOME_GEO="$INSTALLED_HOME_GEO"
    fi
fi
log() { printf '[vpn-location-sync] %s\n' "$*"; }

if [[ -z "$HOME_GEO" ]]; then
    log "ERROR: no trusted home geolocation (run location-setup.sh; root uses $INSTALLED_HOME_GEO only)" >&2
    exit 1
fi
GEO_FILE="/etc/geolocation"
VPN_IF="${VPN_IF:-proton0}"
ACTION="${1:-sync}"
SYNC_TMPS=()
trap '(( ${#SYNC_TMPS[@]} )) && rm -f -- "${SYNC_TMPS[@]}"' EXIT

write_geolocation() {
    local lat="$1" lon="$2" label="$3"
    local tmp
    tmp="$(mktemp)"
    SYNC_TMPS+=("$tmp")
    if ! cat >"$tmp" <<EOF
# ${label}
# Updated by vpn-location-sync.sh at $(date -Iseconds)
${lat}
${lon}
5
1000
EOF
    then
        rm -f "$tmp"
        return 1
    fi
    if ! install -m 0644 -o root -g root "$tmp" "$GEO_FILE"; then
        rm -f "$tmp"
        return 1
    fi
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
    local json="" lat lon city country attempt
    # Only through the tunnel: an unbound fallback would send the real (ISP)
    # address to ipapi.co whenever the tunnel is not carrying traffic.
    if ip link show "$VPN_IF" 2>/dev/null | grep -q 'LOWER_UP'; then
        for attempt in 1 2; do
            json="$("$CURL" -sf --max-time 15 --interface "$VPN_IF" https://ipapi.co/json/ 2>/dev/null || true)"
            [[ -n "$json" ]] && break
            [[ "$attempt" -eq 1 ]] && sleep 1
        done
    fi
    if [[ -z "$json" ]]; then
        log "ERROR: could not geolocate VPN exit IP" >&2
        return 1
    fi
    lat="$(echo "$json" | jq -r '.latitude // empty')"
    lon="$(echo "$json" | jq -r '.longitude // empty')"
    city="$(echo "$json" | jq -r '.city // "unknown"')"
    country="$(echo "$json" | jq -r '.country_name // .country // "unknown"')"
    # Network data lands in /etc as root: accept plain decimal degrees only,
    # and keep the label on its one comment line (no newlines/control chars).
    local num='^-?[0-9]{1,3}(\.[0-9]+)?$'
    if [[ ! $lat =~ $num || ! $lon =~ $num ]] \
        || (( ${lat%%.*} < -90 || ${lat%%.*} > 90 || ${lon%%.*} < -180 || ${lon%%.*} > 180 )); then
        log "ERROR: invalid geolocation response" >&2
        return 1
    fi
    city="$(printf '%s' "$city" | tr -d '[:cntrl:]' | cut -c1-64)"
    country="$(printf '%s' "$country" | tr -d '[:cntrl:]' | cut -c1-64)"
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
        if ! fetch_vpn_coords; then
            # Never leave real home coords active during a VPN session on lookup failure.
            write_geolocation "0.0" "0.0" "Proton VPN exit — lookup failed (neutral placeholder)"
            restart_geoclue
            return 1
        fi
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
