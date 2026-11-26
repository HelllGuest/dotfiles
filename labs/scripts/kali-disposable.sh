#!/usr/bin/env bash
# kali-disposable.sh — Kali guest with immutable base + ephemeral overlay.
#
# Pattern: one gold qcow2 (base). Each session boots a throwaway overlay.
# wipe/stop deletes the overlay → back to clean base. No host shares.
# Network default: isolated (no guest WAN). Use --nat for updates / cloud-init.
#
# Usage:
#   bash labs/scripts/kali-disposable.sh setup          # packages + download base
#   bash labs/scripts/kali-disposable.sh start           # new overlay + boot
#   bash labs/scripts/kali-disposable.sh start --nat     # NAT only (virbr0)
#   bash labs/scripts/kali-disposable.sh start --lan     # NAT + physical ethernet
#   bash labs/scripts/kali-disposable.sh attach-lan      # add LAN NIC to running VM
#   bash labs/scripts/kali-disposable.sh lan-check       # verify guest LAN reachability
#   bash labs/scripts/kali-disposable.sh stop            # power off, keep overlay
#   bash labs/scripts/kali-disposable.sh wipe            # destroy VM + delete overlay
#   bash labs/scripts/kali-disposable.sh status
#
# Env:
#   KALI_VM_DIR     default: /var/lib/libvirt/images/kali-disposable
#                   (system qemu cannot read $HOME; keep disks here)
#   KALI_RAM_MB     default: 4096
#   KALI_VCPUS      default: 4
#   KALI_NET        nat | isolated | none | nat+lan   (default: isolated)
#                   nat+lan = NAT eth0 + physical NIC via macvtap (see KALI_LAN_IFACE)
#                   (alias: lan → nat+lan)
#   KALI_LAN_IFACE  physical ethernet for nat+lan (default: enp0s31f6, else first ether)
#   KALI_IMAGE_URL / KALI_IMAGE_SHA256  pinned cloud image (override when bumping)
#   KALI_PASSWORD   guest SSH password (isolated default: kali; nat/lan: random unless set)
#   KALI_LAN_PROBE  LAN gateway IP for lan-check ping (default: 192.168.8.1)

set -euo pipefail

_KALI_TMP=()
_kali_cleanup() { ((${#_KALI_TMP[@]})) && rm -rf -- "${_KALI_TMP[@]}" || true; }
trap _kali_cleanup EXIT

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VM_NAME="${KALI_VM_NAME:-kali-disposable}"
VM_DIR="${KALI_VM_DIR:-/var/lib/libvirt/images/kali-disposable}"
BASE_IMG="$VM_DIR/kali-base.qcow2"
OVERLAY="$VM_DIR/kali-session.qcow2"
RAM_MB="${KALI_RAM_MB:-4096}"
VCPUS="${KALI_VCPUS:-4}"
NET_MODE="${KALI_NET:-isolated}"
LAN_IFACE="${KALI_LAN_IFACE:-enp0s31f6}"
LAN_IFACE_SET=0
[[ -n "${KALI_LAN_IFACE:-}" ]] && LAN_IFACE_SET=1

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

# Official cloud image (amd64). Bump URL + SHA together (see SHA256SUMS on kali.download).
# Pin the per-release dir, not current/: current/ drops this file at the next release.
KALI_IMAGE_URL="${KALI_IMAGE_URL:-https://kali.download/cloud-images/kali-2026.3/kali-linux-2026.3-cloud-genericcloud-amd64.tar.xz}"
KALI_IMAGE_SHA256="${KALI_IMAGE_SHA256:-087a9c43b6082b0a6aae666debe26c9edf6e3960a90952fc94720e755d628e58}"
KALI_PASS_FILE="${KALI_PASS_FILE:-}"  # set in ensure path; default under VM_DIR

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing $1 — run: $0 setup"; }

kali_pass_path() {
  printf '%s' "${KALI_PASS_FILE:-$VM_DIR/kali-session.password}"
}

# Isolated keeps lab default kali/kali. NAT/LAN never use a fixed password unless set.
# Fresh overlay → new random password; KEEP_OVERLAY=1 reuses the saved file.
resolve_kali_password() {
  local pass=""
  case "$NET_MODE" in
    nat|nat+lan)
      if [[ -n "${KALI_PASSWORD:-}" ]]; then
        pass="$KALI_PASSWORD"
      elif [[ "${KEEP_OVERLAY:-0}" == "1" && -f "$(kali_pass_path)" ]]; then
        pass="$(tr -d '\n' <"$(kali_pass_path)")"
      else
        pass="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
        [[ ${#pass} -eq 20 ]] || die "failed to generate KALI_PASSWORD"
      fi
      ;;
    *)
      pass="${KALI_PASSWORD:-kali}"
      ;;
  esac
  [[ "$pass" =~ ^[A-Za-z0-9._@%-]+$ ]] \
    || die "KALI_PASSWORD must be alphanumeric (plus . _ @ % -)"
  KALI_PASS="$pass"
}

save_kali_password() {
  case "$NET_MODE" in
    nat|nat+lan)
      ensure_vm_dir
      (
        umask 077
        printf '%s\n' "$KALI_PASS" >"$(kali_pass_path)"
        chmod 600 "$(kali_pass_path)" 2>/dev/null || true
      )
      ;;
  esac
}

guest_ssh_password() {
  if [[ -n "${KALI_PASSWORD:-}" ]]; then
    printf '%s' "$KALI_PASSWORD"
  elif [[ -f "$(kali_pass_path)" ]]; then
    tr -d '\n' <"$(kali_pass_path)"
  else
    printf '%s' kali
  fi
}

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
  # Boot race: bring virbr0 up after libvirt creates it (system-setup ships unit).
  if [[ -f "$REPO_ROOT/system/etc/systemd/system/virbr0-up.service" ]]; then
    sudo_do install -Dm644 \
      "$REPO_ROOT/system/etc/systemd/system/virbr0-up.service" \
      /etc/systemd/system/virbr0-up.service
    sudo_do systemctl daemon-reload
    sudo_do systemctl enable --now virbr0-up.service 2>/dev/null || true
  fi
  sudo_do ip link set virbr0 up 2>/dev/null || true
  # firewalld: libvirt zone owns virbr0 (see security/scripts/firewalld-lab-zones.sh).
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    sudo_do firewall-cmd --permanent --zone=libvirt --change-interface=virbr0 2>/dev/null || true
    sudo_do firewall-cmd --zone=libvirt --change-interface=virbr0 2>/dev/null || true
    sudo_do firewall-cmd --reload 2>/dev/null || true
  fi
  sudo_do usermod -aG libvirt,kvm "$USER"
  ensure_vm_dir
  echo "✓ packages + libvirtd. Log out/in (or: newgrp libvirt) before start."
}

# Ensure default NAT is usable (firewalld libvirt zone + bridge up).
ensure_nat_forward() {
  case "$NET_MODE" in
    nat|nat+lan) ;;
    *) return 0 ;;
  esac
  virsh_u net-start default 2>/dev/null || true
  # Admin-up even with NO-CARRIER; carrier appears when a guest tap attaches.
  sudo_do ip link set virbr0 up >/dev/null 2>&1 || true
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    sudo_do firewall-cmd --permanent --zone=libvirt --change-interface=virbr0 >/dev/null 2>&1 || true
    sudo_do firewall-cmd --zone=libvirt --change-interface=virbr0 >/dev/null 2>&1 || true
  fi
}

# Best-effort guest IPv4 on default/kali-isolated (hostname lease or domifaddr).
guest_ipv4() {
  local ip=""
  ip="$(virsh_u domifaddr "$VM_NAME" --source lease 2>/dev/null \
    | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)" || true
  if [[ -z "$ip" ]]; then
    ip="$(virsh_u net-dhcp-leases default 2>/dev/null \
      | awk '/kali-disposable/ {print $5}' | cut -d/ -f1 | head -1)" || true
  fi
  if [[ -z "$ip" ]]; then
    ip="$(virsh_u net-dhcp-leases kali-isolated 2>/dev/null \
      | awk '/kali-disposable/ {print $5}' | cut -d/ -f1 | head -1)" || true
  fi
  printf '%s' "$ip"
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
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum required to verify Kali image"
  local got
  got="$(sha256sum "$tmp/kali.tar.xz" | awk '{print $1}')"
  [[ "$got" == "$KALI_IMAGE_SHA256" ]] \
    || die "Kali image SHA-256 mismatch (got $got want $KALI_IMAGE_SHA256). Refusing to install. If you bumped KALI_IMAGE_URL, refresh KALI_IMAGE_SHA256 from ${KALI_IMAGE_URL%/*}/SHA256SUMS"
  echo "→ SHA-256 ok"
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
        (
          xml="$(mktemp)"
          trap 'rm -f -- "$xml"' EXIT
          cat > "$xml" <<'EOF'
<network>
  <name>kali-isolated</name>
  <bridge name='virbr-kali' stp='on' delay='0'/>
</network>
EOF
          virsh_u net-define "$xml" >&2
        )
        virsh_u net-start kali-isolated >&2 || true
        virsh_u net-autostart kali-isolated >&2 || true
      fi
      echo "--network network=kali-isolated"
      ;;
    # Primary virtio NIC on libvirt NAT; physical LAN attached after define.
    nat+lan|nat|*) echo "--network network=default" ;;
  esac
}

normalize_net_mode() {
  case "$NET_MODE" in
    lan) NET_MODE=nat+lan ;;
  esac
}

# Resolve LAN_IFACE: reject empty; keep explicit choice; else default or first ether.
resolve_lan_iface() {
  if [[ -z "$LAN_IFACE" ]]; then
    die "LAN iface empty — pass --lan-iface IFACE or set KALI_LAN_IFACE"
  fi
  if [[ -d "/sys/class/net/$LAN_IFACE" ]]; then
    return 0
  fi
  if [[ "$LAN_IFACE_SET" == "1" ]]; then
    die "missing host LAN iface $LAN_IFACE (set KALI_LAN_IFACE to a real NIC)"
  fi
  local path name picked=""
  for path in /sys/class/net/*; do
    name="${path##*/}"
    case "$name" in
      lo|virbr*|docker*|br-*|veth*|wlan*|wl*|wwan*|tailscale*|macvtap*|vnet*|tun*|tap*) continue ;;
    esac
    [[ -d "$path/wireless" ]] && continue
    [[ -e "$path/type" && "$(cat "$path/type" 2>/dev/null || echo)" == "1" ]] || continue
    picked="$name"
    break
  done
  [[ -n "$picked" ]] || die "no physical LAN iface found — set KALI_LAN_IFACE=…"
  echo "→ default $LAN_IFACE missing; using $picked"
  LAN_IFACE="$picked"
}

restore_lan_nm() {
  # attach_lan_iface may set managed no; wipe returns the NIC to NetworkManager.
  command -v nmcli >/dev/null 2>&1 || return 0
  [[ -n "$LAN_IFACE" && -d "/sys/class/net/$LAN_IFACE" ]] || return 0
  nmcli device set "$LAN_IFACE" managed yes >/dev/null 2>&1 || true
}

lan_eth1_unit_body() {
  # eth1 is LAN L2/L3 access only. WiFi/NAT (eth0) keeps the sole default gateway.
  # Dual defaults (LAN CPE + NAT) break routing/DNS when the cable is plugged.
  # Also ignore CPE DNS/RA (sinkholes e.g. registry.npmjs.org → 172.31.255.254).
  # Filename 05- beats netplan's 10-netplan-eth1.network.
  cat <<'EOF'
[Match]
Name=eth1
[Network]
DHCP=yes
IPv6AcceptRA=no
DNSDefaultRoute=no
[DHCPv4]
UseDNS=no
UseDomains=no
UseGateway=no
UseRoutes=no
[DHCPv6]
UseDNS=no
UseDomains=no
UseGateway=no
UseRoutes=no
EOF
}

resolved_public_dns_body() {
  cat <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 9.9.9.9
EOF
}

# Seed eth1 DHCP + public DNS on guests that predate cloud-init write_files.
ensure_guest_lan_dhcp() {
  local unit_path="/etc/systemd/network/05-kali-eth1.network"
  local dns_path="/etc/systemd/resolved.conf.d/99-kali-public-dns.conf"
  local gip="" body dns_body tmp_unit tmp_dns
  local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
  body="$(lan_eth1_unit_body)"
  dns_body="$(resolved_public_dns_body)"

  seed_guest_dns_via_ssh() {
    local ssh=(ssh "${ssh_opts[@]}" "kali@$gip")
    [[ "${1:-}" == "sshpass" ]] && ssh=(sshpass -p "$(guest_ssh_password)" ssh "${ssh_opts[@]}" "kali@$gip")
    "${ssh[@]}" "sudo mkdir -p /etc/systemd/resolved.conf.d /etc/systemd/network" 2>/dev/null || return 1
    printf '%s\n' "$body" | "${ssh[@]}" "sudo tee $unit_path >/dev/null" 2>/dev/null || return 1
    printf '%s\n' "$dns_body" | "${ssh[@]}" "sudo tee $dns_path >/dev/null" 2>/dev/null || return 1
    "${ssh[@]}" "sudo rm -f /etc/systemd/network/20-lan-eth1.network /etc/systemd/network/21-lan-eth1-byname.network; sudo systemctl restart systemd-networkd systemd-resolved 2>/dev/null || true; resolvectl flush-caches 2>/dev/null || true" 2>/dev/null || return 1
  }

  if virsh_u domstate "$VM_NAME" 2>/dev/null | grep -qi running; then
    gip="$(guest_ipv4)"
    if [[ -z "$gip" ]]; then
      echo "  note: no guest NAT IP yet — eth1 DHCP unit may need: kali-wipe && kali-up-lan"
      return 0
    fi
    if command -v sshpass >/dev/null 2>&1 && seed_guest_dns_via_ssh sshpass; then
      echo "✓ seeded guest LAN DNS ($unit_path + public resolvers) via ssh (kali@$gip)"
      return 0
    fi
    if seed_guest_dns_via_ssh; then
      echo "✓ seeded guest LAN DNS ($unit_path + public resolvers) via ssh (kali@$gip)"
      return 0
    fi
    echo "  note: could not ssh to kali@$gip to seed eth1 DNS (install sshpass or use kali-wipe && kali-up-lan)"
    return 0
  fi

  # Offline overlay: inject with virt-customize when available.
  if [[ -f "$OVERLAY" ]] && command -v virt-customize >/dev/null 2>&1; then
    tmp_unit="$(mktemp)"; tmp_dns="$(mktemp)"
    printf '%s\n' "$body" >"$tmp_unit"
    printf '%s\n' "$dns_body" >"$tmp_dns"
    if virt-customize -q -a "$OVERLAY" \
      --mkdir /etc/systemd/resolved.conf.d \
      --upload "$tmp_unit:$unit_path" \
      --upload "$tmp_dns:$dns_path" 2>/dev/null; then
      echo "✓ seeded $unit_path + public DNS into overlay via virt-customize"
    else
      echo "  note: virt-customize seed failed — use kali-wipe && kali-up-lan for eth1 DNS"
    fi
    rm -f "$tmp_unit" "$tmp_dns"
  fi
}

host_prep_lan_iface() {
  resolve_lan_iface
  local prep="$REPO_ROOT/labs/scripts/kali-lan-host-prep.sh"
  [[ -x "$prep" ]] || die "missing $prep"
  # Prefer installed pkexec helper (wheel polkit); fall back to sudo.
  if [[ -x /usr/local/bin/kali-lan-host-prep ]]; then
    if pkexec /usr/local/bin/kali-lan-host-prep "$LAN_IFACE"; then
      return 0
    fi
  fi
  if sudo_do bash "$prep" "$LAN_IFACE"; then
    return 0
  fi
  # Fail closed when parent still has IPv4 — macvtap cannot share a polluted NIC.
  if ip -4 -o addr show dev "$LAN_IFACE" 2>/dev/null | grep -q .; then
    cat >&2 <<EOF
ERROR: host $LAN_IFACE still has IPv4 (often a broken /0 from NM "Wired connection").
That blocks Kali macvtap from reaching LAN peers. Fix once on the host:

  sudo bash $prep $LAN_IFACE
  sudo install -m0755 -o root -g root $prep /usr/local/bin/kali-lan-host-prep
  sudo install -m0644 -o root -g root \\
    $REPO_ROOT/system/etc/polkit-1/rules.d/50-kali-lan-host-prep.rules \\
    /etc/polkit-1/rules.d/50-kali-lan-host-prep.rules

Then: kali attach-lan && kali lan-check
EOF
    return 1
  fi
  # No IPv4 left — good enough even if sudo failed mid-way.
  sudo_do ip link set "$LAN_IFACE" up >/dev/null 2>&1 \
    || ip link set "$LAN_IFACE" up >/dev/null 2>&1 \
    || true
}

# Attach host physical ethernet into the guest via macvtap (bridge mode).
# Guest sees it as eth1 when NAT eth0 is also present. Needs cable/carrier
# on LAN_IFACE for DHCP on the physical LAN. Host RJ45 has no IP (wifi gateway).
attach_lan_iface() {
  case "$NET_MODE" in
    nat+lan) ;;
    *) return 0 ;;
  esac
  virsh_u dominfo "$VM_NAME" >/dev/null 2>&1 \
    || die "domain $VM_NAME not defined — start the guest first"
  resolve_lan_iface
  host_prep_lan_iface || die "host LAN prep failed — Kali cannot use the physical LAN"

  if virsh_u dumpxml "$VM_NAME" 2>/dev/null | grep -q "dev='$LAN_IFACE'"; then
    echo "✓ LAN macvtap already attached ($LAN_IFACE)"
    ensure_guest_lan_dhcp
    if ! ip -br link show "$LAN_IFACE" 2>/dev/null | grep -q 'LOWER_UP'; then
      echo "  note: $LAN_IFACE has no carrier — plug ethernet cable for guest eth1 DHCP"
    fi
    return 0
  fi

  local xml
  xml="$(mktemp)"
  _KALI_TMP+=("$xml")
  cat >"$xml" <<EOF
<interface type='direct'>
  <source dev='$LAN_IFACE' mode='bridge'/>
  <model type='virtio'/>
</interface>
EOF
  if virsh_u domstate "$VM_NAME" 2>/dev/null | grep -qi running; then
    virsh_u attach-device "$VM_NAME" "$xml" --live --persistent
  else
    virsh_u attach-device "$VM_NAME" "$xml" --config
  fi
  rm -f "$xml"
  echo "✓ attached physical LAN $LAN_IFACE → guest (macvtap bridge mode)"
  echo "  note: NetworkManager left unmanaged on $LAN_IFACE until wipe"
  ensure_guest_lan_dhcp
  if ! ip -br link show "$LAN_IFACE" 2>/dev/null | grep -q 'LOWER_UP'; then
    echo "  note: $LAN_IFACE has no carrier — plug ethernet cable for guest eth1 DHCP"
  fi
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
  rm -f "$(kali_pass_path)"
  # Best-effort: restore NM on known iface without dying if absent.
  if [[ -n "$LAN_IFACE" && -d "/sys/class/net/$LAN_IFACE" ]]; then
    restore_lan_nm
  elif [[ -d /sys/class/net/enp0s31f6 ]]; then
    LAN_IFACE=enp0s31f6
    restore_lan_nm
  fi
  echo "✓ wiped session overlay; base untouched: $BASE_IMG"
}

cmd_start() {
  need virsh
  need qemu-img
  need virt-install
  ensure_vm_dir
  [[ -f "$BASE_IMG" ]] || die "no base image — run: $0 setup"
  groups | grep -qw libvirt || die "user not in libvirt group — log out/in after setup"
  ensure_nat_forward

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
    # Kali genericcloud needs cloud-init NoCloud seed or networking never comes up.
    local ci_dir ci_user ci_meta
    resolve_kali_password
    save_kali_password
    ci_dir="$(mktemp -d "${TMPDIR:-/tmp}/kali-ci.XXXXXX")"
    _KALI_TMP+=("$ci_dir")
    ci_user="$ci_dir/user-data"
    ci_meta="$ci_dir/meta-data"
    # Unquoted EOF: only KALI_PASS is expanded (validated alphanumeric above).
    cat >"$ci_user" <<EOF
#cloud-config
hostname: kali-disposable
manage_etc_hosts: true
ssh_pwauth: true
disable_root: false
chpasswd:
  expire: false
  users:
    - {name: kali, password: "${KALI_PASS}", type: text}
users:
  - default
  - name: kali
    gecos: Kali
    groups: [adm, sudo, dialout]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "${KALI_PASS}"
write_files:
  - path: /etc/ssh/sshd_config.d/99-kali-disposable.conf
    permissions: "0644"
    content: |
      PasswordAuthentication yes
      KbdInteractiveAuthentication yes
      PermitRootLogin no
  - path: /etc/systemd/network/05-kali-eth1.network
    permissions: "0644"
    content: |
      [Match]
      Name=eth1
      [Network]
      DHCP=yes
      IPv6AcceptRA=no
      DNSDefaultRoute=no
      [DHCPv4]
      UseDNS=no
      UseDomains=no
      UseGateway=no
      UseRoutes=no
      [DHCPv6]
      UseDNS=no
      UseDomains=no
      UseGateway=no
      UseRoutes=no
  - path: /etc/systemd/resolved.conf.d/99-kali-public-dns.conf
    permissions: "0644"
    content: |
      [Resolve]
      DNS=1.1.1.1 8.8.8.8
      FallbackDNS=1.0.0.1 9.9.9.9
  - path: /etc/netplan/99-kali-dns.yaml
    permissions: "0600"
    content: |
      network:
        version: 2
        renderer: networkd
        ethernets:
          eth0:
            dhcp4: true
            nameservers:
              addresses: [1.1.1.1, 8.8.8.8]
          eth1:
            dhcp4: true
            accept-ra: false
            dhcp4-overrides:
              use-dns: false
              use-domains: false
              use-routes: false
packages:
  - openssh-server
runcmd:
  - systemctl enable --now ssh || systemctl enable --now sshd || true
  - systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  - netplan apply 2>/dev/null || true
  - systemctl restart systemd-networkd 2>/dev/null || true
  - systemctl restart systemd-resolved 2>/dev/null || true
  - resolvectl flush-caches 2>/dev/null || true
EOF
    # Fresh instance-id each overlay so cloud-init always re-runs.
    printf 'instance-id: kali-disposable-%s\nlocal-hostname: kali-disposable\n' \
      "$(date +%s)" >"$ci_meta"
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
      --cloud-init "user-data=${ci_user},meta-data=${ci_meta}" \
      --graphics spice \
      --video virtio \
      --console pty,target_type=serial \
      --noautoconsole \
      --quiet
    rm -rf -- "$ci_dir"
  fi

  # Carrier + lease can lag a few seconds after virt-install returns.
  sudo_do ip link set virbr0 up >/dev/null 2>&1 || true
  attach_lan_iface
  local gip=""
  for _ in 1 2 3 4 5 6; do
    gip="$(guest_ipv4)"
    [[ -n "$gip" ]] && break
    sleep 2
  done

  echo "✓ $VM_NAME running (URI=$(uri))"
  echo "  GUI: virt-manager → $VM_NAME   or:  virsh -c $(uri) console $VM_NAME"
  case "$NET_MODE" in
    nat|nat+lan)
      echo "  Cloud login: kali / ${KALI_PASS:-$(guest_ssh_password)}  (also: $(kali_pass_path))"
      ;;
    *)
      echo "  Cloud login: kali / ${KALI_PASS:-kali} — isolated net; change if you open networking."
      ;;
  esac
  if [[ -n "$gip" ]]; then
    echo "  Guest IP (NAT): $gip   (ssh kali@$gip)"
  else
    echo "  Guest IP: (pending DHCP — virsh net-dhcp-leases default)"
  fi
  case "$NET_MODE" in
    nat+lan)
      echo "  Physical LAN: $LAN_IFACE → guest eth1 (macvtap). Plug cable if no carrier."
      echo "  NM: $LAN_IFACE unmanaged until wipe (macvtap)."
      ;;
  esac
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
  echo "LAN_IFACE=$LAN_IFACE $(ip -br link show "$LAN_IFACE" 2>/dev/null || echo missing)"
  if command -v virsh >/dev/null; then
    virsh_u dominfo "$VM_NAME" 2>/dev/null || echo "domain: not defined"
    if virsh_u dumpxml "$VM_NAME" 2>/dev/null | grep -q "dev='$LAN_IFACE'"; then
      echo "LAN: macvtap attached ($LAN_IFACE → guest eth1)"
    else
      echo "LAN: not attached (kali attach-lan / start --lan)"
    fi
  fi
  if [[ -f "$BASE_IMG" ]]; then qemu-img info "$BASE_IMG" 2>/dev/null | head -6; fi
  if [[ -f "$OVERLAY" ]]; then qemu-img info "$OVERLAY" 2>/dev/null | head -8; fi
  return 0
}

cmd_lan_check() {
  need virsh
  resolve_lan_iface
  local gip guest_lan="" ok=1

  echo "HOST_IFACE=$LAN_IFACE $(ip -br link show "$LAN_IFACE" 2>/dev/null || echo missing)"
  if ip -4 -o addr show dev "$LAN_IFACE" 2>/dev/null | grep -q .; then
    echo "FAIL: host $LAN_IFACE still has IPv4 (blocks macvtap):"
    ip -4 addr show dev "$LAN_IFACE" | sed 's/^/  /'
    echo "  fix: sudo bash $REPO_ROOT/labs/scripts/kali-lan-host-prep.sh $LAN_IFACE"
    ok=0
  else
    echo "PASS: host $LAN_IFACE has no IPv4 (good for macvtap)"
  fi
  if virsh_u dumpxml "$VM_NAME" 2>/dev/null | grep -q "dev='$LAN_IFACE'"; then
    echo "PASS: macvtap attached to $LAN_IFACE"
  else
    echo "FAIL: macvtap not attached — kali attach-lan / kali-up-lan"
    ok=0
  fi
  gip="$(guest_ipv4)"
  if [[ -z "$gip" ]]; then
    echo "FAIL: no guest NAT IP"
    ok=0
  else
    echo "PASS: guest NAT $gip"
    local ssh=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
    local run=(sshpass -p "$(guest_ssh_password)" "${ssh[@]}" "kali@$gip")
    command -v sshpass >/dev/null || run=("${ssh[@]}" -o BatchMode=yes "kali@$gip")
    if out="$("${run[@]}" 'ip -4 -br addr show eth1; ip -4 route show default; ping -c1 -W2 $(ip -4 route show default | awk "/default/{print \$3; exit}") >/dev/null && echo GW_OK' 2>/dev/null)"; then
      echo "$out" | sed 's/^/  /'
      guest_lan="$(echo "$out" | awk '/^eth1/{print $3}' | head -1)"
      echo "PASS: guest eth1 present (${guest_lan:-?})"
      echo "$out" | grep -q GW_OK && echo "PASS: guest default gw reachable (NAT)" \
        || { echo "FAIL: guest default gw ping"; ok=0; }
      local lan_probe="${KALI_LAN_PROBE:-192.168.8.1}"
      [[ "$lan_probe" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "invalid KALI_LAN_PROBE: $lan_probe"
      if "${run[@]}" "ping -c1 -W2 ${lan_probe} >/dev/null" 2>/dev/null; then
        echo "PASS: guest → LAN gateway ${lan_probe} via eth1"
      else
        echo "FAIL: guest cannot ping ${lan_probe} on eth1"
        ok=0
      fi
    else
      echo "FAIL: cannot ssh into guest as kali@$gip"
      ok=0
    fi
  fi
  [[ "$ok" -eq 1 ]] || die "lan-check failed"
  echo "✓ Kali LAN access OK"
}

cmd_setup() {
  cmd_setup_host
  # Install host LAN prep helper + polkit (needs sudo once).
  if [[ -f "$REPO_ROOT/labs/scripts/kali-lan-host-prep.sh" ]]; then
    sudo_do install -m 0755 -o root -g root \
      "$REPO_ROOT/labs/scripts/kali-lan-host-prep.sh" /usr/local/bin/kali-lan-host-prep || true
    sudo_do install -m 0644 -o root -g root \
      "$REPO_ROOT/system/etc/polkit-1/rules.d/50-kali-lan-host-prep.rules" \
      /etc/polkit-1/rules.d/50-kali-lan-host-prep.rules || true
  fi
  cmd_fetch_base
  cmd_status
  echo
  echo "Next: newgrp libvirt   # or re-login"
  echo "      bash $REPO_ROOT/labs/scripts/kali-disposable.sh start --lan"
  echo "      bash $REPO_ROOT/labs/scripts/kali-disposable.sh lan-check"
  echo "      bash $REPO_ROOT/labs/scripts/kali-disposable.sh wipe   # after work"
}

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-}"
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --isolated) NET_MODE=isolated; shift ;;
      --nat) NET_MODE=nat; shift ;;
      --lan|--nat-lan) NET_MODE=nat+lan; shift ;;
      --none) NET_MODE=none; shift ;;
      --keep) KEEP_OVERLAY=1; shift ;;
      --lan-iface)
        [[ -n "${2:-}" ]] || die "--lan-iface needs a non-empty interface name"
        LAN_IFACE="$2"
        LAN_IFACE_SET=1
        shift 2
        ;;
      *) break ;;
    esac
  done
  normalize_net_mode
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    wipe) cmd_wipe "$@" ;;
    status) cmd_status "$@" ;;
    attach-lan) NET_MODE=nat+lan; attach_lan_iface ;;
    lan-check) cmd_lan_check "$@" ;;
    fetch) cmd_fetch_base "$@" ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown command: $cmd (setup|start|stop|wipe|status|attach-lan|lan-check)" ;;
  esac
}

main "$@"
