#!/usr/bin/env bash
# proton-connectivity-check.sh — diagnose Proton VPN connect failures
#
# Typical failure: ISP/router blocks api.protonvpn.ch TLS while general HTTPS works.

set -euo pipefail

PROTON_API_HOST="${PROTON_API_HOST:-api.protonvpn.ch}"
PROTON_API_URL="https://${PROTON_API_HOST}/vpn/v1/logicals"
CURL_TIMEOUT="${CURL_TIMEOUT:-20}"
FAIL=0

pass() { printf '✓ %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*"; FAIL=1; }
info() { printf '  %s\n' "$*"; }

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo "=== Proton VPN connectivity ==="

echo "--- Network ---"
if check_cmd nmcli; then
    nmcli -t -f NAME,TYPE,STATE,DEVICE connection show --active | while IFS= read -r line; do
        [[ -n "$line" ]] && info "$line"
    done
    DNS="$(nmcli -t -f IP4.DNS device show "$(nmcli -t -f DEVICE connection show --active | head -1)" 2>/dev/null | cut -d: -f2 | paste -sd ' ' - || true)"
    info "DNS: ${DNS:-unknown}"
else
    fail "nmcli missing"
fi

if ip link show proton0 >/dev/null 2>&1; then
    pass "proton0 interface up"
else
    info "proton0 not up (expected when disconnected)"
fi

echo "--- Baseline HTTPS ---"
if curl -sS -o /dev/null --max-time "$CURL_TIMEOUT" -w '' https://www.google.com 2>/dev/null; then
    pass "General HTTPS (google.com)"
else
    fail "General HTTPS unreachable — fix base internet first"
fi

echo "--- Proton API ---"
if getent ahosts "$PROTON_API_HOST" >/dev/null 2>&1; then
    IP="$(getent ahostsv4 "$PROTON_API_HOST" | awk '{print $1; exit}')"
    pass "DNS resolves ${PROTON_API_HOST} → ${IP}"
else
    fail "DNS cannot resolve ${PROTON_API_HOST}"
    info "Try: scripts/network-dns-setup.sh"
fi

CURL_ERR_FILE="$(mktemp)"
HTTP_CODE="$(curl -sS -o /dev/null --max-time "$CURL_TIMEOUT" -w '%{http_code}' "$PROTON_API_URL" 2>"$CURL_ERR_FILE" || true)"
HTTP_CODE="${HTTP_CODE:-000}"
if [[ "$HTTP_CODE" =~ ^[23] ]]; then
    pass "Proton API reachable (${PROTON_API_URL} → HTTP ${HTTP_CODE})"
elif [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
    pass "Proton API TLS OK (HTTP ${HTTP_CODE} without auth — expected)"
else
    fail "Proton API blocked or timing out (HTTP ${HTTP_CODE})"
    [[ -s "$CURL_ERR_FILE" ]] && info "$(tr '\n' ' ' <"$CURL_ERR_FILE")"
    info "ISP/network may reset TLS to Proton — try hotspot or different network"
    info "Try: scripts/network-dns-setup.sh && retry protonvpn-app"
fi
rm -f "$CURL_ERR_FILE"

echo "--- Proton app ---"
if flatpak list --app 2>/dev/null | grep -q 'com.protonvpn.www'; then
    pass "Proton VPN flatpak installed (com.protonvpn.www)"
elif command -v protonvpn-app >/dev/null 2>&1; then
    pass "protonvpn-app in PATH"
elif systemctl is-active proton.VPN.service >/dev/null 2>&1; then
    pass "proton.VPN.service active (native/AUR)"
else
    info "Proton VPN app not detected — run: bash scripts/install-flatpaks.sh"
fi

CACHE_DIR="${HOME}/.cache/Proton/VPN"
if [[ -f "${CACHE_DIR}/connection/connection_persistence.json" ]]; then
    pass "Last connection cache present"
else
    info "No connection_persistence.json — connect once in app after API works"
fi

if rg -q 'ServerListDecodeError|ProtonAPINotReachable' "${CACHE_DIR}/logs/vpn-app.log" 2>/dev/null; then
    fail "App log shows API/server-list errors"
    info "tail: ${CACHE_DIR}/logs/vpn-app.log"
else
    pass "No recent server-list errors in app log"
fi

echo "--- Result ---"
if [[ "$FAIL" -eq 0 ]]; then
    echo "Proton connectivity looks OK. Retry connect in protonvpn-app."
else
    echo "Proton connectivity issues found. Fix ✗ items above."
fi

exit "$FAIL"
