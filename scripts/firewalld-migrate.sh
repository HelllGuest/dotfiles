#!/usr/bin/env bash
# firewalld-migrate.sh — replace UFW with firewalld (nftables, default drop).
# Rewires libvirt virbr0 → libvirt zone; creates host-only virbr-malware → lab-malware.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/lab-malware-zone.sh
source "$REPO_ROOT/scripts/lib/lab-malware-zone.sh"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="/var/backups/dotfiles-ufw-${STAMP}"

echo "→ Backing up UFW config to $BACKUP (if present)..."
if [[ -d /etc/ufw ]]; then
  sudo install -d -m 0700 "$BACKUP"
  sudo cp -a /etc/ufw "$BACKUP/" 2>/dev/null || true
fi

if command -v ufw >/dev/null 2>&1; then
  echo "→ Disabling UFW..."
  sudo ufw --force disable 2>/dev/null || true
fi
sudo systemctl disable --now ufw 2>/dev/null || true
sudo systemctl mask ufw 2>/dev/null || true

echo "→ Installing firewalld..."
sudo pacman -S --needed --noconfirm firewalld

echo "→ Configuring nftables backend + default zone drop..."
sudo install -d -m 0755 /etc/firewalld
if [[ ! -f /etc/firewalld/firewalld.conf ]]; then
  printf '%s\n' '# managed by firewalld-migrate.sh' 'DefaultZone=drop' 'FirewallBackend=nftables' \
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

# Default zone — --set-default-zone already persists; --permanent is invalid here
# (firewall-cmd: "Can't use stand-alone options with other options").
sudo firewall-cmd --set-default-zone=drop || true

# libvirt zone XML ships with the libvirt package (not firewalld alone).
if ! firewall-cmd --permanent --get-zones 2>/dev/null | grep -qw libvirt; then
  echo "→ Installing libvirt (provides firewalld libvirt zone + virsh)..."
  sudo pacman -S --needed --noconfirm libvirt
  sudo firewall-cmd --reload || true
fi

# libvirt default NAT (virbr0) → libvirt zone
if command -v virsh >/dev/null 2>&1; then
  sudo systemctl enable --now libvirtd.service 2>/dev/null || true
  sudo virsh net-start default 2>/dev/null || true
  sudo virsh net-autostart default 2>/dev/null || true
fi
# Permanent add-interface so zone sticks when bridge appears later.
echo "→ Binding virbr0 to firewalld zone libvirt (permanent)..."
sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 || true
if [[ -d /sys/class/net/virbr0 ]]; then
  sudo firewall-cmd --zone=libvirt --change-interface=virbr0 || true
fi

# Host-only malware net (no forward / no NAT)
MALWARE_XML="$(mktemp)"
trap 'rm -f "$MALWARE_XML"' EXIT
cat >"$MALWARE_XML" <<'EOF'
<network>
  <name>virbr-malware</name>
  <bridge name="virbr-malware" stp="on" delay="0"/>
  <domain name="malware.lab"/>
  <ip address="192.168.200.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.200.50" end="192.168.200.99"/>
    </dhcp>
  </ip>
</network>
EOF

if command -v virsh >/dev/null 2>&1; then
  if ! sudo virsh net-info virbr-malware >/dev/null 2>&1; then
    echo "→ Defining libvirt host-only network virbr-malware..."
    sudo virsh net-define "$MALWARE_XML"
  fi
  # Ensure forward mode is none (host-only): redefine if an older NAT copy exists.
  if sudo virsh net-dumpxml virbr-malware 2>/dev/null | grep -q '<forward'; then
    sudo virsh net-destroy virbr-malware 2>/dev/null || true
    sudo virsh net-undefine virbr-malware 2>/dev/null || true
    sudo virsh net-define "$MALWARE_XML"
  fi
  sudo virsh net-autostart virbr-malware 2>/dev/null || true
  sudo virsh net-start virbr-malware 2>/dev/null || true
fi

echo "→ Binding virbr-malware to firewalld zone lab-malware..."
ensure_lab_malware_zone

# libvirt may reattach bridges at start; re-assert runtime zones.
if [[ -d /sys/class/net/virbr0 ]]; then
  sudo firewall-cmd --zone=libvirt --change-interface=virbr0 || true
fi
if [[ -d /sys/class/net/virbr-malware ]]; then
  sudo firewall-cmd --zone=lab-malware --change-interface=virbr-malware || true
fi

echo "✓ firewalld active (default=$(firewall-cmd --get-default-zone 2>/dev/null || echo ?))"
echo "  virbr0 → libvirt zone; virbr-malware → lab-malware zone (DROP, no masq/forward)"
echo "  UFW backup: $BACKUP"
