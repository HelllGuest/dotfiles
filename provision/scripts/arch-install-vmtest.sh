#!/usr/bin/env bash
# arch-install-vmtest.sh — dry-run Stage A in a UEFI qemu VM (no real disks).
#
# Serves local scripts/ and in-repo stage-a/ (or sibling checkout) so
# the guest rehearses YOUR tree, not GitHub main.
#
#   ~/dotfiles/provision/scripts/arch-install-vmtest.sh
#   INSTALLER=arch-install-t14s.sh ~/dotfiles/provision/scripts/arch-install-vmtest.sh
#
# Env: INSTALLER, WORK, DISK_SIZE, RAM, PORT (scripts, default 8000),
#      T14S_PORT (canonical tree, default PORT+1), ISO, FRESH=1,
#      STAGE_A_LOCAL / T14S_LOCAL (override path to stage-a/)
set -euo pipefail
say(){ printf '\e[1;34m>>\e[0m %s\n' "$*"; }
die(){ printf '\e[1;31mERR\e[0m %s\n' "$*" >&2; exit 1; }

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$DOTFILES_ROOT/scripts"
INSTALLER=${INSTALLER:-arch-install.sh}
[[ $INSTALLER == */* || $INSTALLER == *..* ]] && die "INSTALLER must be a basename under scripts/"
[[ -f "$SCRIPTS_DIR/$INSTALLER" ]] || die "$INSTALLER not found in $SCRIPTS_DIR"
WORK=${WORK:-$HOME/arch-vmtest}
DISK="$WORK/test-disk.qcow2"
DISK_SIZE=${DISK_SIZE:-80G}
RAM=${RAM:-4096}
PORT=${PORT:-8000}
T14S_PORT=${T14S_PORT:-$((PORT + 1))}
ISO=${ISO:-}
T14S_DIR="${STAGE_A_LOCAL:-${T14S_LOCAL:-$DOTFILES_ROOT/stage-a}}"
[[ -d $T14S_DIR ]] || T14S_DIR="$DOTFILES_ROOT/../stage-a"
[[ -d $T14S_DIR ]] || T14S_DIR="$DOTFILES_ROOT/../t14s-arch-install"
[[ -d $T14S_DIR ]] && T14S_DIR="$(cd "$T14S_DIR" && pwd)" || T14S_DIR=""

# 1. dependencies (qemu + OVMF firmware)
# shellcheck source=../lib/vm-common.sh
source "$DOTFILES_ROOT/provision/lib/vm-common.sh"
need=()
command -v qemu-system-x86_64 >/dev/null || need+=(qemu-full)
QEMU_IMG=/usr/bin/qemu-img; [[ -x $QEMU_IMG ]] || QEMU_IMG=qemu-img
vm_find_ovmf || need+=(edk2-ovmf)
if (( ${#need[@]} )); then die "install first:  sudo pacman -S --needed ${need[*]}"; fi
ovmf_code="$OVMF_CODE"; ovmf_vars_src="$OVMF_VARS_SRC"
say "qemu + OVMF found ($ovmf_code)"

mkdir -p "$WORK"

# 2. Arch ISO
if [[ -z $ISO ]]; then
  ISO=$(ls -1t "$WORK"/archlinux-*.iso "$HOME"/Downloads/archlinux-*.iso 2>/dev/null | head -1 || true)
fi
if [[ -z $ISO || ! -f $ISO ]]; then
  ISO="$WORK/archlinux-x86_64.iso"
  say "downloading latest Arch ISO (~1.2G) -> $ISO"
  ISO_URL=https://geo.mirror.pkgbuild.com/iso/latest
  # Verify before booting: a truncated/tampered ISO must never reach the VM.
  want=$(curl -fsSL "$ISO_URL/sha256sums.txt" | awk '$2 == "archlinux-x86_64.iso" {print $1}')
  [[ $want =~ ^[0-9a-f]{64}$ ]] || die "could not read ISO SHA-256 from $ISO_URL/sha256sums.txt"
  curl -fSL --retry 3 -o "$ISO.partial" "$ISO_URL/archlinux-x86_64.iso"
  got=$(sha256sum "$ISO.partial" | awk '{print $1}')
  if [[ $got != "$want" ]]; then
    rm -f -- "$ISO.partial"
    die "ISO SHA-256 mismatch (got $got, want $want)"
  fi
  mv -f "$ISO.partial" "$ISO"
fi
say "ISO: $ISO"

# 3. virtual disk + writable OVMF vars copy
[[ ${FRESH:-0} == 1 ]] && rm -f "$DISK"
[[ -f $DISK ]] || { say "creating blank ${DISK_SIZE} disk"; "$QEMU_IMG" create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null; }
cp -f "$ovmf_vars_src" "$WORK/OVMF_VARS.fd"

# 4. serve local trees (guest → 10.0.2.2)
#    PORT     → repo root  (scripts/arch-install*.sh + provision/lib/stage-a-handoff.sh)
#    T14S_PORT → stage-a/ (install.sh + lib/, whole tree) when present
( cd "$DOTFILES_ROOT" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) &>/dev/null &
HTTP_PID=$!
T14S_HTTP_PID=""
if [[ -n $T14S_DIR && -f $T14S_DIR/install.sh ]]; then
  ( cd "$T14S_DIR" && exec python3 -m http.server "$T14S_PORT" --bind 127.0.0.1 ) &>/dev/null &
  T14S_HTTP_PID=$!
  say "serving local Stage A from $T14S_DIR on :$T14S_PORT"
else
  say "no local stage-a/ — guest resolves GitHub main→SHA (or STAGE_A_REF / T14S_REF)"
fi
trap 'kill "$HTTP_PID" ${T14S_HTTP_PID:-} 2>/dev/null || true' EXIT
sleep 1

T14S_ENV=""
if [[ -n $T14S_HTTP_PID ]]; then
  T14S_ENV="T14S_BASE_URL=http://10.0.2.2:${T14S_PORT} T14S_INSTALL_URL=http://10.0.2.2:${T14S_PORT}/install.sh"
fi

cat <<EOF

  ┌─ VM smoke test (local trees) ───────────────────────────────┐
   Serves dotfiles repo at http://10.0.2.2:${PORT}/
   $([ -n "$T14S_HTTP_PID" ] && echo "Serves stage-a/ at http://10.0.2.2:${T14S_PORT}/" || echo "No local stage-a/ — pinned GitHub fetch")
   Active INSTALLER=${INSTALLER}

   Inside the Arch ISO root shell:

     STAGE_A_HANDOFF_URL=http://10.0.2.2:${PORT}/provision/lib/stage-a-handoff.sh \\
     ${T14S_ENV} \\
     bash <(curl -fsSL http://10.0.2.2:${PORT}/scripts/${INSTALLER})

   • Do NOT rely on DOTFILES_RAW here (STAGE_A_HANDOFF_URL pins the local handoff)
   • Wrappers set HW_PROFILE (t14s / p15) or DMI-detect (arch-install.sh)
   • Disk: AUTO · /dev/vda only · FRESH=1 to wipe qcow2
   • Virtual disk: $DISK
  └─────────────────────────────────────────────────────────────┘

EOF

# 5. launch UEFI VM
say "launching qemu (close window to stop)"
kvm=(); [[ -e /dev/kvm ]] && kvm=(-enable-kvm -cpu host)
qemu-system-x86_64 \
  "${kvm[@]}" -m "$RAM" -smp 4 -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
  -drive if=pflash,format=raw,file="$WORK/OVMF_VARS.fd" \
  -drive file="$DISK",if=virtio,format=qcow2 \
  -cdrom "$ISO" -boot menu=on \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=n0 \
  -vga virtio -display gtk

say "VM exited. Disk kept at $DISK (FRESH=1 to wipe next run)."
