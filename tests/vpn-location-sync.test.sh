#!/usr/bin/env bash
# vpn-location-sync runs as root (NM dispatcher; pkexec without a password via
# 50-vpn-location-sync.rules). Root must never read user-writable geolocation
# files, and network data written to /etc must be validated.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
SCRIPT="$ROOT/scripts/vpn-location-sync.sh"
bash -n "$SCRIPT" || fail "bash -n vpn-location-sync.sh"

# Static checks (always run, also where user namespaces are unavailable, e.g. CI):
# the root branch may only use the root-owned installed copy.
_rootblk="$(awk '/^if \(\( EUID == 0 \)\); then$/{f=1} f&&/^else$/{exit} f' "$SCRIPT")"
[[ -n $_rootblk ]] || fail "vpn-location-sync must branch on EUID == 0"
grep -q 'INSTALLED_HOME_GEO' <<<"$_rootblk" || fail "root branch must use INSTALLED_HOME_GEO"
! grep -qE 'resolve_repo_root|REPO_ROOT|\$\{?HOME|home_dir|stow/' <<<"$_rootblk" || fail "root branch must not read user/repo paths"
grep -q '! -L "\$INSTALLED_HOME_GEO"' <<<"$_rootblk" && grep -q 'stat -c %u "\$INSTALLED_HOME_GEO"' <<<"$_rootblk" \
  || fail "root branch must reject symlinked / non-root-owned home copies"
grep -q '^INSTALLED_HOME_GEO="/usr/local/share/vpn-location-sync/home.geolocation"$' "$SCRIPT" \
  || fail "installed home copy path must be fixed (no env override)"
grep -qx 'CURL=/usr/bin/curl' "$SCRIPT" || fail "curl path must be fixed in a root script"
unset -v _rootblk

# Root path is fixed (no env override in a root script): run a copy whose two
# fixed paths point into a temp tree, as uid 0 inside a user namespace.
if ! unshare -r true 2>/dev/null; then
  echo "SKIP: vpn-location-sync root tests (unprivileged user namespaces unavailable)"
  echo "PASS: vpn-location-sync.test.sh"; exit 0
fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/share" "$T/etc" "$T/home/u/dotfiles/stow/system/etc"
sed -e "s#^INSTALLED_HOME_GEO=.*#INSTALLED_HOME_GEO=\"$T/share/home.geolocation\"#" \
    -e "s#^GEO_FILE=.*#GEO_FILE=\"$T/etc/geolocation\"#" \
    -e "s#^CURL=/usr/bin/curl\$#CURL=$T/bin/curl#" "$SCRIPT" >"$T/sync.sh"
grep -q "$T/share/home.geolocation" "$T/sync.sh" && grep -q "$T/etc/geolocation" "$T/sync.sh" \
  && grep -q "^CURL=$T/bin/curl" "$T/sync.sh" \
  || fail "test could not retarget fixed paths (variable names changed?)"
printf 'SECRET-ROOT-ONLY\n' >"$T/secret"; chmod 600 "$T/secret"
printf '# installed\n10.0\n20.0\n5\n1000\n' >"$T/share/home.geolocation"
printf '# tracked\n1.0\n2.0\n5\n1000\n' >"$T/home/u/dotfiles/stow/system/etc/geolocation"
ln -s "$T/secret" "$T/home/u/dotfiles/stow/system/etc/geolocation.local"
cat >"$T/bin/ip" <<'S'
#!/bin/sh
[ -n "$VPN_UP" ] && echo "5: proton0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420"
exit 0
S
# NM may report the VPN connected while proton0 carries no traffic (no LOWER_UP):
# the lookup must then be skipped, never sent over the real egress.
printf '#!/bin/sh\n[ -n "$NM_UP" ] && { echo "GENERAL.STATE:100 (connected)"; exit 0; }\nexit 1\n' >"$T/bin/nmcli"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/systemctl"
cat >"$T/bin/curl" <<'S'
#!/bin/sh
case " $* " in *" --interface proton0 "*) printf '%s' "$FAKE_JSON"; exit 0 ;; esac
echo "unbound lookup: $*" >>"$CURL_LOG"; exit 0
S
chmod +x "$T"/bin/*
run() { unshare -r env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home/u" PKEXEC_UID="$(id -u)" \
  USER=u DOTFILES_ROOT="$T/home/u/dotfiles" CURL_LOG="$T/curl.log" "$@" bash "$T/sync.sh" "$ACTION" 2>&1; }

! grep -q 'VPN_LOCATION_CURL\|CURL="\${' "$SCRIPT" || fail "root script must not take the curl binary from the environment"

# 1) VPN down as root: restore from the root-owned copy, never the user's symlink.
out="$(ACTION=down run)" || fail "root restore failed: $out"
grep -q SECRET "$T/etc/geolocation" && fail "root followed a user-planted symlink (file disclosure)"
grep -qx '10.0' "$T/etc/geolocation" || fail "root must restore the installed home copy: $(cat "$T/etc/geolocation")"

# 2) Installed copy that is a symlink is refused (fail closed).
mv "$T/share/home.geolocation" "$T/share/real"; ln -s "$T/secret" "$T/share/home.geolocation"
rm -f "$T/etc/geolocation"
out="$(ACTION=down run)" && fail "symlinked installed copy must be refused: $out"
[[ ! -e $T/etc/geolocation ]] || fail "nothing may be written when the installed copy is untrusted"
rm "$T/share/home.geolocation"; mv "$T/share/real" "$T/share/home.geolocation"

# 3) VPN up: coordinates validated; label stays one line; no unbound lookup.
out="$(ACTION=up run VPN_UP=1 FAKE_JSON='{"latitude":48.85,"longitude":2.35,"city":"Paris\nInjected","country_name":"FR"}')" \
  || fail "valid VPN coords rejected: $out"
grep -qx '48.85' "$T/etc/geolocation" || fail "VPN latitude not written"
[[ $(grep -c . "$T/etc/geolocation") -eq 6 ]] || fail "label must not add lines: $(cat "$T/etc/geolocation")"
out="$(ACTION=up run VPN_UP=1 FAKE_JSON='{"latitude":"1\n0.0","longitude":2}')" && fail "non-numeric latitude must be rejected: $out"
out="$(ACTION=up run VPN_UP=1 FAKE_JSON='{"latitude":95.1,"longitude":2}')" && fail "out-of-range latitude must be rejected: $out"
rm -f "$T/curl.log"
out="$(ACTION=up run NM_UP=1 FAKE_JSON='{"latitude":1,"longitude":2}' || true)"
[[ ! -e $T/curl.log ]] || fail "must not geolocate over the real egress when the tunnel is down: $(cat "$T/curl.log")"
grep -qxF '0.0' "$T/etc/geolocation" || fail "failed VPN lookup must replace home coords with neutral 0.0 placeholder: $(cat "$T/etc/geolocation")"
! grep -qxF '10.0' "$T/etc/geolocation" || fail "failed VPN lookup must not leave home coords in /etc/geolocation"

echo "PASS: vpn-location-sync.test.sh"
