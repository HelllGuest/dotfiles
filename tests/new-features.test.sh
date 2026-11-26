#!/usr/bin/env bash
# new-features.test.sh — unit tests for modular pkg bundles, secrets-bootstrap,
# post-update --full, Makefile targets, and vm-stageb-run.sh overlay wiring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- 1. Modular package bundles (pkg-lists.sh) -------------------------------
mkdir -p "$T/repo/packages" "$T/repo/provision/lib" "$T/bin"
cp "$ROOT/provision/lib/pkg-lists.sh" "$ROOT/provision/lib/dmi.sh" "$T/repo/provision/lib/"
printf '%s\n' git ghidra jdk-openjdk jdk17-openjdk openssl-3 >"$T/repo/packages/pacman.txt"
printf '%s\n' forgit vscodium-bin cursor-bin antigravity-ide flutter-bin >"$T/repo/packages/aur.txt"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/pacman"
chmod +x "$T/bin/pacman"

full_pac="$(REPO_ROOT="$T/repo" DMI_SYSFS_ROOT="$T/none" PCI_SYSFS_ROOT="$T/none" PATH="$T/bin:$PATH" \
  bash -c 'source "$REPO_ROOT/provision/lib/pkg-lists.sh"; pacman_targets')"
grep -qx ghidra <<<"$full_pac" || fail "default pacman_targets must include ghidra"

min_pac="$(REPO_ROOT="$T/repo" MINIMAL_PACKAGES=1 DMI_SYSFS_ROOT="$T/none" PCI_SYSFS_ROOT="$T/none" PATH="$T/bin:$PATH" \
  bash -c 'source "$REPO_ROOT/provision/lib/pkg-lists.sh"; pacman_targets')"
grep -qx git <<<"$min_pac" || fail "MINIMAL_PACKAGES must keep git"
! grep -qxE 'ghidra|jdk-openjdk|jdk17-openjdk|openssl-3' <<<"$min_pac" \
  || fail "MINIMAL_PACKAGES must drop RE/JDK packages: $min_pac"

full_aur="$(REPO_ROOT="$T/repo" bash -c 'source "$REPO_ROOT/provision/lib/pkg-lists.sh"; aur_targets')"
grep -qx cursor-bin <<<"$full_aur" && grep -qx flutter-bin <<<"$full_aur" \
  || fail "default aur_targets must include IDEs and flutter-bin"

min_aur="$(REPO_ROOT="$T/repo" MINIMAL_PACKAGES=1 bash -c 'source "$REPO_ROOT/provision/lib/pkg-lists.sh"; aur_targets')"
[[ $min_aur == "forgit" ]] || fail "MINIMAL_PACKAGES aur_targets must leave only forgit (got: $min_aur)"

no_mobile="$(REPO_ROOT="$T/repo" SKIP_MOBILE_DEV=1 bash -c 'source "$REPO_ROOT/provision/lib/pkg-lists.sh"; aur_targets')"
grep -qx cursor-bin <<<"$no_mobile" && ! grep -qx flutter-bin <<<"$no_mobile" \
  || fail "SKIP_MOBILE_DEV=1 must drop only flutter-bin: $no_mobile"

# --- 2. secrets-bootstrap.sh roundtrip (OpenSSL AES-256-CBC PBKDF2) ----------
if command -v openssl >/dev/null 2>&1; then
  SDIR="$T/secrets"
  DOTFILES_SECRETS_DIR="$SDIR" DOTFILES_FORCE_OPENSSL=1 DOTFILES_SECRETS_PASS="unit-test-pass" \
    bash "$ROOT/security/scripts/secrets-bootstrap.sh" init >/dev/null
  [[ -f $SDIR/local.env && -f $SDIR/local.env.enc ]] || fail "secrets init must create local.env and local.env.enc"
  perm="$(stat -c '%a' "$SDIR/local.env")"
  [[ $perm == 600 ]] || fail "local.env must be mode 600 (got $perm)"
  printf 'GIT_USER_NAME="Test User"\nGIT_USER_EMAIL="test@example.com"\n' >"$SDIR/local.env"
  DOTFILES_SECRETS_DIR="$SDIR" DOTFILES_FORCE_OPENSSL=1 DOTFILES_SECRETS_PASS="unit-test-pass" \
    bash "$ROOT/security/scripts/secrets-bootstrap.sh" lock >/dev/null
  rm -f "$SDIR/local.env"
  DOTFILES_SECRETS_DIR="$SDIR" DOTFILES_FORCE_OPENSSL=1 DOTFILES_SECRETS_PASS="unit-test-pass" \
    bash "$ROOT/security/scripts/secrets-bootstrap.sh" unlock >/dev/null
  grep -qx 'GIT_USER_NAME="Test User"' "$SDIR/local.env" || fail "secrets unlock did not restore content"
  perm="$(stat -c '%a' "$SDIR/local.env")"
  [[ $perm == 600 ]] || fail "decrypted local.env must be mode 600 (got $perm)"
  DOTFILES_SECRETS_DIR="$SDIR" bash "$ROOT/security/scripts/secrets-bootstrap.sh" status >/dev/null \
    || fail "secrets status must succeed on valid 0600 file"
  chmod 644 "$SDIR/local.env"
  rc=0; DOTFILES_SECRETS_DIR="$SDIR" bash "$ROOT/security/scripts/secrets-bootstrap.sh" status >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 1 ]] || fail "secrets status must fail on loose 644 permissions (rc=$rc)"
  # --help must not leak 'set -euo pipefail'
  ! bash "$ROOT/security/scripts/secrets-bootstrap.sh" --help | grep -q 'set -euo' \
    || fail "secrets-bootstrap.sh --help must not print set -euo pipefail"
  # unlock on empty dir must fail cleanly without leaking temp files
  mkdir -p "$T/empty-sec"
  rc=0; DOTFILES_SECRETS_DIR="$T/empty-sec" bash "$ROOT/security/scripts/secrets-bootstrap.sh" unlock >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 1 ]] || fail "unlock with no archive must exit 1 (got $rc)"
  [[ -z "$(ls -A "$T/empty-sec")" ]] || fail "failed unlock must not leak temp files: $(ls -A "$T/empty-sec")"
fi

# --- 3. post-update.sh CLI + --full execution with stubs ---------------------
bash "$ROOT/provision/scripts/post-update.sh" --help | grep -q -- '--full' || fail "post-update.sh --help must document --full"
rc=0; bash "$ROOT/provision/scripts/post-update.sh" --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "post-update.sh unknown flag must exit 2 (got $rc)"

PU="$T/pu"
mkdir -p "$PU/repo/scripts" "$PU/repo/provision/scripts" "$PU/repo/ai/scripts" "$PU/bin"
cp "$ROOT/provision/scripts/post-update.sh" "$PU/repo/provision/scripts/"
for stub in paru flatpak fc-cache nvim tldr agentsync; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/pu.log"\n' "$stub" "$PU" >"$PU/bin/$stub"
done
printf '#!/bin/sh\necho "check $*" >>"%s/pu.log"\n' "$PU" >"$PU/repo/scripts/check.sh"
printf '#!/bin/sh\necho "skills $*" >>"%s/pu.log"\n' "$PU" >"$PU/repo/ai/scripts/sync-agent-skills.sh"
chmod +x "$PU/bin/"* "$PU/repo/scripts/"*.sh "$PU/repo/provision/scripts/"*.sh "$PU/repo/ai/scripts/"*.sh
PATH="$PU/bin:/usr/bin:/bin" SKIP_OPS_HYGIENE=1 bash "$PU/repo/provision/scripts/post-update.sh" --full >/dev/null 2>&1 \
  || fail "post-update.sh --full must pass with stubs: $(cat "$PU/pu.log" 2>/dev/null)"
for expect in 'paru -Syu' 'agentsync ' 'skills ' 'check --post'; do
  grep -qF "$expect" "$PU/pu.log" || fail "post-update.sh --full missing '$expect': $(cat "$PU/pu.log")"
done

# --- 4. git-setup.sh local.env sourcing (0600 only) --------------------------
grep -q 'LOCAL_ENV=.*local\.env' "$ROOT/desktop/scripts/git-setup.sh" || fail "git-setup.sh must check local.env"
GS="$T/gs"
mkdir -p "$GS/sec"
printf 'GIT_USER_NAME="FromLocalEnv"\n' >"$GS/sec/local.env"
chmod 600 "$GS/sec/local.env"
gs_blk="$(awk '/^# Optional local overrides/{f=1} f&&/^# No TTY/{exit} f' "$ROOT/desktop/scripts/git-setup.sh")"
out="$(DOTFILES_SECRETS_DIR="$GS/sec" bash -c "$gs_blk; printf '%s' \"\${GIT_USER_NAME:-}\"")"
[[ $out == "FromLocalEnv" ]] || fail "git-setup.sh must source 0600 local.env (got: $out)"
chmod 644 "$GS/sec/local.env"
out="$(DOTFILES_SECRETS_DIR="$GS/sec" bash -c "$gs_blk; printf '%s' \"\${GIT_USER_NAME:-}\"" 2>/dev/null)"
[[ -z $out ]] || fail "git-setup.sh must ignore loose 644 local.env (got: $out)"

# --- 5. Makefile, vm-stageb-run.sh overlay, and install.sh --minimal ---------
grep -q '^ci:' "$ROOT/Makefile" && grep -q '^drift:' "$ROOT/Makefile" && grep -q '^fix:' "$ROOT/Makefile" \
  || fail "Makefile must define ci, drift, and fix targets"
grep -q 'OVERLAY=\${OVERLAY:-1}' "$ROOT/provision/scripts/vm-stageb-run.sh" \
  && grep -q 'qemu-img create -q -f qcow2 -F qcow2 -b' "$ROOT/provision/scripts/vm-stageb-run.sh" \
  && grep -q 'stageb-OVMF_VARS.fd' "$ROOT/provision/scripts/vm-stageb-run.sh" \
  || fail "vm-stageb-run.sh must default OVERLAY=1 with backing snapshot + isolated OVMF_VARS"
grep -q -- '--minimal' "$ROOT/install.sh" \
  && grep -q 'Skipping ghidra-cli (MINIMAL_PACKAGES/SKIP_RE_TOOLS)' "$ROOT/install.sh" \
  || fail "install.sh must expose --minimal and skip ghidra-cli when RE tools are skipped"

# --- 6. Relative markdown links in tracked docs must resolve -----------------
python3 - "$ROOT" <<'PY' || fail "broken relative markdown link(s)"
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
link_re = re.compile(r'\[[^\]]*\]\(([^)#\s]+)')
broken = []
for f in sorted(root.rglob('*.md')):
    if any(p in f.parts for p in ('.git', 'stow', 'node_modules')):
        continue
    for i, line in enumerate(f.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
        for m in link_re.finditer(line):
            href = m.group(1)
            if href.startswith(('http://', 'https://', 'mailto:', 'file://')):
                continue
            if not (f.parent / href).resolve().exists():
                broken.append(f"{f.relative_to(root)}:{i}: {href}")
if broken:
    print("\n".join(broken), file=sys.stderr)
    sys.exit(1)
PY

echo "PASS: new-features.test.sh"
