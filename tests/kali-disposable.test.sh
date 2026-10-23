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
grep -q 'ufw route allow in on virbr0' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali setup/start must allow UFW forward on virbr0"
grep -q 'ip link set virbr0 up' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali must bring virbr0 admin-up for NAT"
grep -q '192.168.122.0/24' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali UFW must allow libvirt NAT subnet forward"
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
[[ -x "$ROOT/scripts/ufw-tailscale.sh" ]] || fail "ufw-tailscale.sh missing/not executable"
grep -q 'allow in on tailscale0' "$ROOT/scripts/ufw-tailscale.sh" \
  || fail "ufw-tailscale must allow tailscale0"
grep -q '^tailscale$' "$ROOT/packages/pacman.txt" \
  || fail "pacman.txt must list tailscale"
grep -q 'ufw-tailscale.sh' "$ROOT/install.sh" \
  || fail "install.sh must call ufw-tailscale.sh"
grep -q 'Brovi H155-381' "$ROOT/docs/fresh-install-coding-re.md" \
  || fail "fresh-install docs must mention Brovi H155-381 CPE path"
grep -q 'guest_ipv4' "$ROOT/scripts/kali-disposable.sh" \
  || fail "kali start should resolve guest IPv4 (not stale leases)"
grep -q 'PasswordAuthentication yes' "$ROOT/scripts/kali-disposable.sh" \
  || fail "cloud-init must force ssh password auth"
grep -q 'owner/repo:skill1,skill2' "$ROOT/scripts/install-re-skills.sh" \
  || fail "install-re-skills must document selective skill filter"
grep -q 'firmware-pentest' "$ROOT/scripts/check.sh" \
  || fail "check.sh must probe firmware-pentest"
grep -q 'firmware-security-reports' "$ROOT/scripts/check.sh" \
  || fail "check.sh must probe firmware-security-reports"
grep -q 'install-re-skills.sh' "$ROOT/install.sh" \
  || fail "install.sh must call install-re-skills.sh"
grep -q 'kali-up-nat' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-up-nat alias missing"
grep -q 'start --isolated' "$ROOT/stow/zsh/.shell-aliases" \
  || fail "kali-up must default to isolated"
grep -q 'clamav-freshclam' "$ROOT/scripts/install-re-extras.sh" \
  || fail "install-re-extras must enable clamav-freshclam"
grep -q 'charge_control_start_threshold' "$ROOT/scripts/install-re-extras.sh" \
  || fail "install-re-extras must set charge thresholds for existing BATs"
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
