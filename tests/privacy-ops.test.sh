#!/usr/bin/env bash
# Privacy / ops hygiene packages + setup scripts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for pkg in pacman-contrib mat2 perl-image-exiftool bleachbit usbguard dnscrypt-proxy; do
  grep -qx "$pkg" "$ROOT/packages/pacman.txt" \
    || fail "pacman.txt must include $pkg"
done

for f in ops-hygiene.sh usbguard-setup.sh dnscrypt-setup.sh network-dns-setup.sh; do
  [[ -f $ROOT/scripts/$f ]] || fail "missing scripts/$f"
  bash -n "$ROOT/scripts/$f" || fail "bash -n scripts/$f"
done

grep -q 'ops-hygiene.sh' "$ROOT/install.sh" \
  || fail "install.sh must call ops-hygiene.sh"
grep -q 'ops-hygiene.sh' "$ROOT/scripts/post-update.sh" \
  || fail "post-update.sh must call ops-hygiene.sh"
grep -q 'PRIMARY_DNS6' "$ROOT/scripts/network-dns-setup.sh" \
  || fail "network-dns-setup.sh must honor PRIMARY_DNS6"
grep -q 'sudo usbguard generate-policy' "$ROOT/scripts/usbguard-setup.sh" \
  || fail "usbguard-setup must sudo generate-policy before enable"
grep -q 'list-devices && sudo usbguard allow-device' "$ROOT/scripts/usbguard-setup.sh" \
  || fail "usbguard hint: list-devices then allow-device -p (not list-devices -p)"
! grep -q 'list-devices -p' "$ROOT/scripts/usbguard-setup.sh" \
  || fail "usbguard list-devices does not take -p"
grep -q "listen_addresses = \\['127.0.0.1:53', '\\[::1\\]:53'\\]" \
  "$ROOT/scripts/dnscrypt-setup.sh" \
  || fail "dnscrypt-setup must listen on 127.0.0.1 and ::1"
grep -q 'PRIMARY_DNS6=::1' "$ROOT/scripts/dnscrypt-setup.sh" \
  || fail "dnscrypt-setup must point NM ipv6 at ::1"

# dnscrypt: NM global DNS so networks joined later cannot fall back to DHCP DNS.
_fn="$(awk '/^install_nm_global_dns\(\) \{/{f=1} f; f&&/^}$/{exit}' "$ROOT/scripts/dnscrypt-setup.sh")"
[[ -n $_fn ]] || fail "dnscrypt-setup must define install_nm_global_dns"
_r="$(mktemp -d)"
bash -c "$_fn"$'\n''install_nm_global_dns "$1"' _ "$_r" || fail "install_nm_global_dns failed"
_c="$_r/etc/NetworkManager/conf.d/90-dnscrypt-global-dns.conf"
grep -qx '\[global-dns-domain-\*\]' "$_c" && grep -qx 'servers=127.0.0.1,::1' "$_c" \
  || fail "NM global DNS must point every connection at dnscrypt: $(cat "$_c" 2>/dev/null)"
[[ $(stat -c %a "$_c") == 644 ]] || fail "NM global DNS conf must be 0644"
rm -rf -- "$_r"
grep -q 'install_nm_global_dns "" "\$_ts"' "$ROOT/scripts/dnscrypt-setup.sh" || fail "dnscrypt-setup must install NM global DNS"
# Tailscale: the MagicDNS suffix keeps resolving via 100.100.100.100; a bogus
# suffix (config injection attempt) is ignored.
_nm() { bash -c 'warn(){ echo "WARN $*" >&2; }; '"$_fn"$'\n''install_nm_global_dns "$1" "$2"' _ "$1" "$2" 2>/dev/null; }
_r="$(mktemp -d)"; _nm "$_r" tail1234.ts.net
_c="$_r/etc/NetworkManager/conf.d/90-dnscrypt-global-dns.conf"
grep -qx '\[global-dns-domain-tail1234.ts.net\]' "$_c" && grep -qx 'servers=100.100.100.100' "$_c" \
  && grep -qx 'searches=tail1234.ts.net' "$_c" && grep -qx 'servers=127.0.0.1,::1' "$_c" \
  || fail "tailnet suffix must keep MagicDNS: $(cat "$_c")"
if command -v NetworkManager >/dev/null 2>&1; then
  : >"$_r/main.conf"
  NetworkManager --print-config --config="$_r/main.conf" --config-dir="$_r/etc/NetworkManager/conf.d" 2>&1 \
    | grep -qx '\[global-dns-domain-tail1234.ts.net\]' || fail "NetworkManager must parse the global DNS conf"
fi
_nm "$_r" $'evil.com\n[main]\ndns=none'
! grep -qE 'evil|dns=none|100\.100' "$_c" || fail "unexpected tailnet suffix must be ignored: $(cat "$_c")"
rm -rf -- "$_r"; unset -f _nm
unset -v _fn _r _c

# GNOME: no notification content on the lock screen; no media autorun.
_uc="$ROOT/gnome/dconf/user.conf"
python3 - "$_uc" <<'PY' || fail "GNOME lock-screen notifications / autorun hardening missing"
import configparser, sys
c = configparser.ConfigParser(strict=False, interpolation=None); c.read(sys.argv[1])
ok = c.get("org/gnome/desktop/notifications", "show-in-lock-screen", fallback="") == "false" \
     and c.get("org/gnome/desktop/media-handling", "autorun-never", fallback="") == "true"
sys.exit(0 if ok else 1)
PY
# bash: secrets env made owner-only before it is sourced (parity with zsh).
awk '/chmod 600 ~\/.config\/secrets\/env/{c=NR} /source ~\/.config\/secrets\/env/{s=NR} END{exit !(c && s && c < s)}' \
  "$ROOT/stow/bash/.bashrc" || fail ".bashrc must chmod 600 secrets env before sourcing it"
unset -v _uc

# backup-gsettings: a dconf snapshot must not drop the enforced privacy keys.
_T="$(mktemp -d)"; mkdir -p "$_T/bin"
cat >"$_T/bin/dconf" <<'STUB'
#!/bin/sh
cat <<'DUMP'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/a.png'

[org/gnome/desktop/privacy]
remember-recent-files=true

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0]
binding='<Super>Return'
command='kitty -e sh -c "a:b; c=d"'
DUMP
STUB
chmod +x "$_T/bin/dconf"
PATH="$_T/bin:$PATH" GSETTINGS_OUT="$_T/user.conf" bash "$ROOT/scripts/backup-gsettings.sh" >/dev/null \
  || fail "backup-gsettings failed"
for _kv in show-in-lock-screen=false autorun-never=true remember-recent-files=false \
    report-technical-problems=false send-software-usage-stats=false; do
  grep -qx "$_kv" "$_T/user.conf" || fail "backup-gsettings must keep enforced $_kv: $(cat "$_T/user.conf")"
done
grep -qxF "picture-uri='file:///usr/share/backgrounds/a.png'" "$_T/user.conf" \
  && grep -qxF "command='kitty -e sh -c \"a:b; c=d\"'" "$_T/user.conf" \
  && grep -qxF "binding='<Super>Return'" "$_T/user.conf" \
  || fail "backup-gsettings must preserve other keys verbatim: $(cat "$_T/user.conf")"
rm -rf -- "$_T"; unset -v _T _kv

echo "PASS: privacy-ops.test.sh"
