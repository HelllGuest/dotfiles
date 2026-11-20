#!/usr/bin/env bash
# lab-detonate.sh — disposable analysis VMs on virbr-malware + capture stack.
#
# Network: virbr-malware (192.168.200.0/24, no NAT/forward) → firewalld zone lab-malware.
# Capture: INetSim (fake DNS/HTTP/HTTPS) + optional PolarProxy on 192.168.200.1.
# lab-malware: target DROP, masquerade off, no forward-ports — only 21/25/53/80/443/10443/10080.

#
# Usage:
#   bash scripts/lab-detonate.sh setup
#   bash scripts/lab-detonate.sh capture-up|capture-down|status
#   bash scripts/lab-detonate.sh linux-define|linux-start|linux-stop|linux-wipe
#   bash scripts/lab-detonate.sh windows-define   # needs DETONATE_WIN_DISK=path.qcow2
set -euo pipefail

_DET_TMP=()
_det_cleanup() { ((${#_DET_TMP[@]})) && rm -rf -- "${_DET_TMP[@]}" || true; }
trap _det_cleanup EXIT

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
    die "virbr-malware missing — run: bash scripts/firewalld-lab-zones.sh"
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
  say "Building lab-capture (INetSim) image (rootful store for capture-up)..."
  sudo podman build -t localhost/lab-capture:latest "$REPO_ROOT/labs/lab-capture"
  # Optional PolarProxy binary (host-side; not baked — Netresec URL varies).
  # It runs on the host, and Netresec publishes no checksum for "latest", so
  # install only a download whose SHA-256 the operator supplied after checking
  # it: POLARPROXY_SHA256=<sha256 of the zip> bash scripts/lab-detonate.sh setup
  if [[ ! -x $CAPTURE_LOG/PolarProxy && -z ${POLARPROXY_SHA256:-} ]]; then
    echo "○ PolarProxy skipped (unverifiable download). To add it: fetch the zip, verify it," >&2
    echo "  then re-run setup with POLARPROXY_SHA256=<its sha256>. INetSim-only capture still works." >&2
  elif [[ ! -x $CAPTURE_LOG/PolarProxy ]]; then
    [[ ${POLARPROXY_SHA256,,} =~ ^[0-9a-f]{64}$ ]] || die "POLARPROXY_SHA256 must be 64 hex chars"
    say "Fetching PolarProxy (optional, SHA-256 pinned)..."
    tmp=$(mktemp -d)
    if curl -fsSL "https://www.netresec.com/?download=PolarProxy" -o "$tmp/pp.zip" \
      || curl -fsSL "https://www.netresec.com/files/PolarProxy_latest_linux-x64.zip" -o "$tmp/pp.zip"; then
      got=$(sha256sum "$tmp/pp.zip" | awk '{print $1}')
      if [[ $got != "${POLARPROXY_SHA256,,}" ]]; then
        rm -rf -- "$tmp"
        die "PolarProxy SHA-256 mismatch (got $got) — not installed"
      fi
      unzip -qo "$tmp/pp.zip" -d "$tmp/out"
      bin=$(find "$tmp/out" -type f -name PolarProxy | head -1)
      if [[ -n $bin ]]; then
        install -m 0755 "$bin" "$CAPTURE_LOG/PolarProxy"
        # Record what was verified: capture-up only runs a matching binary.
        sha256sum "$CAPTURE_LOG/PolarProxy" | awk '{print $1}' >"$CAPTURE_LOG/PolarProxy.verified"
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
  sudo podman image exists localhost/lab-capture:latest 2>/dev/null \
    || die "build capture image first: lab-detonate.sh setup"

  # Rootful host network so guests on 192.168.200.0/24 reach INetSim on BIND_IP.
  # INetSim parses malware traffic: run it with only the caps it needs (bind
  # :53/:80/:443, switch to user inetsim, own its log dir), no new privileges
  # and a read-only root. Recreated every time (stateless; logs on the host
  # volume) so an older container cannot keep its original, broader caps.
  sudo podman rm -f lab-inetsim >/dev/null 2>&1 || true
  # Captures (mail, FTP uploads, HTTP POST bodies) on the host: they survive the
  # recreate above and are writable despite the read-only root.
  local data="$CAPTURE_LOG/inetsim-data"
  sudo install -d -m 0755 "$CAPTURE_LOG/inetsim" "$data/smtp" "$data/ftp-upload" "$data/http-postdata"
  say "Starting INetSim (sudo podman --network=host, bind $BIND_IP)..."
  sudo podman run -d --name lab-inetsim --network=host --restart=unless-stopped \
    --cap-drop ALL --cap-add NET_BIND_SERVICE --cap-add SETUID --cap-add SETGID --cap-add CHOWN \
    --security-opt no-new-privileges --read-only --tmpfs /tmp \
    -v "$CAPTURE_LOG/inetsim:/var/log/inetsim:Z" \
    -v "$data/smtp:/var/lib/inetsim/smtp:Z" \
    -v "$data/ftp-upload:/var/lib/inetsim/ftp/upload:Z" \
    -v "$data/http-postdata:/var/lib/inetsim/http/postdata:Z" \
    -e LAB_CAPTURE_BIND="$BIND_IP" \
    localhost/lab-capture:latest

  # Only a binary installed by setup after SHA-256 verification (older,
  # unverified downloads have no matching .verified record).
  local pp_ok=0
  if [[ -x $CAPTURE_LOG/PolarProxy && -f $CAPTURE_LOG/PolarProxy.verified ]] \
    && [[ $(sha256sum "$CAPTURE_LOG/PolarProxy" | awk '{print $1}') == "$(cat "$CAPTURE_LOG/PolarProxy.verified")" ]]; then
    pp_ok=1
  elif [[ -x $CAPTURE_LOG/PolarProxy ]]; then
    echo "○ PolarProxy not started: binary was not installed by a verified setup (delete it, re-run setup with POLARPROXY_SHA256)" >&2
  fi
  if (( pp_ok )); then
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
  elif [[ ! -x $CAPTURE_LOG/PolarProxy ]]; then
    echo "○ PolarProxy binary missing — INetSim only (setup with POLARPROXY_SHA256=<verified sha256> to add it)"
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

# Pinned Alpine cloud images (url sha512), from Alpine's published .sha512 files.
ALPINE_IMAGES=(
  "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/cloud/nocloud_alpine-3.20.3-x86_64-bios-cloudinit-r0.qcow2 73bd1fdfd9a0b4db250c923630a415a054ed1ae869e6ff4a121b49d28b2fb3a2a21a948bd0c121e5640f3f16c68cfb574b72fd6a4395a788a71f7f279c1c52e3"
  "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/cloud/nocloud_alpine-3.19.1-x86_64-bios-cloudinit-r0.qcow2 f122b0e9e832cf90bda49ca73b800105ab4aa193bd340cba641e6acbda1da9aa5571de87870561380ac69bdb2dcd428590e7b4a898f7f62b559f5c12a4aefc01"
)

fetch_linux_base() {
  local entry url want got
  if [[ -f $LINUX_BASE ]]; then
    # Images fetched before pinning are re-checked, never trusted blindly.
    got=$(sha512sum "$LINUX_BASE" | awk '{print $1}')
    for entry in "${ALPINE_IMAGES[@]}"; do
      [[ $got == "${entry##* }" ]] && return 0
    done
    die "$LINUX_BASE matches no pinned Alpine SHA-512 — delete it to fetch a verified image"
  fi
  say "Downloading Alpine cloud image → $LINUX_BASE"
  for entry in "${ALPINE_IMAGES[@]}"; do
    url=${entry% *} want=${entry##* }
    curl -fsSL "$url" -o "$LINUX_BASE.partial" || continue
    got=$(sha512sum "$LINUX_BASE.partial" | awk '{print $1}')
    if [[ $got == "$want" ]]; then
      mv "$LINUX_BASE.partial" "$LINUX_BASE"
      chmod 444 "$LINUX_BASE"
      return 0
    fi
    echo "WARN: SHA-512 mismatch for $url — discarded" >&2
  done
  rm -f -- "$LINUX_BASE.partial"
  die "no verified Alpine cloud image (download failed or checksum mismatch)"
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
  local pass="${DETONATE_LINUX_PASS:-detonate}" ci_dir ci_user ci_meta
  [[ "$LINUX_NAME" =~ ^[A-Za-z0-9._-]+$ ]] \
    || die "invalid DETONATE_LINUX_NAME: $LINUX_NAME"
  [[ "$pass" =~ ^[A-Za-z0-9._@%-]+$ ]] \
    || die "DETONATE_LINUX_PASS must be alphanumeric (plus . _ @ % -)"
  rm -f "$LINUX_OVERLAY"
  qemu-img create -f qcow2 -F qcow2 -b "$LINUX_BASE" "$LINUX_OVERLAY" 8G
  ci_dir="$(mktemp -d "${TMPDIR:-/tmp}/detonate-ci.XXXXXX")"
  _DET_TMP+=("$ci_dir")
  ci_user="$ci_dir/user-data"
  ci_meta="$ci_dir/meta-data"
  # Host-only isolated network (virbr-malware): seed console login for Alpine nocloud,
  # then power off so the clean snapshot captures the post-init disk without the
  # transient virt-install cloud-init ISO attached.
  cat >"$ci_user" <<EOF
#cloud-config
hostname: ${LINUX_NAME}
disable_root: false
chpasswd:
  expire: false
  users:
    - {name: root, password: "${pass}", type: text}
power_state:
  mode: poweroff
  timeout: 30
EOF
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' \
    "$LINUX_NAME" "$(date +%s)" "$LINUX_NAME" >"$ci_meta"
  say "Defining $LINUX_NAME on virbr-malware..."
  sudo virt-install --import --name "$LINUX_NAME" \
    --memory 2048 --vcpus 2 \
    --disk "path=${LINUX_OVERLAY},format=qcow2,bus=virtio" \
    --network "network=virbr-malware,model=virtio" \
    --os-variant alpinelinux3.18 \
    --cloud-init "user-data=${ci_user},meta-data=${ci_meta}" \
    --graphics none --console pty,target_type=serial \
    --noautoconsole --noreboot
  rm -rf -- "$ci_dir"
  # Wait for first-boot cloud-init poweroff so the clean snapshot is offline
  # (post-boot XML has the transient cloud-init ISO detached). Fail closed on
  # timeout instead of snapshotting a half-configured VM without a login seed.
  local _i
  for _i in $(seq 1 60); do
    virsh_s domstate "$LINUX_NAME" 2>/dev/null | grep -qi 'shut off' && break
    sleep 2
  done
  if ! virsh_s domstate "$LINUX_NAME" 2>/dev/null | grep -qi 'shut off'; then
    virsh_s destroy "$LINUX_NAME" 2>/dev/null || true
    virsh_s undefine "$LINUX_NAME" 2>/dev/null || true
    rm -f "$LINUX_OVERLAY"
    die "$LINUX_NAME did not power off after cloud-init (120s); aborted without creating a broken 'clean' snapshot"
  fi
  virsh_s snapshot-create-as "$LINUX_NAME" clean "pre-detonation" --atomic || true
  echo "✓ $LINUX_NAME defined (snapshot: clean; login: root / ${pass}). Start: lab-detonate.sh linux-start"
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
    echo "lab-malware ifaces: $(sudo firewall-cmd --permanent --zone=lab-malware --list-interfaces 2>/dev/null || true)"
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
