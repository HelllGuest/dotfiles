#!/usr/bin/env bash
# firewalld-lab-zones.sh — ensure firewalld drop + lab/libvirt zone binds.
#
# Stage A already installs firewalld (DefaultZone=drop). This script wires:
#   virbr0        → libvirt      (Kali / NAT guests)
#   virbr-malware → lab-malware  (host-only 192.168.200.0/24; DROP; no masq/forward)
#
# Idempotent. Safe to re-run. Does not install or enable UFW.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/lab-malware-zone.sh
source "$REPO_ROOT/security/lib/lab-malware-zone.sh"

echo "→ Ensuring firewalld + CLI monitors..."
sudo pacman -S --needed --noconfirm firewalld htop btop fastfetch

# Hygiene: never let a leftover ufw package fight nftables.
if pacman -Q ufw >/dev/null 2>&1; then
  echo "→ Removing leftover ufw package..."
  sudo systemctl disable --now ufw 2>/dev/null || true
  sudo systemctl mask ufw 2>/dev/null || true
  sudo pacman -Rns --noconfirm ufw || true
fi

echo "→ Configuring nftables backend + default zone drop..."
sudo install -d -m 0755 /etc/firewalld
if [[ ! -f /etc/firewalld/firewalld.conf ]]; then
  printf '%s\n' '# managed by firewalld-lab-zones.sh' 'DefaultZone=drop' 'FirewallBackend=nftables' \
    | sudo tee /etc/firewalld/firewalld.conf >/dev/null
else
  if sudo grep -q '^FirewallBackend=' /etc/firewalld/firewalld.conf; then
    sudo sed -i 's/^FirewallBackend=.*/FirewallBackend=nftables/' /etc/firewalld/firewalld.conf
  else
    echo 'FirewallBackend=nftables' | sudo tee -a /etc/firewalld/firewalld.conf >/dev/null
  fi
  if sudo grep -q '^DefaultZone=' /etc/firewalld/firewalld.conf; then
    sudo sed -i 's/^DefaultZone=.*/DefaultZone=drop/' /etc/firewalld/firewalld.conf
  else
    echo 'DefaultZone=drop' | sudo tee -a /etc/firewalld/firewalld.conf >/dev/null
  fi
fi

sudo systemctl unmask firewalld 2>/dev/null || true
sudo systemctl enable --now firewalld

# --set-default-zone already persists; --permanent is invalid with it.
sudo firewall-cmd --set-default-zone=drop || true

# libvirt zone XML ships with the libvirt package; dnsmasq is required by
# libvirt virtual networks (default + virbr-malware DHCP).
if ! sudo firewall-cmd --permanent --get-zones 2>/dev/null | grep -qw libvirt; then
  echo "→ Installing libvirt + dnsmasq (firewalld libvirt zone + virbr-malware DHCP)..."
  sudo pacman -S --needed --noconfirm libvirt dnsmasq
  sudo firewall-cmd --reload || true
elif ! command -v dnsmasq >/dev/null 2>&1; then
  echo "→ Installing dnsmasq (required for libvirt virbr-malware DHCP)..."
  sudo pacman -S --needed --noconfirm dnsmasq
fi

if command -v virsh >/dev/null 2>&1; then
  sudo systemctl enable --now libvirtd.service 2>/dev/null || true
  sudo virsh net-start default 2>/dev/null || true
  sudo virsh net-autostart default 2>/dev/null || true
fi

echo "→ Binding virbr0 to firewalld zone libvirt (permanent)..."
sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 \
  || sudo firewall-cmd --permanent --zone=libvirt --list-interfaces 2>/dev/null | grep -qw virbr0 \
  || { echo "firewalld-lab-zones: failed to bind virbr0 → libvirt" >&2; exit 1; }
if [[ -d /sys/class/net/virbr0 ]]; then
  sudo firewall-cmd --zone=libvirt --change-interface=virbr0 \
    || { echo "firewalld-lab-zones: runtime virbr0 → libvirt failed" >&2; exit 1; }
fi

# Create/load the lab-malware firewalld zone BEFORE virsh net-start: the bridge
# XML sets zone="lab-malware", so libvirt fails with INVALID_ZONE if it doesn't
# exist in firewalld yet.
echo "→ Ensuring firewalld zone lab-malware..."
ensure_lab_malware_zone

# Host-only malware net (no forward / no NAT)
MALWARE_XML="$(mktemp)"
trap 'rm -f "$MALWARE_XML"' EXIT
# dns enable=no → INetSim owns :53; dhcp-option=6 still advertises 192.168.200.1
# so guest resolv.conf is not empty. zone=lab-malware stops libvirt reclaiming the
# bridge into the stock libvirt firewalld zone on every reload/start.
cat >"$MALWARE_XML" <<'EOF'
<network xmlns:dnsmasq="http://libvirt.org/schemas/network/dnsmasq/1.0">
  <name>virbr-malware</name>
  <bridge name="virbr-malware" zone="lab-malware" stp="on" delay="0"/>
  <domain name="malware.lab"/>
  <dns enable="no"/>
  <ip address="192.168.200.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.200.50" end="192.168.200.99"/>
    </dhcp>
  </ip>
  <dnsmasq:options>
    <dnsmasq:option value="dhcp-option=6,192.168.200.1"/>
  </dnsmasq:options>
</network>
EOF

if command -v virsh >/dev/null 2>&1; then
  _redef=0
  if ! sudo virsh net-info virbr-malware >/dev/null 2>&1; then
    echo "→ Defining libvirt host-only network virbr-malware..."
    sudo virsh net-define "$MALWARE_XML"
  else
    _xml="$(sudo virsh net-dumpxml virbr-malware 2>/dev/null || true)"
    if grep -q '<forward' <<<"$_xml" \
      || ! grep -qE "<dns[^>]*enable=['\"]no['\"]" <<<"$_xml" \
      || ! grep -q 'dhcp-option=6,192.168.200.1' <<<"$_xml" \
      || ! grep -qE 'zone=['\"]lab-malware['\"]' <<<"$_xml"; then
      _redef=1
    fi
  fi
  if [[ $_redef -eq 1 ]]; then
    echo "→ Redefining virbr-malware (no forward; dns off; zone=lab-malware)..."
    sudo virsh net-destroy virbr-malware 2>/dev/null || true
    sudo virsh net-undefine virbr-malware 2>/dev/null || true
    sudo virsh net-define "$MALWARE_XML"
  fi
  unset -v _redef _xml
  sudo virsh net-autostart virbr-malware >/dev/null 2>&1 || true
  _ninfo="$(sudo virsh net-info virbr-malware 2>/dev/null || true)"
  if ! grep -qiE '^Active:[[:space:]]+yes' <<<"$_ninfo"; then
    sudo virsh net-start virbr-malware
  fi
  unset -v _ninfo
fi

if [[ -d /sys/class/net/virbr0 ]]; then
  sudo firewall-cmd --zone=libvirt --change-interface=virbr0 \
    || { echo "firewalld-lab-zones: re-assert virbr0 → libvirt failed" >&2; exit 1; }
fi
if [[ -d /sys/class/net/virbr-malware ]]; then
  sudo firewall-cmd --zone=lab-malware --change-interface=virbr-malware \
    || { echo "firewalld-lab-zones: re-assert virbr-malware → lab-malware failed" >&2; exit 1; }
fi

echo "✓ firewalld active (default=$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo ?))"
echo "  virbr0 → libvirt; virbr-malware → lab-malware (DROP, no masq/forward)"
