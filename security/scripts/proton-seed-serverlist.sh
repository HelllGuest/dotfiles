#!/usr/bin/env bash
# proton-seed-serverlist.sh — fix Proton VPN "Loading app" hang on throttled networks.
#
# Problem: Proton's /vpn/v1/logicals server list is ~3 MB. On heavily throttled
# networks (e.g. UAE ISPs) the direct API stalls below the app's 60s timeout, so
# login/refresh never completes and the app is stuck on "Loading app". The tunnel
# itself is fine — only the REST fetch is blocked.
#
# Fix: download the server list out-of-band via Proton's alternative-routing
# endpoint (resolved through DoH, reached over an AWS front) and write the app's
# disk cache. The app then sees a non-expired cache, treats the session as loaded,
# and skips the blocking fetch on next start.
#
# Usage: proton-seed-serverlist.sh        # seed cache, then restart the app
#        proton-seed-serverlist.sh --kill # also kill a stuck app first
#
# Reads the active Proton session from the login keyring (secret-tool). The app
# must have logged in at least once (2FA accepted) so the session token exists.

set -euo pipefail

APP_ID="com.protonvpn.www"
CACHE_DIR="$HOME/.var/app/$APP_ID/cache/Proton/VPN"
CACHE_FILE="$CACHE_DIR/serverlist.json"
API_HOST="api.protonvpn.ch"
APPVER="linux-vpn-gui@5.2.4+x86-64"
UA="ProtonVPN/5.2.4 (Linux; org.gnome.platform/50)"

log()  { printf '[proton-seed] %s\n' "$*"; }
die()  { printf '[proton-seed] ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl       >/dev/null || die "curl not found"
command -v jq         >/dev/null || die "jq not found"
command -v secret-tool>/dev/null || die "secret-tool not found (libsecret)"
command -v base32     >/dev/null || die "base32 not found (coreutils)"

if [[ "${1:-}" == "--kill" ]]; then
  log "killing stuck app"
  flatpak kill "$API_HOST" 2>/dev/null || true
  flatpak kill "$APP_ID" 2>/dev/null || true
  pkill -f "proton.vpn.app" 2>/dev/null || true
  sleep 2
fi

# 1. Pull session token from keyring (UID + AccessToken + MaxTier).
log "reading session from keyring"
# awk's early `exit` closes the pipe (SIGPIPE on secret-tool); tolerate it under set -e.
SECRET="$(secret-tool search --all xdg:schema org.freedesktop.Secret.Generic 2>/dev/null \
  | awk '/^secret = \{/{sub(/^secret = /,""); print; exit}' || true)"
[[ -n "$SECRET" ]] || die "no Proton session in keyring — log in via the app once first"

UID_TOKEN="$(jq -r '.UID'         <<<"$SECRET")"
ACCESS="$(jq -r '.AccessToken'    <<<"$SECRET")"
TIER="$(jq -r '.vpn.vpninfo.VPN.MaxTier // 2' <<<"$SECRET")"
[[ -n "$UID_TOKEN" && "$UID_TOKEN" != null ]] || die "could not parse UID from keyring secret"
[[ -n "$ACCESS"   && "$ACCESS"   != null ]] || die "could not parse AccessToken from keyring secret"
log "session ok (tier=$TIER)"

# 2. Resolve Proton alternative-routing host via DoH.
#    Proton publishes it as a TXT record at <b32(api host)>.protonpro.xyz.
ENC="d$(printf '%s' "$API_HOST" | base32 | tr -d '=')"
log "resolving alt-route host ($ENC.protonpro.xyz)"
ALT=""
for doh in "https://dns11.quad9.net:5053/dns-query" "https://dns.google/resolve"; do
  ALT="$(curl -sS --max-time 15 "$doh?name=$ENC.protonpro.xyz&type=TXT" 2>/dev/null \
    | jq -r '.Answer[0].data // empty' 2>/dev/null | tr -d '"' || true)"
  [[ -n "$ALT" ]] && break
done
[[ -n "$ALT" ]] || die "DoH lookup failed — could not find alt-route host"
ALT_IP="$(getent ahostsv4 "$ALT" 2>/dev/null | awk 'NR==1{print $1}')"
log "alt host: $ALT ${ALT_IP:+($ALT_IP)}"

# 3. Download the server list through the alt front.
#    -k: the AWS front presents a non-matching cert (Proton pins separately),
#    so standard verification must be skipped for this request only.
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
log "downloading server list via alt route"
HTTP="$(curl -sSk --compressed --max-time 180 \
  -H "x-pm-uid: $UID_TOKEN" \
  -H "Authorization: Bearer $ACCESS" \
  -H "x-pm-appversion: $APPVER" \
  -H "User-Agent: $UA" \
  -o "$TMP" -w '%{http_code}' \
  "https://$ALT/vpn/v1/logicals?SecureCoreFilter=all&WithState=true")"
[[ "$HTTP" == 200 ]] || die "download failed (HTTP $HTTP)"
COUNT="$(jq '.LogicalServers | length' "$TMP" 2>/dev/null || echo 0)"
[[ "$COUNT" -gt 0 ]] || die "downloaded list invalid or empty"
log "got $COUNT servers"

# 4. Add the persistence keys the app expects, then write the cache.
#    ExpirationTime 3h ahead, LoadsExpirationTime 15m ahead (app defaults).
NOW="$(date +%s)"
mkdir -p "$CACHE_DIR"
jq --argjson tier "$TIER" --argjson now "$NOW" '
  . + {
    MaxTier: $tier,
    LastModifiedTime: "Thu, 01 Jan 1970 00:00:00 GMT",
    ExpirationTime: ($now + 10800),
    LoadsExpirationTime: ($now + 900)
  }' "$TMP" > "$CACHE_FILE"
chmod 644 "$CACHE_FILE"
log "wrote cache: $CACHE_FILE ($(du -h "$CACHE_FILE" | cut -f1))"

log "done — start Proton VPN; it should load without hanging"
