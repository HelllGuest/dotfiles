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
grep -q "listen_addresses = \\['127.0.0.1:53', '\\[::1\\]:53'\\]" \
  "$ROOT/scripts/dnscrypt-setup.sh" \
  || fail "dnscrypt-setup must listen on 127.0.0.1 and ::1"
grep -q 'PRIMARY_DNS6=::1' "$ROOT/scripts/dnscrypt-setup.sh" \
  || fail "dnscrypt-setup must point NM ipv6 at ::1"

echo "PASS: privacy-ops.test.sh"
