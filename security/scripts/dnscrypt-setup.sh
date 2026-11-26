#!/usr/bin/env bash
# dnscrypt-setup.sh — encrypted DNS via dnscrypt-proxy + NetworkManager
#
# Listens on 127.0.0.1 / ::1, points active NM connection at localhost.
# Tailscale MagicDNS (when connected) may override NM DNS — that is OK;
# encrypted DNS applies when MagicDNS is off / Tailscale down.
#
# Usage:
#   bash security/scripts/dnscrypt-setup.sh
#   SKIP_NM=1 bash security/scripts/dnscrypt-setup.sh     # daemon only
#   SKIP_ENABLE=1 bash security/scripts/dnscrypt-setup.sh # config only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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

# Per-connection DNS (network-dns-setup.sh) only covers connections that exist
# now: any Wi-Fi joined later would use its DHCP DNS in plaintext, outside
# dnscrypt. NetworkManager global DNS overrides that for every connection.
# Global DNS also overrides what Tailscale (MagicDNS on tailscale0) and Proton
# VPN (NetShield DNS on proton0) push. Tailnet names keep working through a
# per-domain section for the MagicDNS suffix; Proton lookups still go through
# the tunnel to dnscrypt (encrypted), only NetShield filtering is bypassed.
# install_nm_global_dns ETC_ROOT [TAILNET_SUFFIX]
#   ETC_ROOT="" = real /etc via sudo; tests pass a dir.
install_nm_global_dns() {
  local root=$1 suffix=${2:-} dir conf
  local -a sudo_=(sudo) lines
  [[ -n $root ]] && sudo_=()
  if [[ -n $suffix && ! $suffix =~ ^[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net$ ]]; then
    warn "ignoring unexpected Tailscale MagicDNS suffix"
    suffix=""
  fi
  dir="$root/etc/NetworkManager/conf.d"
  conf="$dir/90-dnscrypt-global-dns.conf"
  lines=(
    '# dotfiles (security/scripts/dnscrypt-setup.sh): every connection resolves via dnscrypt-proxy.'
    '# Remove this file and reload NetworkManager to return to per-connection DNS.'
  )
  if [[ -n $suffix ]]; then
    lines+=('[global-dns]' "searches=$suffix" '' "[global-dns-domain-$suffix]" 'servers=100.100.100.100' '')
  fi
  lines+=('[global-dns-domain-*]' 'servers=127.0.0.1,::1')
  "${sudo_[@]}" install -d -m 0755 "$dir"
  printf '%s\n' "${lines[@]}" | "${sudo_[@]}" tee "$conf" >/dev/null
  "${sudo_[@]}" chmod 0644 "$conf"
}

tailnet_suffix() {
  command -v tailscale >/dev/null 2>&1 || return 0
  tailscale status --json 2>/dev/null | jq -r '.MagicDNSSuffix // empty' 2>/dev/null || true
}

if [[ "${SKIP_NM:-0}" != 1 && "${SKIP_NM_GLOBAL:-0}" != 1 ]]; then
  say "NetworkManager global DNS → 127.0.0.1 / ::1 (covers networks joined later)"
  _ts="$(tailnet_suffix)"
  install_nm_global_dns "" "$_ts"
  if [[ -n $_ts ]]; then
    say "kept Tailscale MagicDNS for $_ts (100.100.100.100)"
  elif command -v tailscale >/dev/null 2>&1; then
    warn "Tailscale not logged in: re-run this script after 'tailscale up' to keep MagicDNS names"
  fi
  unset -v _ts
  sudo nmcli general reload dns-full 2>/dev/null \
    || sudo systemctl reload NetworkManager \
    || warn "reload NetworkManager to apply global DNS"
fi

if [[ "${SKIP_NM:-0}" != 1 ]]; then
  if [[ -f "$REPO_ROOT/security/scripts/network-dns-setup.sh" ]]; then
    say "point NetworkManager DNS at dnscrypt (127.0.0.1 / ::1)"
    PRIMARY_DNS=127.0.0.1 SECONDARY_DNS=127.0.0.1 \
      PRIMARY_DNS6=::1 SECONDARY_DNS6=::1 \
      bash "$REPO_ROOT/security/scripts/network-dns-setup.sh" \
      || warn "network-dns-setup failed — set DNS manually to 127.0.0.1"
  else
    warn "network-dns-setup.sh missing"
  fi
fi

if [[ "${SKIP_NM:-0}" == 1 || "${SKIP_NM_GLOBAL:-0}" == 1 ]] \
  && command -v tailscale >/dev/null 2>&1 && tailscale status &>/dev/null; then
  warn "Tailscale is up — MagicDNS may override NM DNS while connected"
fi
echo "  note: global DNS fails closed — if dnscrypt-proxy stops, nothing resolves (systemctl status dnscrypt-proxy)"

echo "✓ dnscrypt-proxy ready"
echo "  verify: resolvectl query example.com 2>/dev/null || dig @127.0.0.1 example.com"
echo "  or:     dig @127.0.0.1 example.com +short"
