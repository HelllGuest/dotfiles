#!/usr/bin/env bash
# arch-install-vmtest.sh — dry-run an Arch installer in a UEFI qemu VM (no real disks).
#
# Boots the Arch ISO in an OVMF/UEFI VM with a blank virtual disk, and serves the
# local installer script over loopback so you can run it end-to-end against
# /dev/vda only. Nothing on your physical machine is touched.
#
#   ~/dotfiles/scripts/arch-install-vmtest.sh
#   INSTALLER=arch-install-t14s.sh ~/dotfiles/scripts/arch-install-vmtest.sh
#   # inside the VM's ISO shell:
#   bash <(curl -fsSL http://10.0.2.2:8000/arch-install.sh)
#   # or for T14s AMD script (confirm past DMI warn in the VM):
#   bash <(curl -fsSL http://10.0.2.2:8000/arch-install-t14s.sh)
#
# Env overrides: INSTALLER (arch-install.sh|arch-install-t14s.sh), WORK, DISK_SIZE
#   (80G: full ./install.sh needs ~40G), RAM (4096), PORT (8000), ISO, FRESH=1
set -euo pipefail
say(){ printf '\e[1;34m>>\e[0m %s\n' "$*"; }
die(){ printf '\e[1;31mERR\e[0m %s\n' "$*" >&2; exit 1; }

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER=${INSTALLER:-arch-install.sh}
[[ $INSTALLER == */* || $INSTALLER == *..* ]] && die "INSTALLER must be a basename under scripts/"
[[ -f "$SCRIPTS_DIR/$INSTALLER" ]] || die "$INSTALLER not found next to this script"
WORK=${WORK:-$HOME/arch-vmtest}
DISK="$WORK/test-disk.qcow2"
DISK_SIZE=${DISK_SIZE:-80G}
RAM=${RAM:-4096}
PORT=${PORT:-8000}
ISO=${ISO:-}

# 1. dependencies (qemu + OVMF firmware)
need=()
command -v qemu-system-x86_64 >/dev/null || need+=(qemu-full)
# prefer system qemu-img — Android SDK ships its own that may shadow it in PATH
QEMU_IMG=/usr/bin/qemu-img; [[ -x $QEMU_IMG ]] || QEMU_IMG=qemu-img
ovmf_code=""; ovmf_vars_src=""
for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
         /usr/share/OVMF/OVMF_CODE.4m.fd /usr/share/OVMF/x64/OVMF_CODE.4m.fd \
         /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
  [[ -f $c ]] && { ovmf_code="$c"; ovmf_vars_src="${c/CODE/VARS}"; break; }
done
[[ -n $ovmf_code && -f $ovmf_vars_src ]] || need+=(edk2-ovmf)
if (( ${#need[@]} )); then die "install first:  sudo pacman -S --needed ${need[*]}"; fi
say "qemu + OVMF found ($ovmf_code)"

mkdir -p "$WORK"

# 2. Arch ISO
if [[ -z $ISO ]]; then
  ISO=$(ls -1t "$WORK"/archlinux-*.iso "$HOME"/Downloads/archlinux-*.iso 2>/dev/null | head -1 || true)
fi
if [[ -z $ISO || ! -f $ISO ]]; then
  ISO="$WORK/archlinux-x86_64.iso"
  say "downloading latest Arch ISO (~1.2G) -> $ISO"
  curl -fSL --retry 3 -o "$ISO" https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso
fi
say "ISO: $ISO"

# 3. virtual disk + writable OVMF vars copy
[[ ${FRESH:-0} == 1 ]] && rm -f "$DISK"
[[ -f $DISK ]] || { say "creating blank ${DISK_SIZE} disk"; "$QEMU_IMG" create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null; }
cp -f "$ovmf_vars_src" "$WORK/OVMF_VARS.fd"

# 4. serve installer over loopback (qemu guest reaches host at 10.0.2.2)
( cd "$SCRIPTS_DIR" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) &>/dev/null &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null || true' EXIT
sleep 1

cat <<EOF

  ┌─ VM smoke test ─────────────────────────────────────────────┐
   Inside the VM's Arch ISO root shell, run the installer:
     ${0##*/} serves scripts/ at http://10.0.2.2:$PORT/
     Active INSTALLER=${INSTALLER}

     bash <(curl -fsSL http://10.0.2.2:$PORT/${INSTALLER})

   • Disk mode: AUTO · target: /dev/vda (the ONLY disk in the VM)
   • Tests: partition+format, LUKS, btrfs(+@tmp), UKIs, systemd-boot
   • T14s script: confirm past DMI warn (VM has no 21CQ/21CR); AMD ucode OK
   • After 'reboot', remove ISO: VM boot menu → disk, expect GDM
   • Reset between runs:  FRESH=1 ${0##*/}
   • T14s: INSTALLER=arch-install-t14s.sh ${0##*/}
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
