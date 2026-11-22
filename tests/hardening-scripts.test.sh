#!/usr/bin/env bash
# Hardening & safety tests for previously untested scripts:
# minimal-stow.sh, zram-setup.sh, tmp-to-disk.sh, rebuild-v3.sh, post-update.sh,
# restore-gsettings.sh, install-photogimp.sh, fetch-gnome-extensions.sh,
# install-dash2dock.sh, install-extensions.sh, location-setup.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- 1. minimal-stow.sh: spaces, symlinks, refuses to clobber real files -------
PKG="$T/pkg"
TGT="$T/home"
mkdir -p "$PKG/.config/Antigravity IDE/User" "$TGT/.config/Antigravity IDE/User"
printf 'new\n' >"$PKG/.config/Antigravity IDE/User/settings.json"
printf 'a\n' >"$PKG/.config/a.txt"
ln -s a.txt "$PKG/.config/a-link.txt"

bash "$ROOT/scripts/minimal-stow.sh" "$PKG" "$TGT" >/dev/null \
  || fail "minimal-stow.sh failed on spaces + symlinks"
[[ -L "$TGT/.config/Antigravity IDE/User/settings.json" ]] \
  || fail "minimal-stow.sh missed path with spaces"
[[ -L "$TGT/.config/a-link.txt" ]] \
  || fail "minimal-stow.sh missed symlink inside package"

# Existing real file must not be overwritten.
rm -f "$TGT/.config/a.txt"
printf 'keep-me\n' >"$TGT/.config/a.txt"
if bash "$ROOT/scripts/minimal-stow.sh" "$PKG" "$TGT" >"$T/ms.out" 2>&1; then
  fail "minimal-stow.sh must refuse to overwrite an existing real file"
fi
[[ "$(cat "$TGT/.config/a.txt")" == keep-me ]] \
  || fail "minimal-stow.sh overwrote existing real file"

# --- 2. zram-setup.sh: installs real file, replaces symlink, backs up drift ----
ZBIN="$T/zbin"
mkdir -p "$ZBIN" "$T/etc/systemd"
printf '#!/bin/sh\nexec "$@"\n' >"$ZBIN/sudo"
printf '#!/bin/sh\nexit 0\n' >"$ZBIN/systemctl"
chmod +x "$ZBIN/"*
ZDEST="$T/etc/systemd/zram-generator.conf"

ln -s /nonexistent "$ZDEST"
PATH="$ZBIN:$PATH" ZRAM_DEST="$ZDEST" bash "$ROOT/scripts/zram-setup.sh" >/dev/null \
  || fail "zram-setup.sh failed replacing symlink"
[[ -f "$ZDEST" && ! -L "$ZDEST" ]] || fail "zram-setup.sh must materialize a real file"
cmp -s "$ROOT/stow/zram/etc/systemd/zram-generator.conf" "$ZDEST" \
  || fail "zram-setup.sh content mismatch"

printf 'custom\n' >"$ZDEST"
PATH="$ZBIN:$PATH" ZRAM_DEST="$ZDEST" bash "$ROOT/scripts/zram-setup.sh" >/dev/null \
  || fail "zram-setup.sh failed on drifted file"
compgen -G "${ZDEST}.bak.*" >/dev/null || fail "zram-setup.sh must back up drifted file"
cmp -s "$ROOT/stow/zram/etc/systemd/zram-generator.conf" "$ZDEST" \
  || fail "zram-setup.sh must overwrite drifted file after backup"

# --- 3. tmp-to-disk.sh: no hardcoded cryptroot, btrfs check, EXIT unmount trap --
TD="$ROOT/scripts/tmp-to-disk.sh"
! grep -q '^DEV=/dev/mapper/cryptroot' "$TD" \
  || fail "tmp-to-disk.sh must derive root device from findmnt, not hardcode cryptroot"
grep -q 'findmnt -no FSTYPE /' "$TD" \
  || fail "tmp-to-disk.sh must verify root filesystem is btrfs"
grep -q 'trap cleanup_top EXIT' "$TD" \
  || fail "tmp-to-disk.sh must clean up /mnt/btrfs-top on EXIT"
if bash "$TD" >"$T/td.out" 2>&1; then
  fail "tmp-to-disk.sh must refuse non-root execution"
fi

# --- 4. rebuild-v3.sh: never sources untrusted PKGBUILD ------------------------
RV="$ROOT/scripts/rebuild-v3.sh"
! grep -q 'source \./PKGBUILD' "$RV" \
  || fail "rebuild-v3.sh must not source untrusted PKGBUILD before verification"
# Behavioral: static parser extracts keys from PKGBUILD without running shell commands.
_rv_dir="$T/rv"
mkdir -p "$_rv_dir"
cat >"$_rv_dir/PKGBUILD" <<EOF
pkgname=demo
validpgpkeys=(
  '0123456789ABCDEF0123456789ABCDEF01234567'
)
\$(touch "$T/pwned")
EOF
_pyblk="$(awk '/mapfile -t pgpkeys/{f=1; next} f&&/^PY$/{exit} f' "$RV")"
_got_keys="$(cd "$_rv_dir" && python3 -c "$_pyblk")"
[[ "$_got_keys" == "0123456789ABCDEF0123456789ABCDEF01234567" ]] \
  || fail "rebuild-v3.sh static parser missed validpgpkeys (got: $_got_keys)"
[[ ! -e "$T/pwned" ]] || fail "rebuild-v3.sh static parser executed PKGBUILD!"

# --- 5. post-update.sh: pipefail catches nvim failure behind tail --------------
grep -q 'set -o pipefail' "$ROOT/scripts/post-update.sh" \
  || fail "post-update.sh must set pipefail so nvim|tail failures are caught"

# --- 6. restore-gsettings.sh: set -euo pipefail + D-Bus guard ------------------
RG="$ROOT/scripts/restore-gsettings.sh"
grep -q 'set -euo pipefail' "$RG" || fail "restore-gsettings.sh must set -euo pipefail"
if DBUS_SESSION_BUS_ADDRESS="" XDG_RUNTIME_DIR="$T/none" bash "$RG" >"$T/rg.out" 2>&1; then
  fail "restore-gsettings.sh must refuse when no session D-Bus"
fi
grep -q 'no session D-Bus' "$T/rg.out" || fail "restore-gsettings.sh must report missing D-Bus"

# --- 7. install-photogimp.sh: SHA-256 verification before unpack ---------------
PG="$ROOT/scripts/install-photogimp.sh"
grep -q 'PHOTO_SHA256="${PHOTO_SHA256:-[0-9a-f]\{64\}}"' "$PG" \
  || fail "install-photogimp.sh must pin 64-hex PHOTO_SHA256"
grep -q 'sha256sum' "$PG" || fail "install-photogimp.sh must verify SHA-256 before unzip"

# --- 8. fetch-gnome-extensions.sh + install-dash2dock.sh + install-extensions --
FE="$ROOT/scripts/fetch-gnome-extensions.sh"
D2="$ROOT/scripts/install-dash2dock.sh"
IE="$ROOT/scripts/install-extensions.sh"
grep -q 'sha256sum' "$FE" || fail "fetch-gnome-extensions.sh must verify EGO zip SHA-256"
grep -q 'fetch-gnome-extensions.sh' "$D2" \
  || fail "install-dash2dock.sh must delegate zip fetch/patch to fetch-gnome-extensions.sh"
! grep -q 'patched metadata shell-version' "$D2" \
  || fail "install-dash2dock.sh must not duplicate patch_shell_51"

# Behavioral: fetch-gnome-extensions --only rejects bad SHA-256 and accepts valid zip.
_fbin="$T/fbin"
_fhome="$T/fhome"
mkdir -p "$_fbin" "$_fhome" "$T/zsrc"
printf '{"uuid":"dash2dock-lite@icedman.github.com","shell-version":["50"]}\n' >"$T/zsrc/metadata.json"
(cd "$T/zsrc" && python3 -c 'import zipfile; z=zipfile.ZipFile("../good.zip","w"); z.write("metadata.json"); z.close()')
_good_sha="$(sha256sum "$T/good.zip" | awk '{print $1}')"
cat >"$_fbin/curl" <<EOF
#!/bin/sh
out=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && { out="\$2"; shift 2; continue; }
  shift
done
cp "$T/good.zip" "\$out"
EOF
chmod +x "$_fbin/curl"
if XDG_DATA_HOME="$_fhome" GNOME_EXT_CURL="$_fbin/curl" \
   bash "$FE" --only dash2dock-lite@icedman.github.com >"$T/fe.out" 2>&1; then
  fail "fetch-gnome-extensions.sh must reject SHA-256 mismatch"
fi
grep -q 'SHA-256 mismatch' "$T/fe.out" || fail "fetch-gnome-extensions must report SHA-256 mismatch"
XDG_DATA_HOME="$_fhome" GNOME_EXT_CURL="$_fbin/curl" DASH2DOCK_SHA256="$_good_sha" \
  bash "$FE" --only dash2dock-lite@icedman.github.com >/dev/null \
  || fail "fetch-gnome-extensions.sh failed with matching SHA-256"
grep -q '"51"' "$_fhome/gnome-shell/extensions/dash2dock-lite@icedman.github.com/metadata.json" \
  || fail "fetch-gnome-extensions.sh --only dash2dock must patch shell-version 51"

# Behavioral: install-extensions.sh survives empty gsettings output (headless).
_ibin="$T/ibin"
mkdir -p "$_ibin"
printf '#!/bin/sh\nexit 0\n' >"$_ibin/gnome-extensions"
printf '#!/bin/sh\nexit 0\n' >"$_ibin/gsettings"
chmod +x "$_ibin/"*
PATH="$_ibin:$PATH" bash "$IE" >/dev/null \
  || fail "install-extensions.sh must not crash on empty gsettings output"

# --- 9. location-setup.sh: installs trusted root-owned copies ------------------
LS="$ROOT/scripts/location-setup.sh"
bash -n "$LS" || fail "bash -n location-setup.sh"
grep -q 'sudo install -m 0755 -o root -g root "\$VPN_SYNC" /usr/local/bin/vpn-location-sync' "$LS" \
  || fail "location-setup.sh must install root-owned vpn-location-sync"
grep -q 'sudo install -m 0644 -o root -g root "\$GEO_FILE" /usr/local/share/vpn-location-sync/home.geolocation' "$LS" \
  || fail "location-setup.sh must install root-owned home.geolocation"

echo "PASS: hardening-scripts.test.sh"
