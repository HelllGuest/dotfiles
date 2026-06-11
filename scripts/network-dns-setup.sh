#!/usr/bin/env bash
# network-dns-setup.sh — override router DNS on NetworkManager connections
#
# Router DNS (often ISP) can block or poison VPN provider API lookups.
# Usage:
#   network-dns-setup.sh              # active connection
#   network-dns-setup.sh --all-wifi   # all wifi profiles
#   network-dns-setup.sh MyWifi  # named profile

set -euo pipefail

PRIMARY_DNS="${PRIMARY_DNS:-1.1.1.1}"
SECONDARY_DNS="${SECONDARY_DNS:-1.0.0.1}"
MODE="active"
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all-wifi) MODE="all-wifi"; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--all-wifi] [connection-name]"
            exit 0
            ;;
        *)
            MODE="named"
            TARGET="$1"
            shift
            ;;
    esac
done

if ! command -v nmcli >/dev/null 2>&1; then
    echo "nmcli not found." >&2
    exit 1
fi

mapfile -t CONNECTIONS < <(
    case "$MODE" in
        active)
            nmcli -t -f NAME connection show --active | rg -v '^lo$' || true
            ;;
        all-wifi)
            nmcli -t -f NAME,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }'
            ;;
        named)
            printf '%s\n' "$TARGET"
            ;;
    esac
)

if [[ "${#CONNECTIONS[@]}" -eq 0 ]] || [[ -z "${CONNECTIONS[0]:-}" ]]; then
    echo "No matching NetworkManager connections." >&2
    exit 1
fi

for conn in "${CONNECTIONS[@]}"; do
    [[ -z "$conn" ]] && continue
    echo "→ $conn: DNS ${PRIMARY_DNS} ${SECONDARY_DNS} (ignore auto-dns)"
    nmcli connection modify "$conn" \
        ipv4.dns "${PRIMARY_DNS} ${SECONDARY_DNS}" \
        ipv4.ignore-auto-dns yes \
        ipv6.dns "2606:4700:4700::1111 2606:4700:4700::1001" \
        ipv6.ignore-auto-dns yes
done

ACTIVE="$(nmcli -t -f NAME connection show --active | rg -v '^lo$' | head -1 || true)"
if [[ -n "$ACTIVE" ]]; then
    echo "→ Reapplying active connection: $ACTIVE"
    nmcli connection up "$ACTIVE" >/dev/null
fi

echo "✓ DNS updated. Verify: scripts/proton-connectivity-check.sh"
