#!/usr/bin/env bash
# Smoke: kali-disposable + RE skill/extra installers parse and stay wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/kali-disposable.sh" \
  "$ROOT/scripts/install-re-skills.sh" \
  "$ROOT/scripts/install-re-extras.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  [[ -x "$f" ]] || fail "not executable: $f"
  bash -n "$f" || fail "bash -n failed: $f"
done

[[ -f "$ROOT/packages/agent-skills-re.txt" ]] || fail "missing agent-skills-re.txt"
[[ -f "$ROOT/packages/re-extra.txt" ]] || fail "missing re-extra.txt"

grep -q 'aicodeking/leanrea' "$ROOT/packages/agent-skills-re.txt" \
  || fail "leanrea pack missing"
grep -q 'OrbitCurve/firmware-reverse-engineering' "$ROOT/packages/agent-skills-re.txt" \
  || fail "OrbitCurve firmware pack missing"
grep -q 'zhaoxuya520/reverse-skill:firmware-pentest' "$ROOT/packages/agent-skills-re.txt" \
  || fail "firmware-pentest selective pack missing"
grep -q 'squashfs-tools' "$ROOT/packages/re-extra.txt" \
  || fail "firmware host pkgs missing from re-extra.txt"

grep -q 'KALI_NET:-isolated' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali default net must be isolated"
grep -q 'cloud-init' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali start must seed cloud-init for DHCP"
grep -q 'firewall-cmd' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali setup/start must use firewalld for virbr0"
grep -q 'zone=libvirt' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must bind virbr0 to firewalld libvirt zone"
grep -q 'ip link set virbr0 up' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must bring virbr0 admin-up for NAT"
grep -q 'virbr0-up.service' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali setup must install virbr0-up.service"
[[ -f "$ROOT/stow/system/etc/systemd/system/virbr0-up.service" ]] \
  || fail "missing stow/system virbr0-up.service"
grep -q 'net-start default' "$ROOT/stow/system/etc/systemd/system/virbr0-up.service" \
  || fail "virbr0-up must start libvirt default network first"
grep -q 'evolution-data-server' "$ROOT/packages/pacman.txt" \
  || fail "pacman.txt must include evolution-data-server (CalendarServer)"
grep -q 'wireless-regdb' "$ROOT/packages/pacman.txt" \
  || fail "pacman.txt must include wireless-regdb"
grep -q 'rd.driver.blacklist=nouveau' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 must blacklist nouveau on cmdline"
grep -q 'install nouveau /bin/false' "$ROOT/profiles/thinkpad-p15.sh" \
  || fail "thinkpad-p15 must block nouveau via modprobe install"
[[ -x "$ROOT/scripts/firewalld-tailscale.sh" ]] || fail "firewalld-tailscale.sh missing/not executable"
grep -q 'tailscale0' "$ROOT/scripts/firewalld-tailscale.sh" \
  || fail "firewalld-tailscale must mention tailscale0"
grep -q '^tailscale$' "$ROOT/packages/pacman.txt" \
  || fail "pacman.txt must list tailscale"
grep -q 'firewalld-tailscale.sh' "$ROOT/install.sh" \
  || fail "install.sh must call firewalld-tailscale.sh"
grep -q 'Brovi H155-381' "$ROOT/docs/fresh-install-coding-re.md" \
  || fail "fresh-install docs must mention Brovi H155-381 CPE path"
grep -q 'guest_ipv4' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali start should resolve guest IPv4 (not stale leases)"
grep -q 'domifaddr "\$VM_NAME" --source lease' "$ROOT/scripts/kali-disposable.sh" \
  || fail "guest_ipv4 must pass --source lease (not source=lease) to virsh domifaddr"
awk '/^ensure_nat_forward\(\)/,/^}/' "$ROOT/scripts/kali-disposable.sh" | grep -q 'nat+lan' \
  || fail "ensure_nat_forward must also run for nat+lan"
awk '/^net_args\(\)/,/^}/' "$ROOT/scripts/kali-disposable.sh" | grep -q "trap 'rm -f -- \"\$xml\"' EXIT" \
  || fail "net_args must clean up temporary kali-isolated XML on exit"
awk '/^net_args\(\)/,/^}/' "$ROOT/scripts/kali-disposable.sh" | grep -q 'net-define "\$xml" >&2' \
  && awk '/^net_args\(\)/,/^}/' "$ROOT/scripts/kali-disposable.sh" | grep -q 'net-start kali-isolated >&2' \
  || fail "net_args must redirect virsh output to stderr so \$(net_args) stays clean"
! awk '/^    cat >"\$ci_user" <<EOF$/,/^EOF$/' "$ROOT/scripts/kali-disposable.sh" | grep -q '^network:$' \
  || fail "cloud-init user-data must not contain invalid top-level network: key"
# save_kali_password must not leak umask 077 to caller shell
(
  _kf="$(awk '/^kali_pass_path\(\) \{/{f=1} f; f&&/^}$/{exit}' "$ROOT/scripts/kali-disposable.sh")"$'\n'
  _kf+="$(awk '/^save_kali_password\(\) \{/{f=1} f; f&&/^}$/{exit}' "$ROOT/scripts/kali-disposable.sh")"
  _kt="$(mktemp -d)"
  trap 'rm -rf "$_kt"' EXIT
  _um="$(bash -c 'umask 022; ensure_vm_dir(){ :; }; NET_MODE=nat; KALI_PASS=TestPass123456789012; KALI_PASS_FILE="$1/pw"; '"$_kf"'; save_kali_password; umask' _ "$_kt")"
  [[ "$_um" == "0022" ]] || fail "save_kali_password mutated caller umask to $_um"
  [[ "$(stat -c %a "$_kt/pw")" == "600" ]] || fail "kali-session.password mode must be 600"
)
grep -q 'PasswordAuthentication yes' "$ROOT/scripts/kali-disposable.sh" \
  || fail "cloud-init must force ssh password auth"
grep -q 'kali-linux-2026.3-cloud-genericcloud-amd64.tar.xz' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali default image URL must track current 2026.3 cloud image"
grep -q '087a9c43b6082b0a6aae666debe26c9edf6e3960a90952fc94720e755d628e58' \
  "$ROOT/scripts/kali-disposable.sh" || fail "kali image SHA-256 pin missing"
grep -q 'KALI_IMAGE_SHA256' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must honor KALI_IMAGE_SHA256 override"
grep -q 'resolve_kali_password' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must resolve guest password (no fixed kali/kali on nat/lan)"
grep -q 'kali-session.password' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must persist networked guest password under VM_DIR"
# Live URL must not 404. Pin a per-release dir: current/ drops the file on the next release.
grep -q 'cloud-images/current/' "$ROOT/scripts/kali-disposable.sh" \
  && fail "KALI_IMAGE_URL must pin cloud-images/kali-<ver>/, not current/"
_kali_url="$(grep -oE 'https://kali\.download/cloud-images/kali-[0-9.]+/kali-linux-[^"]+\.tar\.xz' \
  "$ROOT/scripts/kali-disposable.sh" | head -1)"
[[ -n "$_kali_url" ]] || fail "could not extract default KALI_IMAGE_URL"
_kali_ver="${_kali_url#*/cloud-images/kali-}"; _kali_ver="${_kali_ver%%/*}"
[[ $_kali_url == *"/kali-linux-${_kali_ver}-cloud-"* ]] || fail "Kali dir and file versions differ: $_kali_url"
unset _kali_ver
_kali_code="$(curl -fsSIL -o /dev/null -w '%{http_code}' "$_kali_url" 2>/dev/null || echo 000)"
[[ "$_kali_code" == "200" ]] || fail "default Kali image URL returned HTTP $_kali_code (want 200): $_kali_url"
unset _kali_url _kali_code
grep -q 'owner/repo:skill1,skill2' "$ROOT/scripts/install-re-skills.sh" \
  || fail "install-re-skills must document selective skill filter"
grep -q 'lib/agent-skills.sh' "$ROOT/scripts/install-re-skills.sh" \
  || fail "install-re-skills must source lib/agent-skills.sh"
grep -q 'firmware-pentest' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must probe firmware-pentest"
grep -q 'memory-forensics' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must probe memory-forensics"
grep -q 'firmware-security-reports' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must probe firmware-security-reports"
grep -q 'install-re-skills.sh' "$ROOT/install.sh" \
  || fail "install.sh must call install-re-skills.sh"
grep -q 'kali-up-nat' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-up-nat alias missing"
grep -q 'kali-up-lan' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-up-lan alias missing"
grep -q 'attach-lan' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-lan attach-lan alias missing"
grep -q 'start --isolated' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-up must default to isolated"
grep -q "mode='bridge'" "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali LAN must use macvtap bridge mode"
grep -q 'KALI_LAN_IFACE' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must honor KALI_LAN_IFACE"
grep -q '20-lan-eth1.network' "$ROOT/scripts/kali-disposable.sh" \
  || fail "cloud-init must seed eth1 DHCP for physical LAN"
grep -q 'UseDNS=no' "$ROOT/scripts/kali-disposable.sh" \
  || fail "LAN eth1 must ignore CPE DNS (npm sinkhole)"
grep -q '99-kali-public-dns.conf' "$ROOT/scripts/kali-disposable.sh" \
  || fail "guest must pin public DNS for npm/registry"
grep -q '05-kali-eth1.network' "$ROOT/scripts/kali-disposable.sh" \
  || fail "eth1 unit must sort before netplan (05-)"
grep -q 'accept-ra: false' "$ROOT/scripts/kali-disposable.sh" \
  || fail "eth1 must disable RA DNS injection"
grep -q 'UseGateway=no' "$ROOT/scripts/kali-disposable.sh" \
  || fail "eth1 must not install LAN default gateway (dual-default with NAT/wifi)"
grep -q 'use-routes: false' "$ROOT/scripts/kali-disposable.sh" \
  || fail "netplan eth1 must use-routes false"
grep -q 'ip addr flush' "$ROOT/scripts/kali-lan-host-prep.sh" \
  || fail "kali-lan-host-prep must flush RJ45 addrs so wifi keeps default"
grep -q 'lan-check' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must expose lan-check"
# kali-lan-host-prep runs as root without a password (polkit): only a physical
# wired Ethernet NIC may be flushed — never Wi-Fi, the VPN tunnel or virtual links.
_vf="$(awk '/^valid_lan_iface\(\) \{/{f=1} f; f&&/^}$/{exit}' "$ROOT/scripts/kali-lan-host-prep.sh")"
[[ -n $_vf ]] || fail "kali-lan-host-prep must define valid_lan_iface"
_sys="$(mktemp -d)"
trap 'rm -rf -- "$_sys"' EXIT
_mk() { mkdir -p "$_sys/$1"; echo "$2" >"$_sys/$1/type"; [[ $3 == dev ]] && mkdir -p "$_sys/$1/device"; [[ ${4:-} ]] && mkdir -p "$_sys/$1/$4"; return 0; }
_mk enp1s0 1 dev; _mk wlan0 1 dev wireless; _mk wlp2s0 1 dev phy80211; _mk proton0 65534 none
_mk virbr0 1 none; _mk veth0 1 none
_vl() { bash -c "$_vf"$'\n''valid_lan_iface "$1" "$2"' _ "$1" "$_sys" >/dev/null; }
_vl enp1s0 || fail "valid_lan_iface must accept a physical Ethernet NIC"
for _bad in wlan0 wlp2s0 proton0 virbr0 veth0 missing0 .. ../enp1s0 'en p' aaaaaaaaaaaaaaaa; do
  _vl "$_bad" && fail "valid_lan_iface must reject '$_bad'"
done
grep -q 'valid_lan_iface "\$IFACE" /sys/class/net' "$ROOT/scripts/kali-lan-host-prep.sh" \
  || fail "kali-lan-host-prep must validate IFACE before touching it"
unset -v _vf _bad; unset -f _mk _vl
[[ -f "$ROOT/stow/system/etc/polkit-1/rules.d/50-kali-lan-host-prep.rules" ]] \
  || fail "missing polkit rule for kali-lan-host-prep"
grep -q 'kali-lan-check\|lan-check' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-lan-check alias missing"
grep -q 'attach-lan' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must expose attach-lan command"
grep -q 'ensure_guest_lan_dhcp' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must seed eth1 DHCP on attach (not only cloud-init)"
grep -q 'restore_lan_nm' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali wipe must restore NetworkManager on LAN iface"
grep -q 'resolve_lan_iface' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must resolve/validate LAN iface"
grep -q 'managed yes' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must re-manage LAN iface after wipe"
help_out="$(bash "$ROOT/scripts/kali-disposable.sh" help 2>&1 || true)"
echo "$help_out" | grep -q 'KALI_LAN_IFACE' \
  || fail "help must document KALI_LAN_IFACE"
echo "$help_out" | grep -q 'nat+lan\|attach-lan\|--lan' \
  || fail "help must document LAN mode"
# Empty --lan-iface must fail closed (not treat /sys/class/net/ as valid).
ec=0
empty_out="$(bash "$ROOT/scripts/kali-disposable.sh" attach-lan --lan-iface "" 2>&1)" || ec=$?
[[ "$ec" -ne 0 ]] || fail "empty --lan-iface must exit non-zero"
echo "$empty_out" | grep -qiE 'non-empty|empty|LAN iface' \
  || fail "empty --lan-iface must error clearly (got: $empty_out)"
grep -q 'kali-up-lan\|kali-up-nat\|kali-lan' "$ROOT/gnome/keybindings.md" \
  || fail "keybindings summary must list kali-up-lan"
grep -q 'clamav-freshclam' "$ROOT/scripts/install-re-extras.sh" \
  || fail "install-re-extras must enable clamav-freshclam"
grep -q 'thinkpad-charge-thresholds.sh' "$ROOT/scripts/install-re-extras.sh" \
  || fail "install-re-extras must call thinkpad-charge-thresholds.sh"
grep -q 'charge_control_start_threshold' "$ROOT/scripts/thinkpad-charge-thresholds.sh" \
  || fail "thinkpad-charge-thresholds.sh must write charge_control_start_threshold"
grep -q 'SUDO_ASKPASS' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must honor SUDO_ASKPASS"
if grep -q 'cursor.general' "$ROOT/stow/vscode/.config/VSCodium/User/settings.json"; then
  fail "VSCodium settings must not contain Cursor-only keys"
fi

# Flag parsing: isolated after start
out="$(bash "$ROOT/scripts/kali-disposable.sh" 2>&1 | head -5 || true)"
echo "$out" | grep -qi 'isolated\|kali-disposable' \
  || fail "usage/help should mention disposable kali"

echo "PASS: kali-disposable.test.sh"
