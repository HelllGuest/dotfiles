#!/usr/bin/env bash
# snapshot-backup.test.sh — offline unit tests for system/scripts/snapshot.sh and security/scripts/personal-backup.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$ROOT/system/scripts/snapshot.sh"
BKP="$ROOT/security/scripts/personal-backup.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x $SNAP ]] || fail "snapshot.sh must be executable"
[[ -x $BKP ]] || fail "personal-backup.sh must be executable"
bash -n "$SNAP" "$BKP" || fail "bash -n failed"

T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT

# ── 1) snapshot.sh tests (stubbed snapper/sbctl/sudo) ────────
mkdir -p "$T/bin"
S_LOG="$T/snap.log"
: >"$S_LOG"
cat >"$T/bin/sudo" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -n ]] && shift
[[ ${1:-} == true ]] && exit 0
exec "$@"
EOF
cat >"$T/bin/snapper" <<EOF
#!/usr/bin/env bash
echo "snapper \$*" >>"$S_LOG"
case " \$* " in
  *" create "*) echo "42" ;;
  *" list "*) echo "42 | 2026-11-26 | test-snap" ;;
esac
EOF
cat >"$T/bin/sbctl" <<EOF
#!/usr/bin/env bash
echo "sbctl \$*" >>"$S_LOG"
[[ \$1 == status ]] && echo "Installed: ✓ sbctl is installed"
exit 0
EOF
chmod +x "$T/bin/sudo" "$T/bin/snapper" "$T/bin/sbctl"

out="$(PATH="$T/bin:$PATH" bash "$SNAP" create "before-upgrade")" || fail "snapshot create failed"
grep -q 'snapshot #42' <<<"$out" || fail "snapshot create missing id: $out"
grep -q 'snapper -c root create' "$S_LOG" || fail "snapper create not logged"
grep -q 'sbctl verify' "$S_LOG" || fail "sbctl verify must run after snapshot create"

out="$(PATH="$T/bin:$PATH" bash "$SNAP" status)" || fail "snapshot status failed"
grep -q 'test-snap' <<<"$out" || fail "snapshot status missing list output: $out"

# rollback defaults to dry-run
: >"$S_LOG"
out="$(PATH="$T/bin:$PATH" bash "$SNAP" rollback 42)" || fail "snapshot rollback dry-run failed"
grep -q '^\[dry-run\] sudo snapper -c root rollback 42' <<<"$out" || fail "rollback must dry-run by default: $out"
[[ ! -s $S_LOG ]] || fail "rollback dry-run must not invoke snapper: $(cat "$S_LOG")"

# rollback rejects non-numeric ID
if PATH="$T/bin:$PATH" bash "$SNAP" rollback abc >/dev/null 2>&1; then
  fail "rollback must reject non-numeric ID"
fi

# rollback --apply invokes snapper rollback
out="$(PATH="$T/bin:$PATH" bash "$SNAP" rollback 42 --apply)" || fail "snapshot rollback --apply failed"
grep -q 'snapper -c root rollback 42' "$S_LOG" || fail "rollback --apply must call snapper rollback"

# ── 2) personal-backup.sh tests (real openssl round-trip) ────
H1="$T/home1"
H2="$T/home2"
mkdir -p "$H1/.ssh" "$H1/.config/dotfiles" "$H2"
printf 'ssh-ed25519 TESTKEY\n' >"$H1/.ssh/id_ed25519.pub"
printf 'GIT_USER_NAME=test\n' >"$H1/.config/dotfiles/local.env"
printf 'export FOO=bar\n' >"$H1/.zshrc.local"

ARCH="$T/out/personal.tar.gz.enc"
HOME="$H1" DOTFILES_FORCE_OPENSSL=1 DOTFILES_SECRETS_PASS="unit-test-pass-123" \
  bash "$BKP" backup "$ARCH" >/dev/null || fail "backup failed"
[[ -f $ARCH ]] || fail "backup archive missing"
[[ $(stat -c '%a' "$ARCH") == 600 ]] || fail "backup archive must be mode 0600"

vout="$(HOME="$H1" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" verify "$ARCH")" \
  || fail "verify failed"
grep -q '\.ssh/id_ed25519\.pub' <<<"$vout" || fail "verify missing .ssh file: $vout"
grep -q '\.zshrc\.local' <<<"$vout" || fail "verify missing .zshrc.local: $vout"

# Dry-run restore leaves H2 untouched
rout="$(HOME="$H2" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" restore "$ARCH" --dry-run)" \
  || fail "restore --dry-run failed"
grep -q '^\[dry-run\] would restore' <<<"$rout" || fail "restore dry-run output mismatch: $rout"
[[ ! -e "$H2/.zshrc.local" ]] || fail "restore --dry-run must not write files"

# Real restore into clean H2
HOME="$H2" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" restore "$ARCH" >/dev/null \
  || fail "restore into clean home failed"
cmp -s "$H1/.ssh/id_ed25519.pub" "$H2/.ssh/id_ed25519.pub" || fail "restored .ssh file mismatch"
cmp -s "$H1/.config/dotfiles/local.env" "$H2/.config/dotfiles/local.env" || fail "restored local.env mismatch"
[[ $(stat -c '%a' "$H2/.config/dotfiles/local.env") == 600 ]] || fail "restored local.env must be 0600"

# Second restore without --force must refuse overwrite
printf 'MODIFIED\n' >"$H2/.zshrc.local"
if HOME="$H2" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" restore "$ARCH" >/dev/null 2>&1; then
  fail "restore without --force must refuse overwriting existing files"
fi
grep -qx 'MODIFIED' "$H2/.zshrc.local" || fail "refused restore must leave existing file intact"

# Restore with --force overwrites cleanly (and enforces 700 on .config/secrets + allows foo..bar)
mkdir -p "$H1/.config/secrets"
printf 'tok=1\n' >"$H1/.config/secrets/foo..bar"
HOME="$H1" DOTFILES_FORCE_OPENSSL=1 DOTFILES_SECRETS_PASS="unit-test-pass-123" \
  bash "$BKP" backup "$ARCH" >/dev/null || fail "backup with .config/secrets/foo..bar failed"
HOME="$H2" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" restore "$ARCH" --force >/dev/null \
  || fail "restore --force failed"
cmp -s "$H1/.zshrc.local" "$H2/.zshrc.local" || fail "restore --force did not restore file"
cmp -s "$H1/.config/secrets/foo..bar" "$H2/.config/secrets/foo..bar" || fail "foo..bar filename must be allowed"
[[ $(stat -c '%a' "$H2/.config/secrets") == 700 ]] || fail "restored .config/secrets must be mode 700"

# Malicious tar with symlink escaping HOME must be rejected before extraction
EVIL_TAR="$T/evil.tar.gz"
EVIL_ENC="$T/evil.enc"
python3 - "$EVIL_TAR" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as tf:
    ti = tarfile.TarInfo(".ssh/escape")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "/etc/passwd"
    tf.addfile(ti)
PY
DOTFILES_SECRETS_PASS="unit-test-pass-123" openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -pass env:DOTFILES_SECRETS_PASS -in "$EVIL_TAR" -out "$EVIL_ENC"
if HOME="$H2" DOTFILES_SECRETS_PASS="unit-test-pass-123" bash "$BKP" restore "$EVIL_ENC" --force >/dev/null 2>&1; then
  fail "restore must reject tar symlink pointing outside HOME"
fi
[[ ! -L "$H2/.ssh/escape" ]] || fail "escaped symlink must never be extracted"

# Age backend header detection (even without .age file extension)
mkdir -p "$T/age-bin"
cat >"$T/age-bin/age" <<'STUB'
#!/usr/bin/env bash
mode=enc out="" src=""
while (($#)); do
  case $1 in
    -d) mode=dec; shift ;;
    -r|-i) shift 2 ;;
    -p) shift ;;
    -o) out=$2; shift 2 ;;
    *) src=$1; shift ;;
  esac
done
if [[ $mode == enc ]]; then
  { printf 'age-encryption.org/v1\n'; cat "$src"; } >"$out"
else
  tail -n +2 "$src" >"$out"
fi
STUB
chmod +x "$T/age-bin/age"
AGE_CUSTOM="$T/out/custom-backup.bin"
HOME="$H1" PATH="$T/age-bin:$PATH" DOTFILES_AGE_RECIPIENT="age1stub" \
  bash "$BKP" backup "$AGE_CUSTOM" >/dev/null || fail "age backup failed"
HOME="$H1" PATH="$T/age-bin:$PATH" DOTFILES_AGE_IDENTITY="$T/key" \
  bash "$BKP" verify "$AGE_CUSTOM" >/dev/null || fail "age verify by header (non-.age suffix) failed"

echo "PASS: snapshot-backup.test.sh"
