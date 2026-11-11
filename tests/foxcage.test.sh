#!/usr/bin/env bash
# install-foxcage.sh: pins wired, SHA-256 enforced, layout + --install, no network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/install-foxcage.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x $SCRIPT ]] || fail "not executable: $SCRIPT"
bash -n "$SCRIPT" || fail "bash -n failed"
grep -q 'FOXCAGE_REF:-349056e5afd0172330d93ea55413dcdd8c763fd0' "$SCRIPT" || fail "commit pin missing"
grep -q 'f9a87fc60e3c3b3b740ec0dcf64ac1c72287d65cc63269822dd805fb98d0a8fe' "$SCRIPT" \
  || fail "script SHA-256 pin missing"
grep -qx 'xdg-dbus-proxy' "$ROOT/packages/pacman.txt" || fail "pacman.txt missing xdg-dbus-proxy"
grep -qx 'passt' "$ROOT/packages/pacman.txt" || fail "pacman.txt missing passt"
grep -q 'scripts/install-foxcage.sh' "$ROOT/install.sh" || fail "install.sh does not run install-foxcage.sh"
grep -q 'SKIP_FOXCAGE:-0' "$ROOT/install.sh" || fail "install.sh must honor SKIP_FOXCAGE"
grep -B3 'bash scripts/install-foxcage.sh' "$ROOT/install.sh" | grep -q 'command -v podman' \
  || fail "install.sh must skip foxcage without podman"
grep -q 'command -v foxcage' "$ROOT/scripts/check.sh" || fail "check.sh must report foxcage"
# Pins in this test must track the script (both are bumped together on update).
grep -q '0df41fe24a1ebc1de3bc0a0714b24bfb19f75a49b05ebb719cd96ff9f4f3bf5d' "$SCRIPT" \
  || fail "icon SHA-256 pin missing"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fixture" "$TMP/stub"
# Fake foxcage: records its --install call and the path it ran from;
# FOXCAGE_FAIL=1 makes --install fail like a real error would.
printf '#!/bin/sh\necho "$0 $*" >>"$HOME/install.log"\n[ "${FOXCAGE_FAIL:-0}" = 1 ] && exit 3\nexit 0\n' \
  >"$TMP/fixture/foxcage"
printf 'png' >"$TMP/fixture/foxcage.png"
# Stub curl: serve fixtures by basename, record URLs (no network).
cat >"$TMP/stub/curl" <<EOF
#!/usr/bin/env bash
out=; url=
while ((\$#)); do case \$1 in -o) out=\$2; shift 2 ;; -*) shift ;; *) url=\$1; shift ;; esac; done
echo "\$url" >>"$TMP/urls"
cp "$TMP/fixture/\${url##*/}" "\$out"
EOF
chmod +x "$TMP/stub/curl"
sha() { sha256sum "$1" | awk '{print $1}'; }

run() { # extra env...
  env -i PATH="$TMP/stub:$PATH" HOME="$TMP/home" \
    FOXCAGE_SHA256="$(sha "$TMP/fixture/foxcage")" \
    FOXCAGE_ICON_SHA256="$(sha "$TMP/fixture/foxcage.png")" "$@" \
    bash "$SCRIPT" >"$TMP/out" 2>&1
}

run || { cat "$TMP/out" >&2; fail "install with matching digests failed"; }
H="$TMP/home"
[[ -x $H/.local/share/foxcage/foxcage ]] || fail "script not installed executable"
[[ -f $H/.local/share/foxcage/foxcage.png ]] || fail "icon not next to script (would fetch unpinned icon)"
[[ $(readlink "$H/.local/bin/foxcage") == "$H/.local/share/foxcage/foxcage" ]] || fail "bin symlink wrong"
grep -qx "$H/.local/share/foxcage/foxcage --install" "$H/install.log" || fail "--install not run from install dir"
! grep -v 'gitlab.com/grepular/foxcage/-/raw/349056e5afd0172330d93ea55413dcdd8c763fd0/' "$TMP/urls" \
  || fail "fetched something other than the pinned raw URLs"

run FOXCAGE_SHA256=0000 && fail "digest mismatch must abort"
grep -q 'SHA-256 mismatch' "$TMP/out" || fail "mismatch must be reported"

run FOXCAGE_FAIL=1 && fail "a failing foxcage --install must fail the installer"
grep -q 'done — run: foxcage' "$TMP/out" && fail "installer reported success after --install failed"

run FOXCAGE_REF=main && fail "non-SHA FOXCAGE_REF must abort"
grep -q '40-char commit SHA' "$TMP/out" || fail "bad ref must be reported"

echo "PASS: foxcage tests"
