#!/usr/bin/env bash
# firewalld-tailscale.sh — allow Tailscale interface + WireGuard port in firewalld.
set -euo pipefail

command -v firewall-cmd >/dev/null 2>&1 || {
  echo "firewalld-tailscale: firewall-cmd missing — run scripts/firewalld-lab-zones.sh first" >&2
  exit 0
}
systemctl is-active --quiet firewalld 2>/dev/null || {
  echo "firewalld-tailscale: firewalld inactive — skip" >&2
  exit 0
}

# Trusted mesh interface
if [[ -d /sys/class/net/tailscale0 ]]; then
  sudo firewall-cmd --permanent --zone=trusted --change-interface=tailscale0 || true
  sudo firewall-cmd --zone=trusted --change-interface=tailscale0 || true
fi
# WireGuard UDP used by Tailscale
sudo firewall-cmd --permanent --add-port=41641/udp || true
sudo firewall-cmd --reload || true
echo "✓ Tailscale firewalld rules applied"
