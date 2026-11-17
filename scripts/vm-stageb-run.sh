#!/usr/bin/env bash
# Boot the Stage A qcow2 and run Stage B (configure.sh + install.sh) from this repo.
#
#   bash scripts/vm-stageb-run.sh
#   DISK=~/arch-vmtest/test-disk.qcow2 bash scripts/vm-stageb-run.sh
#   Parallel runs: distinct WORK=… and SSH_PORT=… (host forward to guest :22).
#
# Credentials match t14s tests/vm-bootstrap.sh defaults unless overridden.
# Do NOT use USERNAME= here — the host shell often exports USERNAME=jon.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK=${WORK:-$HOME/arch-vmtest}
DISK=${DISK:-$WORK/test-disk.qcow2}
RAM=${RAM:-4096}
SMP=${SMP:-4}
LUKS_PASS=${LUKS_PASS:-vmtest-luks-pass-change-me}
GUEST_PASS=${GUEST_PASS:-vmtest-user-pass-change-me}
GUEST_USER=${GUEST_USER:-t14svm}

say(){ printf '\e[1;34m>>\e[0m %s\n' "$*"; }
die(){ printf '\e[1;31mERR\e[0m %s\n' "$*" >&2; exit 1; }

[[ -f $DISK ]] || die "missing disk $DISK (run t14s-arch-install tests/vm-run.sh first)"
[[ -f $REPO/install.sh ]] || die "missing $REPO/install.sh"
[[ -x $REPO/scripts/vm-stageb-guest.sh ]] || die "missing vm-stageb-guest.sh"
command -v qemu-system-x86_64 >/dev/null || die "need qemu"
[[ -e /dev/kvm ]] || die "need kvm"

ovmf_code=""; ovmf_vars_src=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
  [[ -f $c ]] && { ovmf_code="$c"; ovmf_vars_src="${c/CODE/VARS}"; break; }
done
[[ -n $ovmf_code && -f $ovmf_vars_src ]] || die "need edk2-ovmf"
cp -f "$ovmf_vars_src" "$WORK/OVMF_VARS.fd"

PIPE="$WORK/stageb-serial"
rm -f "$PIPE.in" "$PIPE.out"
QEMU_LOG="$WORK/stageb-serial.log"
: >"$QEMU_LOG"
mkfifo "$PIPE.in" "$PIPE.out"
exec 3<>"$PIPE.in" 4<>"$PIPE.out"
cat <&4 | tee -a "$QEMU_LOG" >/dev/null &
TEE_PID=$!

cleanup() {
  kill "${QEMU_PID:-}" "${TEE_PID:-}" 2>/dev/null || true
  rm -f "$PIPE.in" "$PIPE.out"
}
trap cleanup EXIT

say "booting $DISK (9p:$REPO) as $GUEST_USER"
qemu-system-x86_64 \
  -enable-kvm -cpu host -m "$RAM" -smp "$SMP" -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
  -drive if=pflash,format=raw,file="$WORK/OVMF_VARS.fd" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT:-2222}-:22 \
  -device virtio-net,netdev=n0 \
  -virtfs local,path="$REPO",mount_tag=dotfiles,security_model=none,readonly=on \
  -display none \
  -serial pipe:"$PIPE" \
  -monitor none \
  -no-reboot \
  >"$WORK/stageb-qemu.out" 2>"$WORK/stageb-qemu.err" &
QEMU_PID=$!

wait_log() {
  # wait_log <seconds> <regex>
  local secs=$1 pat=$2
  for _ in $(seq 1 "$secs"); do
    if grep -a -E "$pat" "$QEMU_LOG" >/dev/null 2>&1; then return 0; fi
    kill -0 "$QEMU_PID" 2>/dev/null || return 2
    sleep 1
  done
  return 1
}

say "waiting for LUKS passphrase prompt"
if wait_log 180 'passphrase for disk|Please unlock disk|cryptsetup'; then
  say "sending LUKS passphrase (once)"
  printf '%s\r' "$LUKS_PASS" >&3
else
  die "no LUKS prompt (disk unlocked already? see $QEMU_LOG)"
fi

say "waiting for login prompt"
# Match end-of-log login line; ignore earlier noise by requiring recent growth
if ! wait_log 180 't14s-vm login:'; then
  die "never reached login prompt"
fi
# Drain a moment so getty is ready
sleep 2

say "logging in as $GUEST_USER"
{
  printf '%s\r' "$GUEST_USER"
  sleep 2
  printf '%s\r' "$GUEST_PASS"
  sleep 5
  printf 'bash --norc --noprofile\r'
  sleep 2
  printf 'export DOTFILES_USER_PASS=%q\r' "$GUEST_PASS"
  sleep 1
  printf 'export DOTFILES_SRC=/mnt/dotfiles\r'
  sleep 1
  printf 'printf %%s\\\\n %q | sudo -S mkdir -p /mnt/dotfiles\r' "$GUEST_PASS"
  sleep 2
  printf 'printf %%s\\\\n %q | sudo -S mount -t 9p -o trans=virtio,version=9p2000.L,ro dotfiles /mnt/dotfiles\r' "$GUEST_PASS"
  sleep 3
  printf 'bash /mnt/dotfiles/scripts/vm-stageb-guest.sh; echo DOTFILES_STAGEB_DONE=$?\r'
} >&3

# Pacman over nested virt is slow; allow 150 min.
say "waiting for Stage B (up to 150 min)"
deadline=$((SECONDS + 9000))
result=""
while (( SECONDS < deadline )); do
  # PASS_HEADLESS before PASS (PASS is a prefix). Allow trailing CR from serial.
  if grep -a -q 'DOTFILES_STAGEB_RESULT=PASS_HEADLESS' "$QEMU_LOG"; then result=PASS_HEADLESS; break; fi
  if grep -a -qE 'DOTFILES_STAGEB_RESULT=PASS([^_]|$)' "$QEMU_LOG"; then result=PASS; break; fi
  if grep -a -q 'DOTFILES_STAGEB_RESULT=FAIL' "$QEMU_LOG"; then result=FAIL; break; fi
  if grep -a -q 'DOTFILES_STAGEB_DONE=0' "$QEMU_LOG"; then result=PASS; break; fi
  if grep -a -qE 'DOTFILES_STAGEB_DONE=[1-9]' "$QEMU_LOG"; then result=FAIL; break; fi
  kill -0 "$QEMU_PID" 2>/dev/null || { result=DEAD; break; }
  sleep 15
done

if kill -0 "$QEMU_PID" 2>/dev/null; then
  printf 'sudo poweroff\r' >&3 || true
  sleep 2
  printf '%s\r' "$GUEST_PASS" >&3 || true
  for _ in $(seq 1 30); do
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 2
  done
  kill "$QEMU_PID" 2>/dev/null || true
fi
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=

if [[ $result == PASS || $result == PASS_HEADLESS ]]; then
  say "$result: Stage B on VM"
  grep -a -E 'DOTFILES_STAGEB_|configure\.sh|firewalld|default.zone|install\.sh exit|✓ configure|Finished' "$QEMU_LOG" | tail -50
  exit 0
fi
say "FAIL: result=${result:-TIMEOUT}"
tail -c 40000 "$QEMU_LOG" | tr -cd '\11\12\15\40-\176' | tail -n 120
exit 1
