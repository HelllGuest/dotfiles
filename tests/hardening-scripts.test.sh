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

# --- 1. minimal-stow.sh: spaces, symlinks, trailing slashes, atomic pre-flight -
PKG="$T/pkg"
TGT="$T/home"
mkdir -p "$PKG/.config/Antigravity IDE/User" "$TGT/.config/Antigravity IDE/User"
printf 'new\n' >"$PKG/.config/Antigravity IDE/User/settings.json"
printf 'a\n' >"$PKG/.config/a.txt"
ln -s a.txt "$PKG/.config/a-link.txt"

bash "$ROOT/scripts/minimal-stow.sh" "${PKG}//" "${TGT}//" >/dev/null \
  || fail "minimal-stow.sh failed on spaces + symlinks + trailing slashes"
[[ -L "$TGT/.config/Antigravity IDE/User/settings.json" ]] \
  || fail "minimal-stow.sh missed path with spaces"
[[ -L "$TGT/.config/a-link.txt" ]] \
  || fail "minimal-stow.sh missed symlink inside package"

# Symlinked package directory must still be traversed.
ln -s "$PKG" "$T/pkg-symlink"
TGT_SYM="$T/home-sym"
mkdir -p "$TGT_SYM"
bash "$ROOT/scripts/minimal-stow.sh" "$T/pkg-symlink" "$TGT_SYM" >/dev/null \
  || fail "minimal-stow.sh failed on symlinked package directory"
[[ -L "$TGT_SYM/.config/a.txt" ]] \
  || fail "minimal-stow.sh did not descend into symlinked package directory"

# Pre-flight atomicity: conflict on second file must leave zero partial links.
PKG2="$T/pkg2"
TGT2="$T/home2"
mkdir -p "$PKG2/.config" "$TGT2/.config"
printf '1\n' >"$PKG2/.config/01-first.txt"
printf '2\n' >"$PKG2/.config/02-conflict.txt"
printf 'keep-me\n' >"$TGT2/.config/02-conflict.txt"
if bash "$ROOT/scripts/minimal-stow.sh" "$PKG2" "$TGT2" >"$T/ms.out" 2>&1; then
  fail "minimal-stow.sh must refuse to overwrite an existing real file"
fi
[[ "$(cat "$TGT2/.config/02-conflict.txt")" == keep-me ]] \
  || fail "minimal-stow.sh overwrote existing real file"
[[ ! -e "$TGT2/.config/01-first.txt" && ! -L "$TGT2/.config/01-first.txt" ]] \
  || fail "minimal-stow.sh created partial link before failing on conflict"

# Refuse to traverse a symlinked parent dir under TARGET.
PKG3="$T/pkg3"
TGT3="$T/home3"
mkdir -p "$PKG3/sub" "$TGT3" "$T/escape"
printf 'x\n' >"$PKG3/sub/file.txt"
ln -s "$T/escape" "$TGT3/sub"
if bash "$ROOT/scripts/minimal-stow.sh" "$PKG3" "$TGT3" >"$T/ms3.out" 2>&1; then
  fail "minimal-stow.sh must refuse symlinked parent directory"
fi
[[ ! -e "$T/escape/file.txt" ]] \
  || fail "minimal-stow.sh followed symlinked parent directory"

# Refuse when an intermediate parent path is a regular file (zero partial links).
PKG4="$T/pkg4"
TGT4="$T/home4"
mkdir -p "$PKG4/blocked" "$TGT4"
printf 'a\n' >"$PKG4/00-ok.txt"
printf 'b\n' >"$PKG4/blocked/file.txt"
printf 'not-a-dir\n' >"$TGT4/blocked"
if bash "$ROOT/scripts/minimal-stow.sh" "$PKG4" "$TGT4" >"$T/ms4.out" 2>&1; then
  fail "minimal-stow.sh must refuse non-directory parent path"
fi
[[ ! -e "$TGT4/00-ok.txt" && ! -L "$TGT4/00-ok.txt" ]] \
  || fail "minimal-stow.sh created partial link before non-dir parent failure"

# --- 2. zram-setup.sh: installs real file, replaces symlink, backs up drift ----
ZBIN="$T/zbin"
mkdir -p "$ZBIN" "$T/etc/systemd"
printf '#!/bin/sh\nexec "$@"\n' >"$ZBIN/sudo"
printf '#!/bin/sh\nexit 0\n' >"$ZBIN/systemctl"
chmod +x "$ZBIN/"*
ZDEST="$T/etc/systemd/zram-generator.conf"

ln -s /nonexistent "$ZDEST"
PATH="$ZBIN:$PATH" ZRAM_DEST="$ZDEST" bash "$ROOT/system/scripts/zram-setup.sh" >/dev/null \
  || fail "zram-setup.sh failed replacing symlink"
[[ -f "$ZDEST" && ! -L "$ZDEST" ]] || fail "zram-setup.sh must materialize a real file"
cmp -s "$ROOT/system/zram/etc/systemd/zram-generator.conf" "$ZDEST" \
  || fail "zram-setup.sh content mismatch"

printf 'custom\n' >"$ZDEST"
PATH="$ZBIN:$PATH" ZRAM_DEST="$ZDEST" bash "$ROOT/system/scripts/zram-setup.sh" >/dev/null \
  || fail "zram-setup.sh failed on drifted file"
compgen -G "${ZDEST}.bak.*" >/dev/null || fail "zram-setup.sh must back up drifted file"
cmp -s "$ROOT/system/zram/etc/systemd/zram-generator.conf" "$ZDEST" \
  || fail "zram-setup.sh must overwrite drifted file after backup"

# --- 3. tmp-to-disk.sh: no hardcoded cryptroot, btrfs check, loud happy umount -
TD="$ROOT/system/scripts/tmp-to-disk.sh"
! grep -q '^DEV=/dev/mapper/cryptroot' "$TD" \
  || fail "tmp-to-disk.sh must derive root device from findmnt, not hardcode cryptroot"
grep -q 'findmnt -no FSTYPE /' "$TD" \
  || fail "tmp-to-disk.sh must verify root filesystem is btrfs"
grep -q 'trap cleanup_top EXIT' "$TD" \
  || fail "tmp-to-disk.sh must clean up /mnt/btrfs-top on EXIT"
grep -q '^umount "\$TOP"$' "$TD" \
  || fail "tmp-to-disk.sh must fail loudly on happy-path umount"
if bash "$TD" >"$T/td.out" 2>&1; then
  fail "tmp-to-disk.sh must refuse non-root execution"
fi

# --- 4. rebuild-v3.sh: never sources untrusted PKGBUILD, ignores comments ------
RV="$ROOT/system/scripts/rebuild-v3.sh"
! grep -q 'source \./PKGBUILD' "$RV" \
  || fail "rebuild-v3.sh must not source untrusted PKGBUILD before verification"
# Behavioral: static parser extracts keys from PKGBUILD, ignores commented-out keys, no shell exec.
_rv_dir="$T/rv"
mkdir -p "$_rv_dir"
cat >"$_rv_dir/PKGBUILD" <<EOF
pkgname=demo
validpgpkeys=(
  # FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF revoked key
  '0123456789ABCDEF0123456789ABCDEF01234567' # active key
)
\$(touch "$T/pwned")
EOF
_pyblk="$(awk '/mapfile -t pgpkeys/{f=1; next} f&&/^PY$/{exit} f' "$RV")"
_got_keys="$(cd "$_rv_dir" && python3 -c "$_pyblk")"
[[ "$_got_keys" == "0123456789ABCDEF0123456789ABCDEF01234567" ]] \
  || fail "rebuild-v3.sh static parser missed validpgpkeys or leaked comment (got: $_got_keys)"
[[ ! -e "$T/pwned" ]] || fail "rebuild-v3.sh static parser executed PKGBUILD!"

# --- 5. post-update.sh: pipefail catches nvim failure behind tail --------------
grep -q 'set -o pipefail' "$ROOT/provision/scripts/post-update.sh" \
  || fail "post-update.sh must set pipefail so nvim|tail failures are caught"

# --- 6. restore-gsettings.sh: set -euo pipefail + D-Bus guard ------------------
RG="$ROOT/desktop/scripts/restore-gsettings.sh"
grep -q 'set -euo pipefail' "$RG" || fail "restore-gsettings.sh must set -euo pipefail"
if DBUS_SESSION_BUS_ADDRESS="" XDG_RUNTIME_DIR="$T/none" bash "$RG" >"$T/rg.out" 2>&1; then
  fail "restore-gsettings.sh must refuse when no session D-Bus"
fi
grep -q 'no session D-Bus' "$T/rg.out" || fail "restore-gsettings.sh must report missing D-Bus"

# --- 7. install-photogimp.sh: SHA-256 verification before unpack ---------------
PG="$ROOT/provision/scripts/install-photogimp.sh"
grep -q 'PHOTO_SHA256="${PHOTO_SHA256:-[0-9a-f]\{64\}}"' "$PG" \
  || fail "install-photogimp.sh must pin 64-hex PHOTO_SHA256"
grep -q 'sha256sum' "$PG" || fail "install-photogimp.sh must verify SHA-256 before unzip"

# Behavioral: mismatched zip fails BEFORE unzip runs.
_pbin="$T/pbin"
_phome="$T/phome"
mkdir -p "$_pbin" "$_phome"
printf '#!/bin/sh\necho "GNU Image Manipulation Program version 3.2.0"\n' >"$_pbin/gimp"
printf '#!/bin/sh\nexit 0\n' >"$_pbin/pacman"
printf '#!/bin/sh\ntouch "%s/pg_unzipped"\nexit 0\n' "$T" >"$_pbin/unzip"
cat >"$_pbin/curl" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  [ "$1" = -o ] && { out="$2"; shift 2; continue; }
  shift
done
printf 'tampered-zip\n' >"$out"
EOF
chmod +x "$_pbin/"*
if HOME="$_phome" PATH="$_pbin:$PATH" PHOTO_CURL="$_pbin/curl" \
   bash "$PG" >"$T/pg.out" 2>&1; then
  fail "install-photogimp.sh must reject SHA-256 mismatch"
fi
grep -q 'SHA-256 mismatch' "$T/pg.out" || fail "install-photogimp.sh must report SHA-256 mismatch"
[[ ! -e "$T/pg_unzipped" ]] || fail "install-photogimp.sh ran unzip despite SHA-256 mismatch"

# --- 8. fetch-gnome-extensions.sh + install-dash2dock.sh + install-extensions --
FE="$ROOT/desktop/scripts/fetch-gnome-extensions.sh"
D2="$ROOT/desktop/scripts/install-dash2dock.sh"
IE="$ROOT/desktop/scripts/install-extensions.sh"
grep -q 'sha256sum' "$FE" || fail "fetch-gnome-extensions.sh must verify EGO zip SHA-256"
grep -q 'fetch-gnome-extensions.sh' "$D2" \
  || fail "install-dash2dock.sh must delegate zip fetch/patch to fetch-gnome-extensions.sh"
! grep -q 'patched metadata shell-version' "$D2" \
  || fail "install-dash2dock.sh must not duplicate patch_shell_51"

# Behavioral: unknown --only UUID and invalid flags fail non-zero without touching disk.
if XDG_DATA_HOME="$T/fe_unk_home" bash "$FE" --only nonexistent@example.invalid >"$T/fe_unk.out" 2>&1; then
  fail "fetch-gnome-extensions.sh must reject unknown --only UUID"
fi
grep -q 'unknown extension UUID' "$T/fe_unk.out" \
  || fail "fetch-gnome-extensions.sh must report unknown extension UUID"
[[ ! -e "$T/fe_unk_home" ]] \
  || fail "fetch-gnome-extensions.sh created EXT_ROOT on unknown --only UUID"
if bash "$FE" --badflag >"$T/fe_bad.out" 2>&1; then
  fail "fetch-gnome-extensions.sh must reject unknown flags"
fi
grep -q 'Usage:' "$T/fe_bad.out" || fail "fetch-gnome-extensions.sh must print Usage on bad flag"

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
url=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && { out="\$2"; shift 2; continue; }
  url="\$1"
  shift
done
printf '%s\n' "\$url" >"$T/d2_url"
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

# Behavioral: install-dash2dock.sh honors DASH2DOCK_URL and adds UUID to gsettings enabled-extensions.
_d2bin="$T/d2bin"
_d2home="$T/d2home"
mkdir -p "$_d2bin" "$_d2home"
cat >"$_d2bin/gsettings" <<EOF
#!/bin/sh
if [ "\$1" = get ]; then
  printf "['other@ext']\n"
elif [ "\$1" = set ]; then
  printf '%s\n' "\$4" >"$T/d2_gs"
fi
EOF
printf '#!/bin/sh\nexit 0\n' >"$_d2bin/gnome-extensions"
chmod +x "$_d2bin/"*
XDG_DATA_HOME="$_d2home" PATH="$_d2bin:$PATH" DASH2DOCK_CURL="$_fbin/curl" \
  DASH2DOCK_URL="https://example.invalid/custom-d2d.zip" DASH2DOCK_SHA256="$_good_sha" \
  bash "$D2" >/dev/null \
  || fail "install-dash2dock.sh failed with custom DASH2DOCK_URL"
[[ "$(cat "$T/d2_url")" == "https://example.invalid/custom-d2d.zip" ]] \
  || fail "install-dash2dock.sh did not honor DASH2DOCK_URL (got: $(cat "$T/d2_url"))"
grep -q "dash2dock-lite@icedman.github.com" "$T/d2_gs" \
  || fail "install-dash2dock.sh did not add UUID to gsettings enabled-extensions"
grep -q "other@ext" "$T/d2_gs" \
  || fail "install-dash2dock.sh dropped existing enabled-extensions"

# Behavioral: install-extensions.sh survives empty gsettings output (headless).
_ibin="$T/ibin"
mkdir -p "$_ibin"
printf '#!/bin/sh\nexit 0\n' >"$_ibin/gnome-extensions"
printf '#!/bin/sh\nexit 0\n' >"$_ibin/gsettings"
chmod +x "$_ibin/"*
PATH="$_ibin:$PATH" bash "$IE" >/dev/null \
  || fail "install-extensions.sh must not crash on empty gsettings output"

# --- 9. location-setup.sh + vpn-location-sync.sh trap --------------------------
LS="$ROOT/security/scripts/location-setup.sh"
bash -n "$LS" || fail "bash -n location-setup.sh"
grep -q 'sudo install -m 0755 -o root -g root "\$VPN_SYNC" /usr/local/bin/vpn-location-sync' "$LS" \
  || fail "location-setup.sh must install root-owned vpn-location-sync"
grep -q 'sudo install -m 0644 -o root -g root "\$GEO_FILE" /usr/local/share/vpn-location-sync/home.geolocation' "$LS" \
  || fail "location-setup.sh must install root-owned home.geolocation"
grep -q 'trap .*SYNC_TMPS.* EXIT' "$ROOT/security/scripts/vpn-location-sync.sh" \
  || fail "vpn-location-sync.sh must clean SYNC_TMPS on EXIT"

# --- 10. install-ponytail.sh: stages fresh clone, refuses moved tags -----------
IP="$ROOT/ai/scripts/install-ponytail.sh"
_porig="$T/pony-origin"
_ph="$T/pony-home"
_pdst="$T/pony-dst"
_pnode="$T/pony-bin"
mkdir -p "$_porig/skills/ponytail" "$_ph" "$_pnode"
printf '#!/bin/sh\nexit 0\n' >"$_pnode/node"
chmod +x "$_pnode/node"
printf '# AGENTS\n' >"$_porig/AGENTS.md"
printf '# skill\n' >"$_porig/skills/ponytail/SKILL.md"
git -C "$_porig" init -q -b main
git -C "$_porig" -c user.name=t -c user.email=t@t add .
git -C "$_porig" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -m init
_c1="$(git -C "$_porig" rev-parse HEAD)"
git -C "$_porig" tag v5.3.3
printf '# v2\n' >>"$_porig/AGENTS.md"
git -C "$_porig" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -q -am v2
_c2="$(git -C "$_porig" rev-parse HEAD)"

# 10a. Fresh clone with moved/mismatched commit refuses and leaves PONYTAIL_DIR absent.
if HOME="$_ph" PATH="$_pnode:/usr/bin:/bin" SKIP_SKILL_SYNC=1 \
   PONYTAIL_REPO="file://$_porig" PONYTAIL_TAG=v5.3.3 \
   PONYTAIL_COMMIT="0000000000000000000000000000000000000000" PONYTAIL_DIR="$_pdst" \
   bash "$IP" >"$T/ip1.out" 2>&1; then
  fail "install-ponytail.sh must refuse mismatched commit on fresh clone"
fi
grep -q 'refusing a moved tag' "$T/ip1.out" \
  || fail "install-ponytail.sh must report refusing a moved tag"
[[ ! -e "$_pdst" ]] \
  || fail "install-ponytail.sh left untrusted checkout at PONYTAIL_DIR on mismatch"

# 10b. Fresh clone with matching commit succeeds and installs skill.
HOME="$_ph" PATH="$_pnode:/usr/bin:/bin" SKIP_SKILL_SYNC=1 \
  PONYTAIL_REPO="file://$_porig" PONYTAIL_TAG=v5.3.3 \
  PONYTAIL_COMMIT="$_c1" PONYTAIL_DIR="$_pdst" \
  bash "$IP" >/dev/null \
  || fail "install-ponytail.sh failed on valid fresh clone"
[[ "$(git -C "$_pdst" rev-parse HEAD)" == "$_c1" ]] \
  || fail "install-ponytail.sh checked out wrong commit"
[[ -f "$_ph/.agents/skills/ponytail/SKILL.md" ]] \
  || fail "install-ponytail.sh did not install hub ponytail skill"

# 10c. Existing checkout refuses when upstream tag moves without touching HEAD.
git -C "$_porig" tag -f v5.3.3 "$_c2" >/dev/null
if HOME="$_ph" PATH="$_pnode:/usr/bin:/bin" SKIP_SKILL_SYNC=1 \
   PONYTAIL_REPO="file://$_porig" PONYTAIL_TAG=v5.3.3 \
   PONYTAIL_COMMIT="$_c1" PONYTAIL_DIR="$_pdst" \
   bash "$IP" >"$T/ip3.out" 2>&1; then
  fail "install-ponytail.sh must refuse moved tag on existing checkout"
fi
grep -q 'refusing a moved tag' "$T/ip3.out" \
  || fail "install-ponytail.sh must report moved tag on existing checkout"
[[ "$(git -C "$_pdst" rev-parse HEAD)" == "$_c1" ]] \
  || fail "install-ponytail.sh modified working tree on moved tag refusal"

# 10d. Existing checkout updates cleanly when PONYTAIL_COMMIT is bumped alongside tag.
HOME="$_ph" PATH="$_pnode:/usr/bin:/bin" SKIP_SKILL_SYNC=1 \
  PONYTAIL_REPO="file://$_porig" PONYTAIL_TAG=v5.3.3 \
  PONYTAIL_COMMIT="$_c2" PONYTAIL_DIR="$_pdst" \
  bash "$IP" >/dev/null \
  || fail "install-ponytail.sh failed to update existing checkout when tag+commit bumped"
[[ "$(git -C "$_pdst" rev-parse HEAD)" == "$_c2" ]] \
  || fail "install-ponytail.sh did not advance HEAD to bumped commit"

echo "PASS: hardening-scripts.test.sh"
