#!/usr/bin/env bash
# ufw-tailscale.sh — UFW allow tailnet traffic (official Tailscale guidance).
#
# Default Tailscale netfilter-mode=on already accepts tailscale0 in its own
# chains. These UFW rules still help when locking down (deny incoming) or when
# using --netfilter-mode=off. Safe to re-run (ufw skips duplicates).
#
# Docs: https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw
set -euo pipefail

sudo_do() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  elif [[ -t 0 ]]; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed — skip"
  exit 0
fi
if ! sudo_do ufw status 2>/dev/null | grep -qi 'Status: active'; then
  echo "ufw inactive — skip (enable first)"
  exit 0
fi

# Interface may be absent until tailscaled starts once; rule still stores.
echo "→ UFW allow in on tailscale0"
sudo_do ufw allow in on tailscale0 comment 'tailscale' >/dev/null

# Better P2P; DERP works without this.
echo "→ UFW allow 41641/udp (Tailscale WireGuard)"
sudo_do ufw allow 41641/udp comment 'tailscale-wg' >/dev/null

# Harmless on clients; needed if this host is ever an exit node / subnet router.
echo "→ UFW route allow on tailscale0"
sudo_do ufw route allow in on tailscale0 >/dev/null 2>&1 || true
sudo_do ufw route allow out on tailscale0 >/dev/null 2>&1 || true

echo "✓ Tailscale UFW rules applied (see: sudo ufw status numbered)"
