#!/usr/bin/env bash
# kali-disposable.sh — Kali guest with immutable base + ephemeral overlay.
#
# Pattern: one gold qcow2 (base). Each session boots a throwaway overlay.
# wipe/stop deletes the overlay → back to clean base. No host shares.
# Network default: libvirt NAT (not bridged). Use --isolated for no guest WAN.
#
# Usage:
#   bash scripts/kali-disposable.sh setup          # packages + download base
#   bash scripts/kali-disposable.sh start           # new overlay + boot
#   bash scripts/kali-disposable.sh stop            # power off, keep overlay
#   bash scripts/kali-disposable.sh wipe            # destroy VM + delete overlay
#   bash scripts/kali-disposable.sh status
#   bash scripts/kali-disposable.sh console         # serial/virsh console hint
#
# Env:
#   KALI_VM_DIR     default: /var/lib/libvirt/images/kali-disposable
#                   (system qemu cannot read $HOME; keep disks here)
#   KALI_RAM_MB     default: 4096
#   KALI_VCPUS      default: 4
#   KALI_NET        nat | isolated | none   (default: nat)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM_NAME="${KALI_VM_NAME:-kali-disposable}"
VM_DIR="${KALI_VM_DIR:-/var/lib/libvirt/images/kali-disposable}"
BASE_IMG="$VM_DIR/kali-base.qcow2"
OVERLAY="$VM_DIR/kali-session.qcow2"
RAM_MB="${KALI_RAM_MB:-4096}"
VCPUS="${KALI_VCPUS:-4}"
NET_MODE="${KALI_NET:-nat}"

ensure_vm_dir() {
  if [[ ! -d "$VM_DIR" ]]; then
    if [[ "$VM_DIR" == /var/lib/libvirt/* ]]; then
      sudo_do mkdir -p "$VM_DIR"
      sudo_do chown "$USER:libvirt" "$VM_DIR"
      sudo_do chmod 775 "$VM_DIR"
    else
      mkdir -p "$VM_DIR"
    fi
  fi
  # Writable by user+libvirt; libvirtd dynamic_ownership hands disks to qemu at start.
  if [[ "$VM_DIR" == /var/lib/libvirt/* ]] && [[ ! -w "$VM_DIR" ]]; then
    sudo_do chown "$USER:libvirt" "$VM_DIR"
    sudo_do chmod 775 "$VM_DIR"
  fi
}

# Official weekly cloud qcow2 (amd64). Override with KALI_IMAGE_URL if needed.
KALI_IMAGE_URL="${KALI_IMAGE_URL:-https://kali.download/cloud-images/current/kali-linux-2026.2-cloud-genericcloud-amd64.tar.xz}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing $1 — run: $0 setup"; }

# Prefer askpass over SSH (no TTY). Set SUDO_ASKPASS or use interactive sudo.
sudo_do() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  else
    sudo "$@"
  fi
}

virsh_u() {
  # Prefer system session once user is in libvirt group; else qemu:///session.
  if groups | grep -qw libvirt 2>/dev/null && [[ -S /var/run/libvirt/libvirt-sock ]]; then
    virsh -c qemu:///system "$@"
  else
    virsh -c qemu:///session "$@"
  fi
}

uri() {
  if groups | grep -qw libvirt 2>/dev/null && [[ -S /var/run/libvirt/libvirt-sock ]]; then
    echo qemu:///system
  else
    echo qemu:///session
  fi
}

cmd_setup_host() {
  echo "→ installing host virt stack..."
  sudo_do pacman -S --needed --noconfirm \
    libvirt qemu-desktop edk2-ovmf dnsmasq iptables-nft virt-manager \
    virt-install libguestfs
  sudo_do systemctl enable --now libvirtd.service
  sudo_do systemctl enable --now virtnetworkd.service 2>/dev/null || true
  # default NAT network
  if ! sudo_do virsh net-info default >/dev/null 2>&1; then
    sudo_do virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null \
      || sudo_do virsh net-define /etc/libvirt/qemu/networks/default.xml 2>/dev/null \
      || true
  fi
  sudo_do virsh net-start default 2>/dev/null || true
  sudo_do virsh net-autostart default 2>/dev/null || true
  sudo_do usermod -aG libvirt,kvm "$USER"
  ensure_vm_dir
  echo "✓ packages + libvirtd. Log out/in (or: newgrp libvirt) before start."
}

cmd_fetch_base() {
  ensure_vm_dir
  if [[ -f "$BASE_IMG" ]]; then
    echo "✓ base exists: $BASE_IMG"
    qemu-img info "$BASE_IMG" | head -8
    return 0
  fi
  local tmp="$VM_DIR/download"
  mkdir -p "$tmp"
  echo "→ downloading Kali cloud image (large; may take a while)..."
  echo "  $KALI_IMAGE_URL"
  if ! curl -fL --retry 3 -o "$tmp/kali.tar.xz" "$KALI_IMAGE_URL"; then
    die "download failed. Set KALI_IMAGE_URL to a working kali cloud/qcow2 URL from https://www.kali.org/get-kali/"
  fi
  echo "→ extracting..."
  tar -xJf "$tmp/kali.tar.xz" -C "$tmp"
  # Kali genericcloud ships disk.raw; older builds used .qcow2.
  local disk
  disk="$(find "$tmp" \( -name '*.qcow2' -o -name '*.raw' -o -name '*.img' \) -type f | head -1)"
  [[ -n "$disk" ]] || die "no disk image (.qcow2/.raw/.img) inside archive"
  echo "→ preparing base qcow2 from $(basename "$disk")..."
  case "$disk" in
    *.qcow2) mv -f "$disk" "$BASE_IMG" ;;
    *) qemu-img convert -p -f raw -O qcow2 "$disk" "$BASE_IMG" ;;
  esac
  # Immutable base; overlay stays writable. libvirtd chowns for qemu at boot.
  chmod 444 "$BASE_IMG" || true
  chown "$USER:libvirt" "$BASE_IMG" 2>/dev/null || true
  rm -rf "$tmp"
  echo "✓ base ready: $BASE_IMG"
  qemu-img info "$BASE_IMG" | head -8
}

net_args() {
  case "$NET_MODE" in
    none) echo "--network none" ;;
    isolated)
      # no DHCP/WAN: create once if missing
      if ! virsh_u net-info kali-isolated >/dev/null 2>&1; then
        local xml
        xml="$(mktemp)"
        cat > "$xml" <<'EOF'
<network>
  <name>kali-isolated</name>
  <bridge name='virbr-kali' stp='on' delay='0'/>
</network>
EOF
        virsh_u net-define "$xml"
        rm -f "$xml"
        virsh_u net-start kali-isolated || true
        virsh_u net-autostart kali-isolated || true
      fi
      echo "--network network=kali-isolated"
      ;;
    nat|*) echo "--network network=default" ;;
  esac
}

cmd_wipe() {
  need virsh
  need qemu-img
  if virsh_u dominfo "$VM_NAME" >/dev/null 2>&1; then
    virsh_u destroy "$VM_NAME" 2>/dev/null || true
    virsh_u undefine "$VM_NAME" --nvram 2>/dev/null \
      || virsh_u undefine "$VM_NAME" 2>/dev/null || true
  fi
  rm -f "$OVERLAY"
  echo "✓ wiped session overlay; base untouched: $BASE_IMG"
}

cmd_start() {
  need virsh
  need qemu-img
  need virt-install
  ensure_vm_dir
  [[ -f "$BASE_IMG" ]] || die "no base image — run: $0 setup"
  groups | grep -qw libvirt || die "user not in libvirt group — log out/in after setup"

  # Always disposable: new overlay each start unless KEEP_OVERLAY=1
  if [[ "${KEEP_OVERLAY:-0}" != "1" ]]; then
    if virsh_u dominfo "$VM_NAME" >/dev/null 2>&1; then
      virsh_u destroy "$VM_NAME" 2>/dev/null || true
      virsh_u undefine "$VM_NAME" --nvram 2>/dev/null || virsh_u undefine "$VM_NAME" 2>/dev/null || true
    fi
    rm -f "$OVERLAY"
  fi

  if [[ ! -f "$OVERLAY" ]]; then
    echo "→ creating ephemeral overlay on base..."
    qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$OVERLAY"
    chmod 664 "$OVERLAY"
    chown "$USER:libvirt" "$OVERLAY" 2>/dev/null || true
  fi

  if virsh_u dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "→ starting existing domain $VM_NAME"
    virsh_u start "$VM_NAME"
  else
    echo "→ importing disposable domain ($RAM_MB MiB, ${VCPUS} vCPU, net=$NET_MODE)"
    # shellcheck disable=SC2046
    virt-install \
      --connect "$(uri)" \
      --name "$VM_NAME" \
      --memory "$RAM_MB" \
      --vcpus "$VCPUS" \
      --cpu host \
      --import \
      --disk "path=$OVERLAY,format=qcow2,bus=virtio" \
      --os-variant debian12 \
      $(net_args) \
      --graphics spice \
      --video virtio \
      --noautoconsole \
      --quiet
  fi

  echo "✓ $VM_NAME running (URI=$(uri))"
  echo "  GUI: virt-manager → $VM_NAME   or:  virsh -c $(uri) console $VM_NAME"
  echo "  Default Kali cloud user is often 'kali'/'kali' — change password after first login."
  echo "  Disposable wipe:  $0 wipe"
}

cmd_stop() {
  need virsh
  virsh_u shutdown "$VM_NAME" 2>/dev/null || virsh_u destroy "$VM_NAME" 2>/dev/null || true
  echo "✓ stop requested (overlay kept). wipe to reset."
}

cmd_status() {
  echo "VM_DIR=$VM_DIR"
  echo "BASE=$( [[ -f $BASE_IMG ]] && echo present || echo missing ) $BASE_IMG"
  echo "OVERLAY=$( [[ -f $OVERLAY ]] && echo present || echo missing ) $OVERLAY"
  echo "NET=$NET_MODE RAM=${RAM_MB}M VCPUS=$VCPUS URI=$(uri 2>/dev/null || echo ?)"
  if command -v virsh >/dev/null; then
    virsh_u dominfo "$VM_NAME" 2>/dev/null || echo "domain: not defined"
  fi
  [[ -f "$BASE_IMG" ]] && qemu-img info "$BASE_IMG" 2>/dev/null | head -6
  [[ -f "$OVERLAY" ]] && qemu-img info "$OVERLAY" 2>/dev/null | head -8
}

cmd_setup() {
  cmd_setup_host
  cmd_fetch_base
  cmd_status
  echo
  echo "Next: newgrp libvirt   # or re-login"
  echo "      bash $REPO_ROOT/scripts/kali-disposable.sh start"
  echo "      bash $REPO_ROOT/scripts/kali-disposable.sh wipe   # after work"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-}"
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --isolated) NET_MODE=isolated; shift ;;
      --nat) NET_MODE=nat; shift ;;
      --none) NET_MODE=none; shift ;;
      --keep) KEEP_OVERLAY=1; shift ;;
      *) break ;;
    esac
  done
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    wipe) cmd_wipe "$@" ;;
    status) cmd_status "$@" ;;
    fetch) cmd_fetch_base "$@" ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown command: $cmd (setup|start|stop|wipe|status)" ;;
  esac
}

main "$@"
