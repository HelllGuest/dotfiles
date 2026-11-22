#!/usr/bin/env bash
# Slice 2b: detonation capture + lab MCP scaffolding.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/lab-detonate.sh" \
  "$ROOT/scripts/lab-mcp.sh" \
  "$ROOT/labs/lab-capture/Containerfile" \
  "$ROOT/labs/lab-capture/inetsim.conf" \
  "$ROOT/labs/lab-capture/entrypoint.sh" \
  "$ROOT/labs/lab-web/mcp-playwright.sh" \
  "$ROOT/labs/lab-web/mcp-devtools.sh" \
  "$ROOT/labs/lab-android/mcp-flutter.sh" \
  "$ROOT/labs/lab-android/mcp-adb.sh" \
  "$ROOT/labs/mcp-host.example.json"
do
  [[ -f $f ]] || fail "missing $f"
done

bash -n "$ROOT/scripts/lab-detonate.sh" || fail "bash -n lab-detonate"
bash -n "$ROOT/scripts/lab-mcp.sh" || fail "bash -n lab-mcp"
[[ -x $ROOT/scripts/lab-detonate.sh ]] || fail "lab-detonate not executable"
[[ -x $ROOT/scripts/lab-mcp.sh ]] || fail "lab-mcp not executable"

grep -q '192.168.200.1' "$ROOT/labs/lab-capture/inetsim.conf" \
  || fail "INetSim must bind malware gateway IP"
ZONE_LIB="$ROOT/scripts/lib/lab-malware-zone.sh"
[[ -f $ZONE_LIB ]] || fail "missing lib/lab-malware-zone.sh"
grep -q 'ensure_lab_malware_zone' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must call ensure_lab_malware_zone"
grep -q 'ensure_lab_malware_zone' "$ROOT/scripts/firewalld-lab-zones.sh" \
  || fail "firewalld-lab-zones must call ensure_lab_malware_zone"
grep -q 'set-target=DROP' "$ZONE_LIB" \
  || fail "lab-malware must set-target=DROP"
grep -q 'remove-masquerade' "$ZONE_LIB" \
  || fail "lab-malware must disable masquerade"
grep -q 'remove-forward-port' "$ZONE_LIB" \
  || fail "lab-malware must clear forward-ports"
grep -qE 'add-masquerade|add-forward-port' "$ZONE_LIB" \
  && fail "lab-malware zone must never enable masquerade/forward-port" || true
grep -q 'for z in block libvirt' "$ZONE_LIB" \
  || fail "lab-malware helper must unbind block+libvirt"
grep -q 'still in libvirt' "$ZONE_LIB" \
  || fail "lab-malware helper must postcheck libvirt is clear"
grep -q 'still in libvirt (runtime)' "$ZONE_LIB" \
  || fail "lab-malware helper must postcheck runtime libvirt is clear"
grep -q '_lab_fw' "$ZONE_LIB" \
  || fail "lab-malware helper must use _lab_fw (root-safe)"
grep -q 'firewalld inactive' "$ZONE_LIB" \
  || fail "lab-malware helper must warn when firewalld inactive"
grep -q 'postcondition failed' "$ZONE_LIB" \
  || fail "lab-malware helper must verify permanent bind"
grep -q 'failed to add port' "$ZONE_LIB" \
  || fail "lab-malware helper must fail if gateway ports missing"
grep -q 'virbr-malware' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must use virbr-malware"
grep -q 'PolarProxy' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must mention PolarProxy"
grep -q 'linux-define' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must define linux VM helpers"
grep -q 'windows-define' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must define windows VM helpers"

grep -q '@playwright/mcp' "$ROOT/labs/lab-web/Containerfile" \
  || fail "lab-web must install @playwright/mcp"
grep -q 'mcp-playwright' "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-mcp must launch playwright"
grep -q 'mcp-flutter' "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-mcp must launch flutter MCP"
grep -q 'android-tools' "$ROOT/labs/lab-android/Containerfile" \
  || fail "lab-android must ship android-tools (adb)"

grep -q 'lab-detonate()' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell-functions lab-detonate missing"
grep -q 'lab-mcp()' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell-functions lab-mcp missing"
grep -q 'SETUP_DETONATE' "$ROOT/scripts/configure.sh" \
  || fail "configure must expose SETUP_DETONATE"
! grep -q 'podman build.*lab-capture' "$ROOT/scripts/labs-setup.sh" \
  && grep -q 'lab-detonate.sh" setup' "$ROOT/scripts/labs-setup.sh" \
  || fail "labs-setup must delegate lab-capture build to lab-detonate.sh setup (avoid double build)"
# The build lives in a step labs-setup tolerates failing: the image must be checked after it.
_ls_setup="$(grep -n -m1 'lab-detonate.sh" setup' "$ROOT/scripts/labs-setup.sh" | cut -d: -f1)"
_ls_check="$(grep -n -m1 'sudo podman image exists localhost/lab-capture:latest' "$ROOT/scripts/labs-setup.sh" | cut -d: -f1)"
[[ -n $_ls_setup && -n $_ls_check ]] && (( _ls_check > _ls_setup )) \
  && sed -n "${_ls_check},$((_ls_check + 1))p" "$ROOT/scripts/labs-setup.sh" | grep -q 'exit 1' \
  || fail "labs-setup must stop when lab-capture is missing after lab-detonate.sh setup"
unset -v _ls_setup _ls_check
grep -qE 'sudo podman build --network=host -t localhost/lab-capture:latest' "$ROOT/scripts/lab-detonate.sh" \
  || fail "lab-detonate setup must build lab-capture in rootful podman store"
grep -q 'sudo podman image exists localhost/lab-capture:latest' "$ROOT/scripts/lab-detonate.sh" \
  || fail "lab-detonate capture-up must check rootful podman store"
grep -q 'sudo -n firewall-cmd --permanent --zone=lab-malware --list-interfaces' "$ROOT/scripts/lab-detonate.sh" \
  || fail "lab-detonate status must query permanent firewalld zone with sudo -n (no polkit hang)"
grep -q 'qemu:///system' "$ROOT/scripts/lab-detonate.sh" \
  || fail "lab-detonate virsh must use qemu:///system (libvirt group, no sudo when possible)"
grep -q '21/tcp' "$ZONE_LIB" && grep -q '25/tcp' "$ZONE_LIB" \
  || fail "lab-malware zone must allow INetSim FTP (21/tcp) and SMTP (25/tcp)"
grep -q 'LAB_CAPTURE_BIND' "$ROOT/labs/lab-capture/entrypoint.sh" \
  || fail "lab-capture entrypoint must honor LAB_CAPTURE_BIND"
grep -q -- '--cloud-init' "$ROOT/scripts/lab-detonate.sh" \
  && grep -q 'aborted without creating a broken' "$ROOT/scripts/lab-detonate.sh" \
  || fail "lab-detonate linux-define must seed cloud-init and fail closed on poweroff timeout"
grep -q 'lab-android-flutter:/opt/flutter"' "$ROOT/stow/zsh/.shell-functions" \
  && grep -q 'lab-android-flutter:/opt/flutter"' "$ROOT/scripts/lab-mcp.sh" \
  && ! grep -q 'lab-android-.*:U' "$ROOT/stow/zsh/.shell-functions" "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-android and lab-mcp must share persistent lab-android-flutter volume without per-start :U re-chown"
grep -q 'exec /usr/local/bin/mcp-playwright' "$ROOT/labs/lab-web/mcp-devtools.sh" \
  && grep -q -- '--executablePath' "$ROOT/labs/lab-web/mcp-devtools.sh" \
  || fail "mcp-devtools.sh must pass --executablePath to chrome-devtools-mcp and delegate fallback to mcp-playwright"

# No host secret mounts in MCP launcher
grep -E '(-v|--bind).*\.ssh|\.gnupg' "$ROOT/scripts/lab-mcp.sh" \
  && fail "lab-mcp must not mount secrets" || true

# inetsim.conf: only option names INetSim knows (http_port/https_port/dns_port
# and create_html_index were silently ignored with warnings).
! grep -qE '^(http_port|https_port|dns_port|create_html_index)[[:space:]]' "$ROOT/labs/lab-capture/inetsim.conf" \
  || fail "inetsim.conf uses option names INetSim does not know"
# INetSim (rootful, host network, parses malware traffic): minimal caps,
# no-new-privileges, read-only root; recreated so old broad containers go away.
_det="$ROOT/scripts/lab-detonate.sh"
_run="$(awk '/sudo podman run -d --name lab-inetsim/{f=1} f; f&&/localhost\/lab-capture:latest/{exit}' "$_det")"
for _f in '--cap-drop ALL' '--cap-add NET_BIND_SERVICE' '--cap-add SETUID' '--cap-add SETGID' '--cap-add CHOWN' \
    '--security-opt no-new-privileges' '--read-only'; do
  grep -qF -- "$_f" <<<"$_run" || fail "INetSim container must use $_f"
done
! grep -qE -- '--privileged|--cap-add (ALL|SYS_ADMIN|NET_ADMIN|DAC_OVERRIDE)' <<<"$_run" || fail "INetSim must not get broad caps"
grep -q 'sudo podman rm -f lab-inetsim' "$_det" || fail "capture-up must recreate lab-inetsim (old containers keep old caps)"
# Read-only root: every dir INetSim writes (logs, SMTP mbox, FTP uploads, HTTP
# POST bodies) must be a host volume, prepared writable without DAC_OVERRIDE.
for _d in /var/log/inetsim /var/lib/inetsim/smtp /var/lib/inetsim/ftp/upload /var/lib/inetsim/http/postdata; do
  grep -qE ":${_d}:Z\"" <<<"$_run" || fail "INetSim must mount $_d from the host (read-only root)"
  grep -qF "$_d" "$ROOT/labs/lab-capture/entrypoint.sh" || fail "entrypoint must prepare $_d"
done
grep -q 'chown root:inetsim "\$d"' "$ROOT/labs/lab-capture/entrypoint.sh" \
  && grep -q 'chmod 0775 "\$d"' "$ROOT/labs/lab-capture/entrypoint.sh" \
  || fail "entrypoint must make writable dirs root:inetsim 0775 (no DAC_OVERRIDE)"

# PolarProxy runs on the host: never install an unverified download.
_set="$(awk '/^cmd_setup\(\) \{/{f=1} f; f&&/^}$/{exit}' "$_det")"
_T="$(mktemp -d)"; mkdir -p "$_T/bin" "$_T/log"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && { printf fakezip > "$2"; shift; }; shift; done\n' >"$_T/bin/curl"
printf '#!/bin/sh\nexit 0\n' >"$_T/bin/podman"; chmod +x "$_T"/bin/*
_pp() { PATH="$_T/bin:$PATH" bash -c 'say(){ :; }; die(){ echo "DIE $*"; exit 3; }; ensure_net(){ :; }; sudo(){ :; }
  DET_DIR=$1 CAPTURE_LOG=$1 LAB_ROOT=$1 REPO_ROOT=$1 USER=x; '"$_set"'; cmd_setup' _ "$_T/log" 2>&1; }
_o="$(_pp)"; [[ ! -e $_T/log/PolarProxy ]] && grep -q 'PolarProxy skipped' <<<"$_o" \
  || fail "PolarProxy must not be fetched without POLARPROXY_SHA256: $_o"
_o="$(POLARPROXY_SHA256=$(printf '%064d' 0) _pp)" || true; grep -q 'SHA-256 mismatch' <<<"$_o" && [[ ! -e $_T/log/PolarProxy ]] \
  || fail "PolarProxy with a wrong SHA-256 must not be installed: $_o"

# Alpine detonation base image: SHA-512 pinned; a tampered download is discarded.
_fl="$(awk '/^ALPINE_IMAGES=\(/{f=1} f; f&&/^}$/{exit}' "$_det")"
grep -cE '^  "https://dl-cdn.alpinelinux.org/[^ ]+ [0-9a-f]{128}"$' <<<"$_fl" | grep -qx 2 \
  || fail "both Alpine images must carry a pinned SHA-512"
_good="$(printf fakezip | sha512sum | awk '{print $1}')"
_al() { PATH="$_T/bin:$PATH" bash -c 'say(){ :; }; die(){ echo "DIE $*"; exit 3; }; '"$_fl"'
  ALPINE_IMAGES=("https://x/a.qcow2 $2"); LINUX_BASE=$1; fetch_linux_base' _ "$_T/base.qcow2" "$1" 2>&1; }
_o="$(_al "$(printf '%0128d' 0)")" && fail "tampered Alpine image must be rejected: $_o"
[[ ! -e $_T/base.qcow2 && ! -e $_T/base.qcow2.partial ]] || fail "rejected image must not remain"
_al "$_good" >/dev/null || fail "matching Alpine image must be accepted"
[[ -f $_T/base.qcow2 ]] || fail "verified Alpine image must be installed"
# Images downloaded before pinning are re-checked, not trusted.
chmod u+w "$_T/base.qcow2"; printf 'old-unverified' >"$_T/base.qcow2"
_o="$(_al "$_good")" && fail "existing unpinned Alpine image must be refused: $_o"
grep -q 'matches no pinned' <<<"$_o" || fail "refusal must explain how to recover: $_o"
chmod u+w "$_T/base.qcow2"; printf fakezip >"$_T/base.qcow2"; _al "$_good" >/dev/null || fail "existing image matching the pin must be reused"

# capture-up starts PolarProxy only if setup recorded a verified hash for it.
_cu="$(awk '/^cmd_capture_up\(\) \{/{f=1} f; f&&/^}$/{exit}' "$_det")"
mkdir -p "$_T/cl/polarproxy"; printf '#!/bin/sh\n' >"$_T/cl/PolarProxy"; chmod +x "$_T/cl/PolarProxy"
printf '#!/bin/sh\necho started >>"%s/nohup.log"\n' "$_T" >"$_T/bin/nohup"; printf '#!/bin/sh\nexit 1\n' >"$_T/bin/pgrep"
chmod +x "$_T/bin/nohup" "$_T/bin/pgrep"
_cap() { PATH="$_T/bin:$PATH" bash -c 'say(){ :; }; die(){ echo "DIE $*"; exit 3; }; ensure_net(){ :; }; need(){ :; }; sudo(){ :; }
  CAPTURE_LOG=$1 BIND_IP=192.168.200.1; '"$_cu"'; cmd_capture_up' _ "$_T/cl" 2>&1; wait; }
_o="$(_cap)"; sleep 1; [[ ! -e $_T/nohup.log ]] && grep -q 'not installed by a verified setup' <<<"$_o" \
  || fail "unverified PolarProxy must not start: $_o"
sha256sum "$_T/cl/PolarProxy" | awk '{print $1}' >"$_T/cl/PolarProxy.verified"
# PolarProxy is started in the background (nohup … &): give the stub a moment.
_started() { local _; for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -e $_T/nohup.log ]] && return 0; sleep 0.2; done; return 1; }
_cap >/dev/null; _started || fail "verified PolarProxy must start"
rm -f "$_T/nohup.log"; printf 'tampered\n' >>"$_T/cl/PolarProxy"
_cap >/dev/null; ! _started || fail "PolarProxy changed after verification must not start"
rm -rf -- "$_T"; unset -v _det _run _f _set _T _o _fl _good _cu; unset -f _pp _al _cap _started

echo "PASS: slice2b-detonate-mcp.test.sh"
