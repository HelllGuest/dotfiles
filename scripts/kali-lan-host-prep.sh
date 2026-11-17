#!/usr/bin/env bash
# kali-lan-host-prep.sh — prepare host RJ45 for Kali macvtap LAN.
#
# WiFi keeps the only default gateway. The physical NIC is left UP with no
# addresses so macvtap bridge mode can reach the LAN. A host address on the
# parent (especially a /0) eats frames and blocks guest↔LAN peers.
#
# Usage (on the libvirt host):
#   sudo bash scripts/kali-lan-host-prep.sh [IFACE]
#   pkexec /usr/local/bin/kali-lan-host-prep [IFACE]   # after location-style install
#
# Env: KALI_LAN_IFACE (default enp0s31f6)

set -euo pipefail

IFACE="${1:-${KALI_LAN_IFACE:-enp0s31f6}}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Runs as root without a password (pkexec + 50-kali-lan-host-prep.rules), so
# any process of a wheel user can pick the argument. Accept only a physical
# wired Ethernet NIC: never Wi-Fi, the VPN tunnel (proton0/wg/tun), bridges or
# other virtual links, whose addresses/routes this script flushes.
# valid_lan_iface NAME SYS_CLASS_NET  (sysfs root is a parameter for tests only)
valid_lan_iface() {
  local name=$1 sys=$2 type
  [[ $name =~ ^[A-Za-z0-9_.:-]{1,15}$ && $name != . && $name != .. ]] || { echo "invalid interface name"; return 1; }
  [[ -d $sys/$name ]] || { echo "missing iface $name"; return 1; }
  [[ -e $sys/$name/device ]] || { echo "$name is not a physical NIC"; return 1; }
  type=$(cat "$sys/$name/type" 2>/dev/null || true)
  [[ $type == 1 ]] || { echo "$name is not Ethernet (type ${type:-?})"; return 1; }
  [[ ! -e $sys/$name/wireless && ! -e $sys/$name/phy80211 ]] || { echo "$name is wireless"; return 1; }
  return 0
}

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo/pkexec)"
reason="$(valid_lan_iface "$IFACE" /sys/class/net)" || die "refusing $IFACE: $reason"

echo "→ prep host LAN $IFACE for Kali macvtap (no host IP/gateway)"

# Stop NM from re-addressing the RJ45.
if command -v nmcli >/dev/null 2>&1; then
  nmcli device set "$IFACE" managed no >/dev/null 2>&1 || true
  # Disable autoconnect on any ethernet profile bound to this device.
  while IFS=: read -r name uuid device; do
    [[ "$device" == "$IFACE" ]] || continue
    nmcli connection modify "$uuid" connection.autoconnect no ipv4.method disabled ipv6.method disabled >/dev/null 2>&1 || true
    nmcli connection down "$uuid" >/dev/null 2>&1 || true
  done < <(nmcli -t -f NAME,UUID,DEVICE connection show 2>/dev/null || true)
fi

ip addr flush dev "$IFACE" || true
# Drop defaults that still point at the RJ45.
while read -r _ _ gw _ iface _; do
  [[ "$iface" == "$IFACE" ]] || continue
  ip route del default via "$gw" dev "$IFACE" >/dev/null 2>&1 || true
done < <(ip -4 route show default 2>/dev/null || true)

ip link set "$IFACE" up || die "could not admin-up $IFACE"

# Fail closed if IPv4 remains ( /0 is fatal for macvtap).
if ip -4 -o addr show dev "$IFACE" 2>/dev/null | grep -q .; then
  ip -4 addr show dev "$IFACE" >&2 || true
  die "$IFACE still has IPv4 — macvtap LAN will stay broken"
fi

if ! ip -br link show "$IFACE" | grep -q 'LOWER_UP\|UP'; then
  echo "  note: $IFACE has no carrier — plug ethernet cable"
fi

echo "✓ $IFACE ready for macvtap (wifi/NAT keep default route)"
ip -br link show "$IFACE"
