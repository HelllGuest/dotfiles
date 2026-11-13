#!/usr/bin/env bash
# lab-detonate.sh — disposable analysis VMs on virbr-malware + capture stack.
#
# Network: virbr-malware (192.168.200.0/24, no NAT/forward) → firewalld zone lab-malware.
# Capture: INetSim (fake DNS/HTTP/HTTPS) + optional PolarProxy on 192.168.200.1.
# lab-malware: target DROP, masquerade off, no forward-ports — only 53/80/443/10443/10080.

#
# Usage:
#   bash scripts/lab-detonate.sh setup
#   bash scripts/lab-detonate.sh capture-up|capture-down|status
#   bash scripts/lab-detonate.sh linux-define|linux-start|linux-stop|linux-wipe
#   bash scripts/lab-detonate.sh windows-define   # needs DETONATE_WIN_DISK=path.qcow2
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/lab-malware-zone.sh
source "$REPO_ROOT/scripts/lib/lab-malware-zone.sh"
LAB_ROOT="${LAB_ROOT:-/srv/lab}"
DET_DIR="${LAB_ROOT}/detonate"
CAPTURE_LOG="${LAB_ROOT}/capture"
BIND_IP="${LAB_CAPTURE_BIND:-192.168.200.1}"
LINUX_NAME="${DETONATE_LINUX_NAME:-detonate-linux}"
WIN_NAME="${DETONATE_WIN_NAME:-detonate-windows}"
LINUX_BASE="${DET_DIR}/linux-base.qcow2"
LINUX_OVERLAY="${DET_DIR}/linux-overlay.qcow2"

die() { echo "ERR $*" >&2; exit 1; }
say() { printf '→ %s\n' "$*"; }
need() { command -v "$1" >/dev/null || die "missing $1"; }

virsh_s() { sudo virsh "$@"; }

ensure_net() {
  need virsh
  sudo systemctl enable --now libvirtd.service 2>/dev/null || true
  if ! virsh_s net-info virbr-malware >/dev/null 2>&1; then
    die "virbr-malware missing — run: bash scripts/firewalld-migrate.sh"
  fi
  virsh_s net-start virbr-malware 2>/dev/null || true
  virsh_s net-autostart virbr-malware 2>/dev/null || true
  ensure_lab_malware_zone
  sudo ip link set virbr-malware up 2>/dev/null || true
}


cmd_setup() {
  ensure_net
  sudo install -d -m 0755 -o "$USER" -g "$USER" "$DET_DIR" "$CAPTURE_LOG" \
    "$CAPTURE_LOG/inetsim" "$CAPTURE_LOG/polarproxy" "$LAB_ROOT/samples" "$LAB_ROOT/out"
  say "Building lab-capture (INetSim) image..."
  podman build -t localhost/lab-capture:latest "$REPO_ROOT/labs/lab-capture"
  # Optional PolarProxy binary (host-side; not baked — Netresec URL varies)
  if [[ ! -x $CAPTURE_LOG/PolarProxy ]]; then
    say "Fetching PolarProxy (optional)..."
    tmp=$(mktemp -d)
    if curl -fsSL "https://www.netresec.com/?download=PolarProxy" -o "$tmp/pp.zip" \
      || curl -fsSL "https://www.netresec.com/files/PolarProxy_latest_linux-x64.zip" -o "$tmp/pp.zip"; then
      unzip -qo "$tmp/pp.zip" -d "$tmp/out"
      bin=$(find "$tmp/out" -type f -name PolarProxy | head -1)
      if [[ -n $bin ]]; then
        install -m 0755 "$bin" "$CAPTURE_LOG/PolarProxy"
        say "PolarProxy → $CAPTURE_LOG/PolarProxy"
      fi
    else
      echo "WARN: PolarProxy download failed — INetSim-only capture still works" >&2
    fi
    rm -rf "$tmp"
  fi
  echo "✓ detonate setup ready under $DET_DIR"
  echo "  next: bash scripts/lab-detonate.sh capture-up"
  echo "        bash scripts/lab-detonate.sh linux-define && linux-start"
}

cmd_capture_up() {
  ensure_net
  need podman
  podman image exists localhost/lab-capture:latest 2>/dev/null \
    || die "build capture image first: lab-detonate.sh setup"

  # Rootful host network so guests on 192.168.200.0/24 reach INetSim on BIND_IP.
  if podman container exists lab-inetsim 2>/dev/null; then
    say "lab-inetsim already defined"
    sudo podman start lab-inetsim 2>/dev/null || true
  else
    say "Starting INetSim (sudo podman --network=host, bind $BIND_IP)..."
    sudo podman run -d --name lab-inetsim --network=host --restart=unless-stopped \
      -v "$CAPTURE_LOG/inetsim:/var/log/inetsim:Z" \
      -e LAB_CAPTURE_BIND="$BIND_IP" \
      localhost/lab-capture:latest
  fi

  if [[ -x $CAPTURE_LOG/PolarProxy ]]; then
    if pgrep -f "[P]olarProxy" >/dev/null 2>&1; then
      say "PolarProxy already running"
    else
      say "Starting PolarProxy :10443 → HTTP (pcaps under $CAPTURE_LOG/polarproxy)..."
      # Listens on all ifaces; lab-malware firewalld zone only exposes it on virbr-malware.
      nohup "$CAPTURE_LOG/PolarProxy" -v \
        -p 10443,80,80 \
        --certhttp 10080 \
        -o "$CAPTURE_LOG/polarproxy" \
        >"$CAPTURE_LOG/polarproxy/polarproxy.log" 2>&1 &
      echo $! >"$CAPTURE_LOG/polarproxy/polarproxy.pid"
    fi
  else
    echo "○ PolarProxy binary missing — INetSim only (re-run setup to fetch)"
  fi
  echo "✓ capture up. Guests: DNS/HTTP/HTTPS → ${BIND_IP}; TLS mitm via :10443 if PolarProxy running"
  echo "  pcaps/logs: $CAPTURE_LOG"
}

cmd_capture_down() {
  sudo podman stop lab-inetsim 2>/dev/null || true
  sudo podman rm lab-inetsim 2>/dev/null || true
  if [[ -f $CAPTURE_LOG/polarproxy/polarproxy.pid ]]; then
    kill "$(cat "$CAPTURE_LOG/polarproxy/polarproxy.pid")" 2>/dev/null || true
    rm -f "$CAPTURE_LOG/polarproxy/polarproxy.pid"
  fi
  pkill -f "[P]olarProxy" 2>/dev/null || true
  echo "✓ capture down"
}

fetch_linux_base() {
  [[ -f $LINUX_BASE ]] && return 0
  say "Downloading Alpine cloud image → $LINUX_BASE"
  curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/cloud/nocloud_alpine-3.20.3-x86_64-bios-cloudinit-r0.qcow2" \
    -o "$LINUX_BASE.partial" \
    || curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2" \
      -o "$LINUX_BASE.partial" \
    || die "Alpine cloud image download failed"
  mv "$LINUX_BASE.partial" "$LINUX_BASE"
  chmod 444 "$LINUX_BASE"
}

cmd_linux_define() {
  ensure_net
  need virt-install
  need qemu-img
  fetch_linux_base
  if virsh_s dominfo "$LINUX_NAME" >/dev/null 2>&1; then
    say "domain $LINUX_NAME already defined"
    return 0
  fi
  rm -f "$LINUX_OVERLAY"
  qemu-img create -f qcow2 -F qcow2 -b "$LINUX_BASE" "$LINUX_OVERLAY" 8G
  say "Defining $LINUX_NAME on virbr-malware..."
  sudo virt-install --import --name "$LINUX_NAME" \
    --memory 2048 --vcpus 2 \
    --disk "path=${LINUX_OVERLAY},format=qcow2,bus=virtio" \
    --network "network=virbr-malware,model=virtio" \
    --os-variant alpinelinux3.18 \
    --graphics none --console pty,target_type=serial \
    --noautoconsole --noreboot
  virsh_s snapshot-create-as "$LINUX_NAME" clean "pre-detonation" --atomic || true
  echo "✓ $LINUX_NAME defined (snapshot: clean). Start: lab-detonate.sh linux-start"
}

cmd_linux_start() {
  ensure_net
  virsh_s start "$LINUX_NAME" 2>/dev/null || true
  echo "✓ $LINUX_NAME started on virbr-malware"
  echo "  console: sudo virsh console $LINUX_NAME"
}

cmd_linux_stop() {
  virsh_s shutdown "$LINUX_NAME" 2>/dev/null || virsh_s destroy "$LINUX_NAME" 2>/dev/null || true
  echo "✓ $LINUX_NAME stopped"
}

cmd_linux_wipe() {
  virsh_s destroy "$LINUX_NAME" 2>/dev/null || true
  if virsh_s snapshot-list "$LINUX_NAME" --name 2>/dev/null | grep -qx clean; then
    virsh_s snapshot-revert "$LINUX_NAME" clean --force
    say "reverted $LINUX_NAME → snapshot clean"
  else
    echo "WARN: no 'clean' snapshot — redefine if disk is dirty"
  fi
}

cmd_windows_define() {
  ensure_net
  local disk="${DETONATE_WIN_DISK:-}"
  [[ -n $disk && -f $disk ]] || die "set DETONATE_WIN_DISK=/path/to/windows.qcow2"
  if virsh_s dominfo "$WIN_NAME" >/dev/null 2>&1; then
    say "domain $WIN_NAME already defined"
    return 0
  fi
  need virt-install
  say "Defining $WIN_NAME on virbr-malware from $disk..."
  sudo virt-install --import --name "$WIN_NAME" \
    --memory 4096 --vcpus 2 \
    --disk "path=${disk},format=qcow2,bus=virtio" \
    --network "network=virbr-malware,model=virtio" \
    --os-variant win10 \
    --graphics spice --video qxl \
    --noautoconsole --noreboot
  virsh_s snapshot-create-as "$WIN_NAME" clean "pre-detonation" --atomic || true
  echo "✓ $WIN_NAME defined. Attach samples via /srv/lab/samples (host virtio-fs optional)."
}

cmd_status() {
  echo "=== virbr-malware ==="
  virsh_s net-info virbr-malware 2>/dev/null || echo "missing"
  ip -br addr show virbr-malware 2>/dev/null || true
  if command -v firewall-cmd >/dev/null; then
    echo "lab-malware ifaces: $(firewall-cmd --permanent --zone=lab-malware --list-interfaces 2>/dev/null || true)"
  fi
  echo "=== capture ==="
  sudo podman ps -a --filter name=lab-inetsim --format '{{.Names}} {{.Status}}' 2>/dev/null || true
  pgrep -a PolarProxy 2>/dev/null || echo "PolarProxy: not running"
  echo "=== domains ==="
  virsh_s list --all 2>/dev/null | grep -E "detonate|Name" || true
}

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-status}"
  shift || true
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    capture-up) cmd_capture_up "$@" ;;
    capture-down) cmd_capture_down "$@" ;;
    linux-define) cmd_linux_define "$@" ;;
    linux-start) cmd_linux_start "$@" ;;
    linux-stop) cmd_linux_stop "$@" ;;
    linux-wipe) cmd_linux_wipe "$@" ;;
    windows-define) cmd_windows_define "$@" ;;
    status) cmd_status "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd (try help)" ;;
  esac
}

main "$@"
