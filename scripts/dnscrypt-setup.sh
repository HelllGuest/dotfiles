#!/usr/bin/env bash
# dnscrypt-setup.sh — encrypted DNS via dnscrypt-proxy + NetworkManager
#
# Listens on 127.0.0.1 / ::1, points active NM connection at localhost.
# Tailscale MagicDNS (when connected) may override NM DNS — that is OK;
# encrypted DNS applies when MagicDNS is off / Tailscale down.
#
# Usage:
#   bash scripts/dnscrypt-setup.sh
#   SKIP_NM=1 bash scripts/dnscrypt-setup.sh     # daemon only
#   SKIP_ENABLE=1 bash scripts/dnscrypt-setup.sh # config only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF=/etc/dnscrypt-proxy/dnscrypt-proxy.toml

say() { printf '→ %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

if ! command -v dnscrypt-proxy >/dev/null 2>&1; then
  die "dnscrypt-proxy not installed — pacman -S dnscrypt-proxy (or ./install.sh)"
fi

if [[ ! -f $CONF ]]; then
  die "missing $CONF — reinstall dnscrypt-proxy"
fi

# Stock Arch toml listens on 127.0.0.1:53 only. Add [::1]:53 so NM ipv6 → ::1 works.
want="listen_addresses = ['127.0.0.1:53', '[::1]:53']"
if ! grep -qxF "$want" "$CONF" 2>/dev/null; then
  say "set $want"
  sudo cp -a "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
  if grep -qE '^listen_addresses\s*=' "$CONF"; then
    sudo sed -i -E \
      "s|^listen_addresses\s*=.*|$want|" \
      "$CONF"
  else
    printf '\n%s\n' "$want" | sudo tee -a "$CONF" >/dev/null
  fi
fi

if [[ "${SKIP_ENABLE:-0}" != 1 ]]; then
  say "enable --now dnscrypt-proxy.service"
  sudo systemctl enable --now dnscrypt-proxy.service \
    || die "could not enable dnscrypt-proxy"
  systemctl is-active --quiet dnscrypt-proxy \
    || die "dnscrypt-proxy not active — journalctl -u dnscrypt-proxy"
fi

if [[ "${SKIP_NM:-0}" != 1 ]]; then
  if [[ -f "$REPO_ROOT/scripts/network-dns-setup.sh" ]]; then
    say "point NetworkManager DNS at dnscrypt (127.0.0.1 / ::1)"
    PRIMARY_DNS=127.0.0.1 SECONDARY_DNS=127.0.0.1 \
      PRIMARY_DNS6=::1 SECONDARY_DNS6=::1 \
      bash "$REPO_ROOT/scripts/network-dns-setup.sh" \
      || warn "network-dns-setup failed — set DNS manually to 127.0.0.1"
  else
    warn "network-dns-setup.sh missing"
  fi
fi

if command -v tailscale >/dev/null 2>&1 && tailscale status &>/dev/null; then
  warn "Tailscale is up — MagicDNS may override NM DNS while connected"
fi

echo "✓ dnscrypt-proxy ready"
echo "  verify: resolvectl query example.com 2>/dev/null || dig @127.0.0.1 example.com"
echo "  or:     dig @127.0.0.1 example.com +short"
