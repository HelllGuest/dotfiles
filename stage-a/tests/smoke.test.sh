#!/usr/bin/env bash
# Smoke checks for the public T14s installer (no root / no disk).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Concatenated INSTALL_SH lives under /tmp — force local modules for live runs.
export T14S_LIB_DIR="${T14S_LIB_DIR:-$ROOT/lib}"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$ROOT/install.sh" ]] || fail "missing install.sh"
[[ -x "$ROOT/install.sh" ]] || fail "install.sh not executable"
bash -n "$ROOT/install.sh" || fail "bash -n failed"
[[ -d $ROOT/lib ]] || fail "missing lib/ (modular layout)"
shopt -s nullglob
for _lib in "$ROOT"/lib/*.sh "$ROOT"/lib/steps/*.sh "$ROOT"/lib/chroot/*.sh; do
  bash -n "$_lib" || fail "bash -n failed: $_lib"
done
unset -v _lib
# Greps search orchestrator + modules. Live runs use ORCH_SH (not the concat).
ORCH_SH="$ROOT/install.sh"
# Stages exactly as install.sh sources them; lib/steps/ must hold no more, no less.
mapfile -t STEPS < <(sed -n '/^_t14s_steps=(/,/^)$/p' "$ORCH_SH" \
  | tr ' ' '\n' | sed 's/;$//' | grep -E '^[0-9]{2}-[a-z0-9-]+\.sh$')
(( ${#STEPS[@]} > 0 )) || fail "could not read the stage list from install.sh"
[[ "$(printf '%s\n' "${STEPS[@]}")" == "$(cd "$ROOT/lib/steps" && ls -1 [0-9]*.sh)" ]] \
  || fail "install.sh stage list and lib/steps/ differ (or are not in run order)"
# curl one-liner path: _lib_path fetches lib/steps/* (subdir) from the same
# base URL into the temp dir. file:// keeps this offline.
_fetch="$(bash -c 'eval "$(awk "/^_lib_path\\(\\) *\\{/{f=1} f{print} f&&/^}\$/{exit}" "$1")"
  T14S_LIB_DIR="" T14S_BASE_URL="file://$2"; _lib_path steps/01-preflight.sh
  cmp -s "$_LIB_PATH" "$2/lib/steps/01-preflight.sh" && echo same; rm -rf -- "$T14S_LIB_FETCH_DIR"' _ "$ORCH_SH" "$ROOT")"
[[ $_fetch == same ]] || fail "curl path must fetch lib/steps/* into the fetch dir (got: $_fetch)"
unset -v _fetch
# Libraries as install.sh loads them: every lib/NN-*.sh except the chroot entry.
mapfile -t LIBS < <(sed -n '/^for _lib in/,/; do$/p' "$ORCH_SH" | tr ' ' '\n' | sed 's/;$//' \
  | grep -E '^[0-9]{2}-[a-z0-9-]+\.sh$')
[[ "$(printf '%s\n' "${LIBS[@]}")" == "$(cd "$ROOT/lib" && ls -1 [0-9]*.sh | grep -vx 80-chroot-setup.sh)" ]] \
  || fail "install.sh library list and lib/*.sh differ (or are not in load order)"
UI_SH=$(mktemp)       # the TUI layer (10-13) in load order, for tests that source it
trap 'rm -f "$UI_SH"' EXIT
_ui=()
for _l in "${LIBS[@]}"; do [[ $_l == 1[0-9]-ui*.sh ]] && _ui+=("$ROOT/lib/$_l"); done
cat "${_ui[@]}" >"$UI_SH"
unset -v _ui _l
INSTALL_SH=$(mktemp)
WIZARD_SH=$(mktemp)   # install.sh + stages in run order: the code install.sh runs
trap 'rm -f "$INSTALL_SH" "$WIZARD_SH" "${CHROOT_SH:-}" "$UI_SH"' EXIT
cat "$ROOT/install.sh" "${STEPS[@]/#/$ROOT/lib/steps/}" >"$WIZARD_SH"
# Chroot stages as lib/steps/23-install-chroot.sh deploys them; 80-chroot-setup.sh
# sources /root/t14s-lib/chroot/[0-9]*.sh in glob order, so names must sort in run order.
mapfile -t CHROOT_STAGES < <(sed -n '/^for _cs in/,/; do$/p' "$ROOT/lib/steps/23-install-chroot.sh" \
  | tr ' ' '\n' | sed 's/;$//' | grep -E '^[0-9]{2}-[a-z0-9-]+\.sh$')
(( ${#CHROOT_STAGES[@]} > 0 )) || fail "could not read the chroot stage list"
[[ "$(printf '%s\n' "${CHROOT_STAGES[@]}")" == "$(cd "$ROOT/lib/chroot" && ls -1 [0-9]*.sh)" ]] \
  || fail "deployed chroot stage list and lib/chroot/ differ (or are not in run order)"
grep -q 'for _t14s_cstage in /root/t14s-lib/chroot/\[0-9\]\*.sh; do' "$ROOT/lib/80-chroot-setup.sh" \
  || fail "80-chroot-setup.sh must source the deployed chroot stages"
CHROOT_SH=$(mktemp)   # chroot entry + stages in run order: the code arch-chroot runs
cat "$ROOT/lib/80-chroot-setup.sh" "${CHROOT_STAGES[@]/#/$ROOT/lib/chroot/}" >"$CHROOT_SH"
cat "$WIZARD_SH" "$ROOT"/lib/*.sh "${CHROOT_STAGES[@]/#/$ROOT/lib/chroot/}" >"$INSTALL_SH"

[[ -x "$ROOT/tests/host-check.sh" ]] && bash -n "$ROOT/tests/host-check.sh" \
  || fail "tests/host-check.sh missing, not executable, or bash -n failed"
! grep -qE '(^|[;&|[:space:]])(rm|mv|dd|mkfs|sgdisk|wipefs|tee|chmod|chown|sed -i|systemctl (start|stop|enable|disable|restart)) ' \
  "$ROOT/tests/host-check.sh" || fail "host-check.sh must stay read-only"

grep -q 'amd_iommu=on' "$INSTALL_SH" || fail "missing amd_iommu=on"
grep -q 'amd_pstate=active' "$INSTALL_SH" || fail "missing amd_pstate=active"
grep -q 'UCODE=amd-ucode' "$INSTALL_SH" || fail "must support amd-ucode for t14s"
grep -q 'UCODE=intel-ucode' "$INSTALL_SH" || fail "must support intel-ucode for p15"
grep -q 'HW_PROFILE' "$INSTALL_SH" || fail "must define HW_PROFILE"
grep -q 'intel_iommu=on' "$INSTALL_SH" || fail "p15 path must set intel_iommu=on"
grep -q 'firewalld' "$INSTALL_SH" || fail "must install/enable firewalld"

grep -q 'configure_firewalld' "$INSTALL_SH" || fail "must define configure_firewalld"
grep -q 'DefaultZone=drop' "$INSTALL_SH" || fail "must set firewalld DefaultZone=drop"
! grep -qE '(^|[[:space:]])(htop|btop|fastfetch|github-cli|glab)([[:space:]]|$)' "$ROOT/lib/50-packages.sh" \
  || fail "base packages must not unconditionally include htop/btop/fastfetch/github-cli/glab"
grep -q 'github-cli glab' "$ROOT/lib/chroot/10-optional-packages.sh" \
  || fail "devtools must include github-cli glab"
grep -q 'btop fastfetch' "$ROOT/lib/chroot/10-optional-packages.sh" \
  || fail "cli bundle must include btop fastfetch"
grep -q '"htop"' "$ROOT/lib/steps/11-extras.sh" \
  || fail "extras checklist must offer htop"
grep -q 'pacman -Rns --noconfirm ufw' "$ROOT/lib/70-firewall.sh" \
  || fail "configure_firewalld must remove ufw package when present"
! grep -qE '(^|[[:space:]])ufw([[:space:]]|$)' "$ROOT/lib/50-packages.sh" \
  || fail "base packages must not include ufw"
! grep -qE '\bUFW_(SYNCTHING|KDECONNECT)\b' "$WIZARD_SH" "$ROOT/lib/70-firewall.sh" \
  || fail "UFW_* answer compat must be removed (FW_* only)"
! test -e "$ROOT/install.sh.monolithic" \
  || fail "install.sh.monolithic must be deleted (modular install.sh is canonical)"
grep -q 'firewall-offline-cmd' "$INSTALL_SH" \
  || fail "chroot firewall must prefer firewall-offline-cmd"
grep -q 'T14S_LIB_DIR' "$ROOT/install.sh" || fail "orchestrator must support T14S_LIB_DIR"
grep -q "application/vnd.github.sha" "$ROOT/install.sh" \
  || fail "curl path must resolve main→SHA (Accept: application/vnd.github.sha)"
grep -q 'T14S_LIB_DIR && -z ${T14S_BASE_URL' "$ROOT/install.sh" \
  || fail "SHA resolve must run only when local lib/ is absent"
grep -qE 'T14S_REF:=69d4483' "$ROOT/install.sh" \
  && fail "must not hardcode a stale T14S_REF commit pin" || true
# Offline: checkout with lib/ beside install.sh must not need GitHub API
if command -v unshare >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  _off_tmp="$(mktemp -d /tmp/t14s-off.XXXXXX)"
  ln -s "$ROOT/lib" "$_off_tmp/lib"
  sed -n '/^# ── library loader/,/^export T14S_REF/p' "$ROOT/install.sh" \
    >"$_off_tmp/probe.sh"
  printf '%s\n' \
    '[[ -n ${T14S_LIB_DIR:-} ]] || { echo "ERR: T14S_LIB_DIR empty"; exit 1; }' \
    '[[ -f $T14S_LIB_DIR/00-common.sh ]] || { echo "ERR: missing 00-common"; exit 1; }' \
    'printf "ok offline local lib\n"' >>"$_off_tmp/probe.sh"
  _off_err="$(
    unshare -rn env -u T14S_LIB_DIR -u T14S_BASE_URL -u T14S_REF \
      PATH="$PATH" HOME=/tmp TMPDIR=/tmp \
      bash "$_off_tmp/probe.sh" 2>&1
  )" || {
    printf '%s\n' "$_off_err" >&2
    rm -rf -- "$_off_tmp"
    fail "offline checkout must resolve lib/ without GitHub API"
  }
  echo "$_off_err" | grep -q 'ok offline local lib' \
    || { rm -rf -- "$_off_tmp"; fail "offline local lib probe: $_off_err"; }
  rm -rf -- "$_off_tmp"
  unset -v _off_tmp _off_err
fi
grep -q 'is-active --quiet firewalld' "$CHROOT_SH" \
  || fail "selftest check_firewalld must prefer is-active"
grep -q '70-firewall.sh' "$WIZARD_SH" || fail "orchestrator must deploy 70-firewall.sh"
grep -q '80-chroot-setup.sh' "$WIZARD_SH" || fail "orchestrator must deploy 80-chroot-setup.sh"
grep -q 't14s_base_packages' "$INSTALL_SH" || fail "pacstrap must use t14s_base_packages"
grep -q 'rm -rf /mnt/root/t14s-lib' "$WIZARD_SH" \
  || fail "cleanup must remove /mnt/root/t14s-lib"
grep -q 'deployed lib/.*missing or empty' "$WIZARD_SH" \
  || fail "_deploy_lib must reject empty modules"
grep -q 'systemctl mask ufw' "$INSTALL_SH" \
  || fail "must mask ufw when enabling firewalld"
grep -qE '(^|[[:space:]])ufw([[:space:]]|$)' "$INSTALL_SH" \
  && grep -q 'systemctl enable.*\bufw\b' "$INSTALL_SH" \
  && fail "must not enable ufw" || true
grep -q 'ollama.service.d' "$INSTALL_SH" || fail "must ship ollama override for P15"
grep -q 'OLLAMA_HOST=127.0.0.1:11434' "$INSTALL_SH" || fail "ollama must bind localhost"

grep -q 'username cannot be empty' "$INSTALL_SH" || fail "must reject empty username"
grep -q "username cannot be 'root'" "$INSTALL_SH" || fail "must reject username root"
grep -q '^valid_username()' "$INSTALL_SH" || fail "must define valid_username"
grep -q '^valid_timezone()' "$INSTALL_SH" || fail "must define valid_timezone"
grep -q '^valid_keymap()' "$INSTALL_SH" || fail "must define valid_keymap"
grep -q 'grep -qxF --' "$INSTALL_SH" || fail "keymap match must be fixed-string (-F)"
grep -q 'getent group' "$INSTALL_SH" || fail "username must reject existing groups"
grep -q 'TZif' "$INSTALL_SH" || fail "timezone must require TZif magic"
grep -q '.install-secrets' "$INSTALL_SH" || fail "must use secrets file (not env passwords)"
grep -q 'USER_PASS=' "$INSTALL_SH" && grep -q 'arch-chroot /mnt env' "$INSTALL_SH" \
  && grep 'arch-chroot /mnt env' -A3 "$INSTALL_SH" | grep -q 'USER_PASS=' \
  && fail "must not pass USER_PASS via arch-chroot env" || true

grep -q 'com.google.Chrome' "$INSTALL_SH" \
  && grep -A2 'for app in' "$INSTALL_SH" | grep -q 'com.google.Chrome' \
  && fail "Chrome must not be in chroot flatpak loop" || true

grep -q 'LOGIN_HINT' "$INSTALL_SH" || fail "finish banner must gate on DESKTOP"
grep -q 'AuthenticAMD' "$INSTALL_SH" || fail "must gate T14s on AuthenticAMD"
grep -q 'GenuineIntel' "$INSTALL_SH" || fail "must gate P15 on GenuineIntel"
grep -qF '21C[QR]' "$INSTALL_SH" || fail "DMI check must use anchored 21C[QR]"
grep -qF '20SU' "$INSTALL_SH" || fail "DMI check must detect P15 20SU"
grep -q 'target profile: T14s Gen 3 AMD' "$INSTALL_SH" \
  || fail "must print T14s target profile"
grep -q 'target profile: P15 Gen 1' "$INSTALL_SH" \
  || fail "must print P15 target profile"
grep -q 'HW_PROFILE=t14s' "$INSTALL_SH" || fail "must set HW_PROFILE=t14s on 21CQ/21CR"
grep -q 'HW_PROFILE=p15' "$INSTALL_SH" || fail "must set HW_PROFILE=p15 on 20SU"
grep -q 'vulkan-radeon' "$INSTALL_SH" || fail "must pacstrap vulkan-radeon"
grep -q 'mesa' "$INSTALL_SH" || fail "must pacstrap mesa"
grep -q 'libva-utils' "$INSTALL_SH" || fail "must install libva-utils with GNOME"
grep -q '_libva=radeonsi' "$INSTALL_SH" \
  || fail "must default LIBVA to radeonsi for T14s"
grep -q '_libva=iHD' "$INSTALL_SH" \
  || fail "must set LIBVA iHD for P15"
grep -q 'LIBVA_DRIVER_NAME=%s' "$INSTALL_SH" \
  || fail "must write LIBVA_DRIVER_NAME from HW_PROFILE"
grep -q '61-gdm-wayland.rules' "$INSTALL_SH" \
  || fail "must install 61-gdm-wayland.rules for AMD 0x1002/0x1681"
# GDM hardening: check the actual heredoc bodies, not just any line in install.sh.
_heredoc() { awk -v t="$1" 'index($0, "cat > " t " <<\x27EOF\x27"){f=1;next} f&&/^EOF$/{exit} f' "$INSTALL_SH"; }
_gdmconf="$(_heredoc /etc/gdm/custom.conf)"
grep -qx 'DisallowTCP=true' <<<"$_gdmconf" || fail "gdm custom.conf must set DisallowTCP=true"
grep -qx 'AutomaticLoginEnable=false' <<<"$_gdmconf" || fail "gdm custom.conf must disable autologin"
awk '/^\[xdmcp\]/{s=1;next} /^\[/{s=0} s&&/^Enable=false$/{f=1} END{exit !f}' <<<"$_gdmconf" \
  || fail "gdm custom.conf must disable XDMCP"
_greeter="$(_heredoc /etc/dconf/db/gdm.d/00-login-screen)"
grep -qx 'disable-user-list=true' <<<"$_greeter" || fail "GDM greeter dconf must hide the user list"
# idle-delay is an org.gnome.desktop.session key; under login-screen it is ignored.
awk '/^\[/{s=$0} /^idle-delay=/{print s}' <<<"$_greeter" | grep -qx '\[org/gnome/desktop/session\]' \
  || fail "greeter idle-delay must live under [org/gnome/desktop/session]"
grep -q 'enable-fingerprint-authentication=false' "$INSTALL_SH" \
  || fail "greeter fingerprint auth must be disabled on SKIP_THINKPAD_HW"
if command -v dconf >/dev/null; then
  _d="$(mktemp -d)"
  printf '%s\n' "$_greeter" >"$_d/00"
  dconf compile "$_d/db" "$_d" || fail "GDM greeter dconf keyfile must compile"
  rm -rf "$_d"
fi
grep -q 'check gdm_dconf' "$INSTALL_SH" || fail "t14s-selftest must check the compiled GDM dconf db"
# The GDM block must sit inside the DESKTOP guard (headless installs have no gdm).
awk '/^if yn_on "\$DESKTOP"; then$/{d=1} d&&/^fi$/{d=0} /cat > \/etc\/gdm\/custom\.conf/{print d+0; exit}' "$INSTALL_SH" \
  | grep -qx 1 || fail "GDM config must be written inside the DESKTOP guard"
grep -q 'gdm.service.d/override.conf' "$INSTALL_SH" \
  || fail "must install GDM systemd override.conf"
grep -q '99-wayland.conf' "$INSTALL_SH" \
  || fail "must install /etc/environment.d/99-wayland.conf"
grep -q 'x86-64-v3' "$INSTALL_SH" \
  || fail "makepkg t14s.conf must tune for Zen 3+ x86-64-v3"
grep -q 'GOAMD64="\${GOAMD64:-v3}"' "$INSTALL_SH" \
  || fail "makepkg t14s.conf must set GOAMD64=v3"
grep -q 's2idle.conf' "$INSTALL_SH" \
  || fail "must install /etc/systemd/sleep.conf.d/s2idle.conf"
grep -q 'thinkpad-lid.conf' "$INSTALL_SH" \
  || fail "must install /etc/systemd/logind.conf.d/thinkpad-lid.conf"
grep -q '61-thinkpad-charge-limit.rules' "$INSTALL_SH" \
  || fail "must install 61-thinkpad-charge-limit.rules (UPower CHARGE_LIMIT=70,80)"
grep -q 'ENV{CHARGE_LIMIT}="70,80"' "$INSTALL_SH" \
  || fail "61-thinkpad-charge-limit.rules must export CHARGE_LIMIT=70,80"
grep -q '71-thinkpad-t14s-touchpad-wakeup.rules' "$INSTALL_SH" \
  || fail "must install 71-thinkpad-t14s-touchpad-wakeup.rules"
grep -q 'i2c-ELAN0678:\*|i2c-SYNA8018:\*' "$INSTALL_SH" \
  || fail "touchpad wakeup rule must match ELAN0678 and SYNA8018"
# Functional check: extract /etc/makepkg.conf.d/t14s.conf and /usr/local/bin/t14s-selftest
_mkconf="$(awk '/^cat > \/etc\/makepkg\.conf\.d\/t14s\.conf <<\x27EOF\x27$/{f=1;next} f&&/^EOF$/{exit} f' "$INSTALL_SH")"
[[ -n $_mkconf ]] || fail "could not extract makepkg.conf.d/t14s.conf heredoc"
bash -c '
  set -euo pipefail
  CFLAGS="-march=x86-64 -mtune=generic -O2"
  CXXFLAGS="-march=x86-64 -mtune=generic -O2"
  RUSTFLAGS="-C opt-level=2"
  eval "$1"
  [[ $CFLAGS == "-march=x86-64-v3 -O2" ]] || exit 11
  [[ $CXXFLAGS == "-march=x86-64-v3 -O2" ]] || exit 12
  [[ $RUSTFLAGS == "-C opt-level=2 -C target-cpu=x86-64-v3" ]] || exit 13
  [[ $GOAMD64 == "v3" ]] || exit 14
' _ "$_mkconf" || fail "makepkg.conf.d/t14s.conf runtime flag rewrite failed"
unset -v _mkconf
_stbody="$(awk '/cat > \/usr\/local\/bin\/t14s-selftest <<\x27ST\x27$/{f=1;next} f&&/^ST$/{exit} f' "$INSTALL_SH")"
[[ -n $_stbody ]] || fail "could not extract t14s-selftest heredoc"
bash -n <<<"$_stbody" || fail "t14s-selftest bash -n failed"
grep -qE '^check .*\|' <<<"$_stbody" \
  && fail "t14s-selftest must not pipe check() into another command (subshell loses ok/bad counter)" || true
unset -v _stbody
grep -q 'thinkpad-charge-thresholds.conf' "$INSTALL_SH" \
  || fail "must install charge threshold tmpfiles"
grep -q 'CHARGE_START="\${CHARGE_START:-70}"' "$INSTALL_SH" \
  || fail "05-policy.sh must default CHARGE_START to 70"
grep -q 'CHARGE_END="\${CHARGE_END:-80}"' "$INSTALL_SH" \
  || fail "05-policy.sh must default CHARGE_END to 80"
grep -q 'charge_control_start_threshold - - - - 70' "$INSTALL_SH" \
  || fail "charge tmpfiles must set start 70"
grep -q 'charge_control_end_threshold - - - - 80' "$INSTALL_SH" \
  || fail "charge tmpfiles must set end 80"
grep -q 'thinkpad-charge-thresholds.service' "$INSTALL_SH" \
  || fail "must ship charge oneshot after multi-user"
grep -q 'After=multi-user.target' "$INSTALL_SH" \
  || fail "charge oneshot must After=multi-user.target"
grep -q 'apply-charge-thresholds.sh' "$INSTALL_SH" \
  || fail "must install apply-charge-thresholds.sh"
grep -qF '/usr/local/lib/thinkpad/apply-charge-thresholds.sh' "$INSTALL_SH" \
  || fail "charge apply path must be /usr/local/lib/thinkpad/ (dotfiles parity)"
grep -q '/usr/local/lib/t14s/' "$INSTALL_SH" \
  && fail "must not use legacy /usr/local/lib/t14s/" || true
# set -e / ERR: top-level functions must not end on a bare failing && list.
python3 - "$INSTALL_SH" <<'PY' || fail "top-level function ends with failing && (set -e hazard)"
from pathlib import Path
import re, sys
t = Path(sys.argv[1]).read_text().splitlines()
# Stop before chroot deploy (chroot helpers live in lib/80, different rules).
cut = next((i for i, ln in enumerate(t) if "80-chroot-setup.sh" in ln and "deploy" in ln.lower() or ln.strip().endswith("80-chroot-setup.sh")), len(t))
# Prefer explicit deploy marker if present.
for i, ln in enumerate(t):
    if "_deploy_lib 80-chroot-setup.sh" in ln or ln.startswith("cat > /mnt/root/chroot-setup.sh"):
        cut = i
        break
t = t[:cut]
bad = []
i = 0
while i < len(t):
    m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\(\)\s*\{', t[i])
    if not m:
        i += 1
        continue
    name, depth, start = m.group(1), 0, i
    for j in range(i, len(t)):
        depth += t[j].count('{') - t[j].count('}')
        if j > i and depth <= 0:
            last = None
            for ln in reversed(t[start:j]):
                s = ln.strip()
                if not s or s.startswith('#'):
                    continue
                last = s
                break
            # Hazard: last stmt is &&-list without || / return (function status = 1).
            if (last and '&&' in last and '||' not in last
                    and not last.startswith('return')
                    and not re.search(r'&&\s*return\b', last)):
                bad.append(f'{name}:{start+1} last={last}')
            i = j + 1
            break
    else:
        i += 1
if bad:
    raise SystemExit('&&-tailed functions:\n  ' + '\n  '.join(bad))
print('ok no &&-tailed top-level functions')
PY
grep -qF '_host_short=${HOSTNAME%%.*}' "$INSTALL_SH" \
  || fail "FQDN hostname must derive short label"
grep -qF '127.0.1.1 ${HOSTNAME} ${_host_short}' "$INSTALL_SH" \
  || fail "FQDN hosts entry must list FQDN before short name"

# reflector rate-sort must be concurrency + time bounded, or a few dead mirrors
# serialize into a multi-minute blank screen
grep -q -- '--sort rate' "$INSTALL_SH" || fail "reflector rate sort missing"
grep -q 'timeout [0-9]* reflector' "$INSTALL_SH" || fail "live reflector run must have an overall timeout"
grep -q -- '--threads 5' "$INSTALL_SH" || fail "reflector ranking must be concurrent"

# TUI: backend bootstrap + semantic helpers must exist, plus plain fallback
grep -q '### Controls' "$ROOT/README.md" || fail "README must document TUI controls"
grep -q '### Safety model' "$ROOT/README.md" || fail "README must document the safety model"
grep -q 'command -v whiptail' "$INSTALL_SH" || fail "must detect whiptail"
grep -q 'command -v dialog' "$INSTALL_SH" || fail "must detect/install dialog"
grep -q -- '--passwordbox' "$INSTALL_SH" || fail "passwords must use a TUI prompt"
grep -q 'ui_yesno' "$INSTALL_SH" || fail "choices must use ui_yesno"
grep -q 'T14S_DRYRUN' "$INSTALL_SH" || fail "must keep a dry-run stop point"
grep -q 'run_progress' "$INSTALL_SH" || fail "must define run_progress for live pacstrap output"
grep -q 'run_gauge "pacstrap' "$INSTALL_SH" \
  || fail "pacstrap must use run_gauge (percent gauge, live on plain TTY)"
grep -q 'run_gauge "chroot config' "$INSTALL_SH" \
  || fail "chroot must use run_gauge"

# progress_filter: pacman/curl/stage lines → monotonic gauge percent per band
python3 - "$CHROOT_SH" <<'PY' || fail "chroot stage markers must be ascending, 0→100, contiguous"
import re, sys
t = open(sys.argv[1]).read()
st = [(int(a), int(b)) for a, b in re.findall(r'^stage (\d+) (\d+) "', t, re.M)]
assert len(st) >= 8, st
assert st[0][0] == 0 and st[-1][1] == 100, st
for (a, b), (c, d) in zip(st, st[1:]):
    assert a < b and b == c, (a, b, c, d)
print('ok chroot stage markers')
PY
_pf_out="$(bash -c '
  eval "$(sed -n "/^progress_filter()/,/^}/p" "$1")"
  LOG=/dev/null W=72
  { printf "Packages (2) a-1 b-1\n"
    printf " a-1-x86_64.pkg.tar.zst downloading...\n"
    printf " a-1-x86_64.pkg.tar.zst downloading...\n"
    printf "(1/2) checking keys in keyring\n(2/2) installing b\n(1/1) Updating initcpios...\n"
    printf "@@STAGE 34 72 GNOME\n(100/100) installing gnome-shell\n"
  } | progress_filter 0 100 gauge step | awk "p==\"XXX\" && /^[0-9]+\$/{print} {p=\$0}"
' _ "$INSTALL_SH")"
[[ "$(printf '%s\n' "$_pf_out" | tr '\n' ' ')" == "0 20 40 45 95 99 34 70 " ]] \
  || fail "progress_filter percents wrong: $(printf '%s\n' "$_pf_out" | tr '\n' ' ')"
echo "ok progress_filter percents"

# progress_filter edge cases: VerbosePkgLists header, footer hint on every
# caption, plain text mode (raw passthrough + stage marker rewrite).
_pf_edge="$(bash -c '
  eval "$(sed -n "/^progress_filter()/,/^}/p" "$1")"
  LOG=/dev/null W=72
  printf "Package (2)  New Version\n b-1-any.pkg.tar.zst downloading...\n" \
    | progress_filter 0 100 gauge step "HINT-LINE" | tr "\n" "|"
  echo
  printf "@@STAGE 34 72 GNOME\nraw line\n" | progress_filter 0 100 text step
' _ "$INSTALL_SH")"
grep -Fq '|20|step||working…|downloading packages (1/2)||HINT-LINE|XXX|' <<<"$_pf_edge" \
  || fail "progress_filter: VerbosePkgLists header or caption hint broken: $_pf_edge"
[[ $(grep -c 'HINT-LINE' <<<"$(tr '|' '\n' <<<"$_pf_edge")") == 2 ]] \
  || fail "progress_filter: hint must be on every gauge caption"
grep -qx '>> \[34%\] GNOME' <<<"$_pf_edge" || fail "text mode must rewrite @@STAGE markers"
grep -qx 'raw line' <<<"$_pf_edge" || fail "text mode must pass raw lines through"
echo "ok progress_filter edge cases"

# run_gauge end-to-end against a stub dialog in a pty: --gauge args, start %,
# caption stream, and the command's exit status passed back.
if command -v script >/dev/null 2>&1; then
  _rg="$(mktemp -d)"
  mkdir -p "$_rg/bin"
  cat >"$_rg/bin/dialog" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$RG_DIR/args"
cat >"$RG_DIR/stdin"
STUB
  chmod +x "$_rg/bin/dialog"
  cat >"$_rg/run.sh" <<'RUN'
set -euo pipefail
src=$1
# First top-level definition only (chroot heredoc redefines say() inline).
for fn in say _tty ui_utf8 ui_bar ui_backtitle tui progress_banner progress_filter run_gauge; do
  eval "$(awk -v f="$fn" '
    !p && index($0, f "()") == 1 { p = 1; if ($0 ~ /\}[[:space:]]*$/) { print; exit } }
    p { print } p && /^\}/ { exit }' "$src")"
done
UI=dialog LOG="$RG_DIR/log" W=72 LOGGING=0 APP_TITLE=t c0= cB=
rc=0
run_gauge "step label" 34 72 bash -c 'printf "(1/2) installing a\n"; exit 7' || rc=$?
echo "rc=$rc" >"$RG_DIR/rc"
RUN
  RG_DIR="$_rg" PATH="$_rg/bin:$PATH" script -qec "bash $_rg/run.sh $INSTALL_SH" /dev/null \
    >/dev/null 2>&1 || true
  grep -qx 'rc=7' "$_rg/rc" 2>/dev/null || fail "run_gauge must return the command exit status"
  grep -qx -- '--gauge' "$_rg/args" || fail "run_gauge must call dialog --gauge"
  [[ $(tail -n 3 "$_rg/args" | tr '\n' ' ') == "14 72 34 " ]] \
    || fail "run_gauge geometry/start % wrong: $(tail -n 3 "$_rg/args" | tr '\n' ' ')"
  grep -qx 'installing a (1/2)' "$_rg/stdin" || fail "run_gauge must stream captions to dialog"
  grep -q 'tail -f' "$_rg/stdin" || fail "run_gauge captions must keep the tail -f hint"
  grep -qx '(1/2) installing a' "$_rg/log" || fail "run_gauge must append raw output to LOG"
  rm -rf "$_rg"
  echo "ok run_gauge stub dialog"
else
  echo "SKIP: run_gauge pty test (no script(1))"
fi

# Palette readability on the 8-colour Linux console (ISO):
#   dialogrc: no BLACK foreground with highlight ON (renders dark grey)
#   newt:     no bright/"yellow"/"white" background; only S-Lang colour names
python3 - "$INSTALL_SH" <<'PY' || fail "TUI palette breaks console readability rules"
import re, sys
t = open(sys.argv[1]).read()
bad = re.findall(r'\(BLACK,[A-Z]+,ON\)', t)
assert not bad, f'bold BLACK fg: {bad}'
names = {'black','red','green','brown','blue','magenta','cyan','lightgray','gray',
         'brightred','brightgreen','yellow','brightblue','brightmagenta','brightcyan','white',''}
dim_bg = {'black','red','green','brown','blue','magenta','cyan','lightgray',''}
for blk in re.findall(r"^NEWT_COLORS_[A-Z]+='\n(.*?)\n'", t, re.S | re.M):
    for ln in blk.splitlines():
        k, _, v = ln.partition('=')
        fg, _, bg = v.partition(',')
        assert fg in names and bg in names, f'unknown S-Lang colour: {ln}'
        if k not in ('emptyscale', 'fullscale'):
            assert bg in dim_bg, f'bright background (console cannot show): {ln}'
assert 'NEWT_COLORS="${NEWT_COLORS_BASE}${TUI_NEWT:-}"' in t, 'severity overlays must extend base'
print('ok TUI palette rules')
PY
grep -q 'ui_view_log' "$INSTALL_SH" || fail "must offer ui_view_log"
# The install runs unattended after the Erase confirm: long steps never stop
# for input (a menu after each gauge left installs waiting); the log is
# offered once, at the very end.
for _f in run_gauge run_progress; do
  awk "/^${_f}\\(\\)/,/^}/" "$UI_SH" | grep -q 'ui_offer_log' \
    && fail "$_f must not stop for input after a long step"
done
unset -v _f
[[ $(grep -v '^[[:space:]]*#' "$WIZARD_SH" | grep -c 'ui_offer_log') == 1 ]] \
  && tail -n 3 "$ROOT/lib/steps/30-finish.sh" | grep -q '^ui_offer_log' \
  || fail "the log offer must appear once, at the end of 30-finish.sh"
# ui_offer_log behaviour: unattended and plain UI skip it; Abort/no terminal
# exits; [log] opens the viewer and returns to the menu; exit leaves.
_ol() {  # UI NONINTERACTIVE menu-answers... -> "menus=N views=N rc=N" (a loop times out)
  timeout 10 bash -c '
    eval "$(awk "/^(ui_offer_log|ui_nav_special)\\(\\) *\\{/{f=1} f{print} f&&/^}\$/{f=0}" "$1")"
    UI=$2 NONINTERACTIVE=$3; shift 3
    c=$(mktemp); v=$(mktemp); answers=("$@")
    ui_menu() { local n; n=$(wc -l <"$c"); echo >>"$c"
      (( n < ${#answers[@]} )) || return 1
      [[ ${answers[n]} == ABORT ]] && return 1; printf %s "${answers[n]}"; }
    ui_view_log() { echo >>"$v"; }; ui_console_help() { :; }
    rc=0; ui_offer_log "done" || rc=$?
    echo "menus=$(wc -l <"$c") views=$(wc -l <"$v") rc=$rc"; rm -f "$c" "$v"' _ "$UI_SH" "$@"
}
[[ $(_ol whiptail 1 exit) == "menus=0 views=0 rc=0" ]] || fail "ui_offer_log must not prompt unattended"
[[ $(_ol plain 0 exit) == "menus=0 views=0 rc=0" ]] || fail "ui_offer_log must not prompt twice on the plain UI"
[[ $(_ol whiptail 0 ABORT) == "menus=1 views=0 rc=0" ]] || fail "Abort at the final menu must exit cleanly"
[[ $(_ol whiptail 0 log log exit) == "menus=3 views=2 rc=0" ]] || fail "[log] must show the log and return to the menu"
[[ $(_ol dialog 0) == "menus=1 views=0 rc=0" ]] || fail "no terminal (menu fails) must exit, not loop"
unset -f _ol
# ui_utf8: one locale test for bars and banners, any UTF-8 spelling.
for _l in C.UTF-8 en_US.UTF-8 en_US.utf8 C.utf8; do
  bash -c 'eval "$(sed -n "/^ui_utf8()/,/^}/p" "$1")"; LC_ALL=$2 ui_utf8' _ "$UI_SH" "$_l" \
    || fail "ui_utf8 must accept $_l"
done
bash -c 'eval "$(sed -n "/^ui_utf8()/,/^}/p" "$1")"; LC_ALL=C ui_utf8' _ "$UI_SH" && fail "ui_utf8 must reject C"
[[ $(grep -c 'LC_CTYPE' "$UI_SH") == 1 ]] || fail "locale detection must live only in ui_utf8"
unset -v _l
# Help text must match what long steps really show.
grep -q 'Live steps (pacstrap/chroot): dialog progress box; whiptail/plain stream' "$UI_SH" \
  && fail "console help still says whiptail streams pacstrap/chroot (it shows a gauge)"
# progress_banner (plain console) must not draw a bar it never updates.
awk '/^progress_banner\(\)/,/^}/' "$UI_SH" | grep -q 'ui_bar' \
  && fail "progress_banner must not show a static progress bar"
grep -q 'ui_checklist' "$INSTALL_SH" || fail "must offer ui_checklist multi-select"
grep -q 'ui_info' "$INSTALL_SH" || fail "must define ui_info"
grep -q 'ui_warn' "$INSTALL_SH" || fail "must define ui_warn"
grep -q 'ui_error' "$INSTALL_SH" || fail "must define ui_error"
grep -q 'ui_critical' "$INSTALL_SH" || fail "must define ui_critical"
grep -q 'ui_ok' "$INSTALL_SH" || fail "must define ui_ok"
grep -q 'write_dialogrc' "$INSTALL_SH" || fail "must ship dialogrc theme"
grep -q 'DIALOG_RC_CRITICAL' "$INSTALL_SH" || fail "must ship per-severity dialogrc"
grep -q 'NEWT_COLORS_CRITICAL' "$INSTALL_SH" || fail "must ship severity NEWT palettes"
grep -q 'NEWT_COLORS_OK' "$INSTALL_SH" || fail "must ship green OK NEWT palette"
grep -q 'msg_height' "$INSTALL_SH" || fail "must scale msgbox height with content"
grep -q 'TUI_KEEP_STDIN=1' "$INSTALL_SH" || fail "progressbox must keep pipe stdin"
grep -q 'ui_critical' "$INSTALL_SH" && grep -A20 '^die()' "$INSTALL_SH" | grep -q 'ui_critical' \
  || fail "die must show ui_critical"
grep -q '\[severity\]' "$INSTALL_SH" || fail "ui_yesno must document severity arg"
grep -q '\[ERROR\]' "$INSTALL_SH" || fail "plain yesno must label error distinctly from critical"
grep -q 'log "View install log" off' "$INSTALL_SH" || fail "checklist must offer log entry"
grep -q -- '--colors' "$INSTALL_SH" || fail "dialog must enable --colors"
grep -q 'Message severity' "$ROOT/README.md" || fail "README must document message severity"
grep -q 'per-severity' "$ROOT/README.md" || fail "README must note per-severity dialogrc/NEWT"
grep -q 'ui_step' "$INSTALL_SH" || fail "wizard must set ui_step progress"
grep -q 'ui_backtitle' "$INSTALL_SH" || fail "tui must use dynamic backtitle"
grep -q '^ui_bar()' "$INSTALL_SH" || fail "must define ui_bar for step/gauge strips"
grep -q 'ui_bar' "$INSTALL_SH" && awk '/^ui_backtitle\(\)/,/^}/' "$INSTALL_SH" | grep -q 'ui_bar' \
  || fail "ui_backtitle must show a step bar via ui_bar"
! grep -q 'ui_bar' "$ROOT/lib/steps/02-welcome.sh" \
  || fail "welcome must not repeat the step bar (the backtitle shows it)"
# The step bar counts completed steps: 11/11 (the install) is not 100% yet.
_bt="$(bash -c 'eval "$(sed -n "/^ui_utf8()/,/^}/p;/^ui_bar()/,/^}/p;/^ui_backtitle()/,/^}/p" "$1")"
  LC_ALL=C APP_TITLE=T TUI_STEPS=11 TUI_STEP=11 TUI_STEP_NAME=Install; ui_backtitle' _ "$UI_SH")"
[[ $_bt == 'T · [#########-] 11/11 · Install' ]] || fail "step bar at 11/11 must show 91%, got: $_bt"
unset -v _bt
# ui_bar shapes (UTF-8 + C locale)
_bar_c="$(bash -c 'eval "$(sed -n "/^ui_utf8()/,/^}/p;/^ui_bar()/,/^}/p" "$1")"; LC_ALL=C ui_bar 40 10' _ "$INSTALL_SH")"
[[ $_bar_c == '[####------]' ]] || fail "ui_bar C 40%: got $_bar_c"
_bar_u="$(bash -c 'eval "$(sed -n "/^ui_utf8()/,/^}/p;/^ui_bar()/,/^}/p" "$1")"; LC_ALL=en_US.UTF-8 ui_bar 50 10' _ "$INSTALL_SH")"
[[ $_bar_u == '[█████░░░░░]' ]] || fail "ui_bar UTF-8 50%: got $_bar_u"
unset -v _bar_c _bar_u
grep -q 'gauge_color = (CYAN,BLUE,ON)' "$INSTALL_SH" \
  || fail "dialog gauge fill must be CYAN on BLUE"
grep -q 'ui_fold' "$INSTALL_SH" || fail "messages must fold prose"
grep -q '_tui_btns' "$INSTALL_SH" || fail "must set Next/Abort/Erase button labels"
grep -q 'erase_yesno' "$INSTALL_SH" || fail "wipe confirms need erase_yesno buttons"
grep -q 'critical_yesno' "$INSTALL_SH" || fail "hard gates need critical_yesno buttons"
grep -q 'TUI_STEPS=11' "$INSTALL_SH" || fail "wizard must declare 11 steps"
grep -q 'not color-only' "$ROOT/README.md" || fail "README must note a11y severity badges"
grep -q 'Next' "$ROOT/README.md" || fail "README Controls must document Next button"
grep -q 'ui_yesno` only' "$ROOT/README.md" \
  || fail "README must mark erase/critical confirms as ui_yesno-only"
grep -q 'NONINTERACTIVE: skipping welcome TUI' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must skip welcome TUI"
grep -q 'choose 1-\$i (empty=1)' "$INSTALL_SH" \
  || fail "plain menu must not claim Ctrl-C is Esc"
grep -q -- '--progressbox' "$INSTALL_SH" || fail "dialog progressbox for live steps"
# Button roles: wipe uses erase; DMI/hook hard gates use critical (not Erase).
# Non-spanning parse: one quoted prompt per ui_yesno (no nested " inside prompts).
python3 - "$INSTALL_SH" <<'PY' || fail "yesno button roles must separate erase vs continue"
from pathlib import Path
import re, sys
t = Path(sys.argv[1]).read_text()
# dialog + whiptail labels
for backend, yes, flag in (
    ("dialog", "Erase", "--yes-label"),
    ("dialog", "Continue", "--yes-label"),
    ("whiptail", "Erase", "--yes-button"),
    ("whiptail", "Continue", "--yes-button"),
):
    role = "erase_yesno" if yes == "Erase" else "critical_yesno"
    pat = rf"{backend}/{role}\)\s+_btns=\({flag} {yes}"
    assert re.search(pat, t), f"missing {backend} {role} → {yes}"
# plain [ERASE] distinct from [CRITICAL]
assert re.search(r"erase\)\s+tag=.*\[ERASE\]", t), "plain [ERASE] tag"
assert re.search(r"critical\)\s+tag=.*\[CRITICAL\]", t), "plain [CRITICAL] tag"
# One call == one "..." prompt; [^"]* allows newlines inside the quotes.
calls = re.findall(
    r'ui_yesno\s+"([^"]*)"\s+(yes|no)\s+(critical|erase|warn|error|info)\b',
    t,
    flags=re.S,
)
erase = [(p, d, s) for p, d, s in calls if s == "erase"]
critical = [(p, d, s) for p, d, s in calls if s == "critical"]
assert len(erase) == 3, (
    f"expected exactly 3 erase confirms, got {len(erase)}: {[p[:40] for p, _, _ in erase]}"
)
assert all(d == "no" for _, d, _ in erase), "erase confirms must default no"
assert any(p.startswith("ERASE $DISK now?") for p, _, _ in erase), "AUTO disk erase"
assert any("Proceed with these partitions" in p for p, _, _ in erase), "MANUAL proceed erase"
assert any("will be ERASED" in p for p, _, _ in erase), "final start erase"
assert "Hardware profile" in t and "ThinkPad P15 Gen 1" in t, "must offer HW_PROFILE radio"
warns = [(p, d, s) for p, d, s in calls if s == "warn"]
assert any("AuthenticAMD" in p for p, _, _ in warns), "T14s CPU mismatch must use warn"
assert any("GenuineIntel" in p for p, _, _ in warns), "P15 CPU mismatch must use warn"
assert any("trust the URL" in p for p, _, _ in critical), "hook must use critical"
proceed = [c for c in calls if "Proceed with these partitions" in c[0]]
assert len(proceed) == 1 and proceed[0][2] == "erase", proceed
# ui_msg must not grow an erase case branch (erase is ui_yesno-only)
msg = t[t.find("ui_msg()"): t.find("ui_info()")]
assert not re.search(r"(?m)^\s*erase\)", msg), "ui_msg must not handle erase severity"
# False-green regression: spanning .*? finder still sees Proceed after severity flip
poison = t.replace(
    '" no erase',
    '" no critical',
    1,
)  # flips AUTO disk erase first — real parser must fail count
poison_calls = re.findall(
    r'ui_yesno\s+"([^"]*)"\s+(yes|no)\s+(critical|erase|warn|error|info)\b',
    poison,
    flags=re.S,
)
poison_erase = [c for c in poison_calls if c[2] == "erase"]
assert len(poison_erase) == 2, "parser must drop flipped AUTO erase"
# Spanning finder stays green on Proceed→critical + extra erase (document why we avoid it)
span_src = t.replace(
    'EFI   $EFI_PART  ${efi_mb}MB  ${_proc_efi_lbl}" no erase',
    'EFI   $EFI_PART  ${efi_mb}MB  ${_proc_efi_lbl}" no critical',
    1,
)
span_src += '\nui_yesno "extra" no erase\n'
span_hit = re.findall(r'ui_yesno\s+".*?"\s+no\s+erase\b', span_src, flags=re.S)
assert any("Proceed with these partitions" in s for s in span_hit), (
    "expected spanning false-green; if this fails, delete this guard"
)
print("ok yesno button roles")
PY
# Live backends (when installed): confirm button flags exist on the binary.
if command -v dialog >/dev/null 2>&1; then
  dialog --help 2>&1 | grep -q -- '--yes-label' \
    || fail "installed dialog missing --yes-label"
  dialog --help 2>&1 | grep -q -- '--ok-label' \
    || fail "installed dialog missing --ok-label"
fi
if command -v whiptail >/dev/null 2>&1; then
  whiptail --help 2>&1 | grep -q -- '--yes-button' \
    || fail "installed whiptail missing --yes-button"
  whiptail --help 2>&1 | grep -q -- '--ok-button' \
    || fail "installed whiptail missing --ok-button"
fi
# progressbox path must not force </dev/tty on the same invocation
python3 - "$INSTALL_SH" <<'PY' || fail "progressbox must use TUI_KEEP_STDIN around tui"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
i = t.find('tui --progressbox')
assert i > 0, "progressbox call missing"
window = t[max(0, i - 250):i + 80]
assert "TUI_KEEP_STDIN=1" in window, "TUI_KEEP_STDIN=1 missing before progressbox"
assert "TUI_KEEP_STDIN=0" in t[i:i + 120], "TUI_KEEP_STDIN=0 missing after progressbox"
print("ok progressbox stdin")
PY
grep -q 'log "View install log"' "$INSTALL_SH" \
  || fail "menus must expose log viewer entry"
grep -q 'sshd "Enable SSH' "$INSTALL_SH" \
  || fail "checklist must offer sshd option"
grep -q 'pick_keymap' "$INSTALL_SH" || fail "must offer archfi-style keymap picker"
grep -q 'pick_timezone' "$INSTALL_SH" || fail "must offer archfi-style timezone picker"
grep -q 'pt-latin1' "$INSTALL_SH" || fail "common keymaps must use real map names"
grep -q 'br-abnt2' "$INSTALL_SH" || fail "common keymaps must use real map names"
grep -q 'jp106' "$INSTALL_SH" || fail "common keymaps must use real map names"
grep -q 'browse_args' "$INSTALL_SH" || fail "keymap browse must not clobber commons menu"
grep -q "s/\\\\.map(\\\\.gz)?\\$//" "$INSTALL_SH" \
  || grep -q 's/\.map(\.gz)?$//' "$INSTALL_SH" \
  || fail "keymap browse must strip .map/.map.gz only (not %%.*)"
! grep -q 'km=\${f%%\.\*}' "$INSTALL_SH" \
  || fail "keymap browse must not use \${f%%.*}"
grep -qF '/usr/share/zoneinfo/$tz' "$INSTALL_SH" \
  || fail "timezone validator must resolve under /usr/share/zoneinfo"
grep -qF 'valid_timezone "$TIMEZONE"' "$INSTALL_SH" \
  || fail "identity step must call valid_timezone"
grep -qF 'valid_hostname "$HOSTNAME"' "$INSTALL_SH" \
  || fail "identity step must call valid_hostname"
grep -qF 'valid_locale "$LOCALE"' "$INSTALL_SH" \
  || fail "identity step must call valid_locale"
grep -qF 'valid_keymap "$KEYMAP"' "$INSTALL_SH" \
  || fail "identity step must call valid_keymap"
grep -qF 'valid_username "$USERNAME"' "$INSTALL_SH" \
  || fail "identity step must call valid_username"
grep -qF 'T14S_IDENTITY_OVERRIDES' "$INSTALL_SH" \
  || fail "fixture overrides must be gated on T14S_IDENTITY_OVERRIDES"
grep -qF 'cannot pick a timezone' "$INSTALL_SH" \
  || fail "pick_timezone must not invent UTC when zoneinfo is missing"
grep -q 'LUKS_WIPE' "$INSTALL_SH" || fail "must offer optional LUKS mapper wipe"
grep -q 'PACMAN_PARALLEL' "$INSTALL_SH" || fail "must offer ParallelDownloads choice"
# pacman_tune: behaviour on a stock-style pacman.conf (live ISO + target).
_pt="$(mktemp)"
cat >"$_pt" <<'CONF'
[options]
XferCommand = /usr/bin/curl -fL -C - -o %o %u
#Color
#VerbosePkgLists
#ParallelDownloads = 5
[core]
Include = /etc/pacman.d/mirrorlist
#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist
#[multilib]
#Include = /etc/pacman.d/mirrorlist
CONF
bash -c 'eval "$(sed -n "/^pacman_tune()/,/^}/p" "$1")"; pacman_tune "$2" 15 Y; pacman_tune "$2" 15 Y' \
  _ "$INSTALL_SH" "$_pt" || fail "pacman_tune failed"
grep -q '^XferCommand' "$_pt" && fail "pacman_tune must drop XferCommand (serializes downloads)" || true
grep -qx 'ParallelDownloads = 15' "$_pt" || fail "pacman_tune must set ParallelDownloads"
for _k in Color ILoveCandy VerbosePkgLists DisableDownloadTimeout '\[multilib\]'; do
  [[ $(grep -c "^${_k}\$" "$_pt") == 1 ]] || fail "pacman_tune: expected exactly one ${_k} (idempotent)"
done
grep -q '^#\[multilib-testing\]' "$_pt" || fail "pacman_tune must not enable [multilib-testing]"
[[ $(grep -c '^Include' "$_pt") == 2 ]] || fail "pacman_tune: only [multilib] Include uncommented"
rm -f "$_pt"; unset -v _pt _k
grep -qE '^[^#]*XferCommand = ' "$INSTALL_SH" \
  && fail "installer must not add an XferCommand" || true
grep -qE 'declare -f pacman_tune( [^>]+)? >/mnt/root/t14s-lib\.sh' "$INSTALL_SH" \
  || fail "chroot must reuse host pacman_tune (no duplicate body)"
echo "ok pacman_tune"

# Chroot pkg_try: failure records pacman's own error line; key errors refresh
# archlinux-keyring and retry once. Stub pacman on PATH.
_pk="$(mktemp -d)"
mkdir -p "$_pk/bin"
cat >"$_pk/bin/pacman" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PK_DIR/calls"
# Real pacman prints this on every install attempt (success or not).
echo "(1/1) checking keys in keyring"
case "$*" in
  *archlinux-keyring*) touch "$PK_DIR/refreshed"; exit 0 ;;
  *keyfail*) [[ -f $PK_DIR/refreshed ]] && exit 0
             echo "error: keyfail: signature from \"X\" is unknown trust"; exit 1 ;;
  *broken*) echo ":: downloading broken..."; echo "error: failed to commit transaction (conflicting files)"; exit 1 ;;
  *keychain*) echo "error: target not found: keychain"; exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$_pk/bin/pacman"
_chroot_body="$(cat "$CHROOT_SH")"
PK_DIR="$_pk" PATH="$_pk/bin:$PATH" bash -c '
  set -euo pipefail
  eval "$(printf "%s\n" "$1" | awk "/^WARN_FILE=/{f=1} f; /^source \\/root\\/t14s-lib.sh/{exit}" | grep -v "^source ")"
  WARN_FILE=$2/warn
  # Key case first: its refresh must be the ONLY keyring call; a later
  # non-key failure must not trigger another one.
  pkg_try "Key set" keyfail >/dev/null || exit 22
  pkg_try "Broken set" broken >/dev/null && exit 21
  pkg_try "Name with key" keychain >/dev/null && exit 24
  pkg_try "Fine set" fine >/dev/null || exit 23
' _ "$_chroot_body" "$_pk" || fail "pkg_try behaviour wrong (rc=$?)"
grep -qx 'Broken set install failed (pacman exit 1): error: failed to commit transaction (conflicting files)' "$_pk/warn" \
  || fail "pkg_try must record pacman's error line: $(cat "$_pk/warn" 2>/dev/null)"
grep -q 'archlinux-keyring' "$_pk/calls" || fail "pkg_try must refresh archlinux-keyring on key errors"
grep -q 'Key set' "$_pk/warn" && fail "key error fixed by refresh must not warn" || true
[[ $(grep -c 'archlinux-keyring' "$_pk/calls") == 1 ]] \
  || fail "only the key error may trigger a keyring refresh (not 'checking keys in keyring' noise)"
grep -qx -- '-Su --noconfirm' "$_pk/calls" || fail "keyring refresh must be followed by -Su (no partial upgrade)"
rm -rf "$_pk"; unset -v _pk _chroot_body
echo "ok pkg_try"

# New option flags are wired end to end (answers, canonicalize, chroot env).
for _fl in INSTALL_MULTILIB INSTALL_YAY INSTALL_TUNED INSTALL_DEVTOOLS INSTALL_BTRFS_ASSISTANT \
           INSTALL_LINUX_HARDENED INSTALL_LINUX_STABLE INSTALL_LINUX_ZEN INSTALL_OLLAMA \
           INSTALL_FLATPAK_APPS INSTALL_BLUETOOTH INSTALL_VM_GUEST VM_SERIAL_CONSOLE \
           FW_SYNCTHING FW_KDECONNECT; do
  python3 - "$INSTALL_SH" "$_fl" <<'PY' || fail "flag $_fl not wired everywhere"
import re, sys
t = open(sys.argv[1]).read(); f = sys.argv[2]
keys = t[t.index('ANSWERS_KEYS=('):t.index(')', t.index('ANSWERS_KEYS=('))]
assert f in keys.split(), 'ANSWERS_KEYS'
# Tokenize the yn_canon for-list (stop at newline+do), not substring 'do' in names.
start = t.index('for _flag in DESKTOP')
end = t.index('\ndo\n', start)
canon = t[start:end]
assert f in canon.split(), 'yn_canon loop'
env = t[t.index('arch-chroot /mnt env'):t.index('bash /root/chroot-setup.sh', t.index('arch-chroot /mnt env'))]
assert f'{f}="${f}"' in env, 'chroot env'
if f.startswith('FW_'):
  assert f'{f}:=' in t, 'default'
else:
  assert f'${{{f}:=N}}' in t, 'default'
PY
done
unset -v _fl
grep -q 'tuned tuned-ppd' "$INSTALL_SH" || fail "GNOME + tuned must install tuned-ppd (replaces PPD)"
grep -q 'tlp conflicts with tuned' "$INSTALL_SH" || fail "tuned must force TLP off"
grep -q 'runuser -u "$USERNAME" -- git clone --no-checkout --depth 1 https://aur.archlinux.org/yay-bin.git' "$INSTALL_SH" \
  || fail "yay must be cloned --no-checkout as the user (makepkg refuses root)"
grep -q 'YAY_BIN_COMMIT:-' "$INSTALL_SH" \
  || fail "yay-bin must pin YAY_BIN_COMMIT SHA"
grep -q 'refusing unverified AUR build' "$INSTALL_SH" \
  || fail "yay-bin must refuse unpinned HEAD mismatch"
grep -vE '^\s*#' "$INSTALL_SH" | grep -q 'NOPASSWD' \
  && fail "installer must not grant sudoers NOPASSWD" || true
grep -q 'rtkit evolution-data-server' "$INSTALL_SH" || fail "GNOME needs rtkit + evolution-data-server"
grep -qE '^[[:space:]]+wireless-regdb$' "$INSTALL_SH" || fail "base needs wireless-regdb (regulatory.db)"
grep -q 'install -m 600 "$LOG" /mnt/var/log/t14s-install.log' "$INSTALL_SH" \
  || fail "install log must be kept on the target"
grep -q 'INSTALL COMPLETE with warnings' "$INSTALL_SH" || fail "finish screen must surface warnings"
# Flatpak apps are deferred to a first-boot oneshot (not downloaded in chroot).
_chr="$(cat "$CHROOT_SH")"
grep -qE '^\s*flatpak install --system .*\$\{_fp_apps' <<<"$_chr" \
  && fail "chroot must not download Flatpak apps (first-boot service does)" || true
grep -q 'systemctl enable NetworkManager-wait-online.service t14s-flatpak-apps.timer' <<<"$_chr" \
  || fail "first-boot flatpak timer + wait-online must be enabled"
# The retrying oneshot must not be WantedBy a target: targets order After= their
# wants, so boot would stay "starting" until Flatpak downloads succeed (VM test).
_fpsvc="$(awk '/cat > \/etc\/systemd\/system\/t14s-flatpak-apps.service/{f=1;next} f&&/^FP$/{exit} f' <<<"$_chr")"
[[ -n $_fpsvc ]] || fail "could not extract t14s-flatpak-apps.service"
! grep -qE '^\[Install\]|^WantedBy=' <<<"$_fpsvc" \
  || fail "flatpak oneshot must not be WantedBy a target (start it from the timer)"
_fptmr="$(awk '/cat > \/etc\/systemd\/system\/t14s-flatpak-apps.timer/{f=1;next} f&&/^FP$/{exit} f' <<<"$_chr")"
grep -qx 'OnBootSec=1min' <<<"$_fptmr" && grep -qx 'WantedBy=timers.target' <<<"$_fptmr" \
  || fail "flatpak timer must fire OnBootSec and be WantedBy timers.target"
grep -q 'TimeoutStartSec=30min' <<<"$_chr" || fail "flatpak oneshot timeout must be 30min"
grep -q 'ConditionPathExists=!/var/lib/t14s/flatpak-apps.done' <<<"$_chr" || fail "flatpak service must be one-shot (stamp)"
grep -q 'Restart=on-failure' <<<"$_chr" || fail "flatpak service must retry until online"
grep -q 'SNAP_PAC_SKIP=y' "$INSTALL_SH" || fail "chroot run must set SNAP_PAC_SKIP=y"
[[ $(grep -c 'NUMBER_LIMIT=10' <<<"$_chr") == 2 ]] || fail "snapper root and home must both set NUMBER_LIMIT=10"
unset -v _chr
echo "ok option wiring"

# No full-screen colour flashes: one backdrop for every severity; newt
# overlays never recolour root/window.
python3 - "$INSTALL_SH" <<'PY' || fail "TUI backdrop must be constant across severities"
import re, sys
t = open(sys.argv[1]).read()
assert t.count('screen_color = $screen') == 1
assert "local screen='(CYAN,BLUE,ON)'" in t
for blk in re.findall(r"^NEWT_COLORS_(?!BASE)[A-Z]+='\n(.*?)\n'", t, re.S | re.M):
    for ln in blk.splitlines():
        assert ln.split('=')[0] in ('border', 'title'), ln
print('ok constant TUI backdrop')
PY
grep -q 'skip_reflector' "$INSTALL_SH" || fail "checklist must offer skip reflector"
grep -q 'INSTALL_CUPS' "$INSTALL_SH" || fail "must offer archdi-style CUPS option"
grep -q 'nerd_fonts' "$INSTALL_SH" || fail "checklist must offer nerd_fonts"
grep -q 'ttf-jetbrains-mono-nerd' "$INSTALL_SH" || fail "must install JetBrains Mono Nerd"
! grep -q 'ttf-meslo-nerd' "$ROOT/lib/chroot/09-fonts-gnome-defaults.sh" \
  || fail "Stage A fonts must stay lean (no bulk 14-family nerd font pack)"
grep -q 'inter-font noto-fonts noto-fonts-emoji' "$ROOT/lib/chroot/09-fonts-gnome-defaults.sh" \
  || fail "Stage A fonts must include Inter + Noto UI/emoji"
grep -q 'ttf-nerd-fonts-symbols-common' "$INSTALL_SH" || fail "must install nerd symbols"
grep -q 'INSTALL_NERD_FONTS' "$INSTALL_SH" || fail "must gate nerd fonts install"
grep -A20 'arch-chroot /mnt env' "$INSTALL_SH" | grep -q 'INSTALL_NERD_FONTS=' \
  || fail "arch-chroot env must pass INSTALL_NERD_FONTS"
grep -q 'answers_save' "$INSTALL_SH" || fail "must save T14S answers file"
grep -q 'answers_load' "$INSTALL_SH" || fail "must load T14S_ANSWERS"
grep -q 'T14S_NONINTERACTIVE' "$INSTALL_SH" || fail "must honor T14S_NONINTERACTIVE"
grep -q 'Install profile' "$INSTALL_SH" || fail "must offer gnome/dev/minimal presets"
grep -q 'smartctl -H' "$INSTALL_SH" || fail "must SMART-check target disk"
grep -q 'INSTALL_CLI' "$INSTALL_SH" || fail "must offer CLI tools bundle"
grep -q 'INSTALL_PODMAN' "$INSTALL_SH" || fail "must offer podman"
grep -q 'INSTALL_DOCKER' "$INSTALL_SH" || fail "must offer docker"
grep -q 'INSTALL_VIRT' "$INSTALL_SH" || fail "must offer libvirt/qemu"
grep -q 'INSTALL_AVAHI' "$INSTALL_SH" || fail "must offer avahi"
grep -q 'INSTALL_STARSHIP' "$INSTALL_SH" || fail "must offer starship"
grep -q 'POST_HOOK_URL' "$INSTALL_SH" || fail "must offer post-install hook URL"
grep -q 'prefer-dark' "$INSTALL_SH" || fail "must ship GNOME dark dconf defaults"
grep -q 'JetBrainsMono Nerd Font' "$INSTALL_SH" || fail "must set Console Nerd Font"
grep -q 'install-chrome-flatpak.sh' "$INSTALL_SH" || fail "must offer Chrome helper script"
grep -q 'arch-chroot /mnt' "$INSTALL_SH" || fail "recovery docs / hook must mention arch-chroot"
grep -q 'Core extras' "$INSTALL_SH" || fail "must split Core checklist"
grep -q 'Dev / CLI tools' "$INSTALL_SH" || fail "must split Dev/CLI checklist"
grep -q 'Network / security' "$INSTALL_SH" || fail "must split Network checklist"
grep -q 'yn_on "\$DESKTOP"' "$INSTALL_SH" || fail "TLP guard must use yn_on"
grep -q 'pipefail' "$INSTALL_SH" || fail "post-hook must use pipefail"
grep -qE '\^https://' "$INSTALL_SH" \
  || fail "post-hook must require https:// URL (fail closed)"
grep -q 'T14S_POST_HOOK_SHA256' "$INSTALL_SH" \
  || fail "post-hook must support optional T14S_POST_HOOK_SHA256 pin"
grep -q 'T14S_POST_HOOK_I_UNDERSTAND' "$INSTALL_SH" \
  || fail "post-hook NONINTERACTIVE must require explicit opt-in"
grep -q 'mdns_minimal' "$INSTALL_SH" || fail "avahi path must patch nsswitch mdns_minimal"
grep -q 'jail.d/sshd.local' "$INSTALL_SH" || fail "fail2ban must enable sshd jail"
grep -q 'banaction = firewallcmd-rich-rules' "$INSTALL_SH" || fail "fail2ban must ban through firewalld"
grep -q 'systemd-tmpfiles-clean.timer systemd-timesyncd.service' "$INSTALL_SH" || fail "installed system must enable systemd-timesyncd"
grep -q 'using DISK from answers' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must honor DISK from answers"
grep -q 'timezone from answers' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must honor TIMEZONE from answers"
grep -q 'T14S_PASS_FILE' "$INSTALL_SH" || fail "must support T14S_PASS_FILE"
grep -q 'secrets_load' "$INSTALL_SH" || fail "must define secrets_load"
grep -q 'MANUAL partitions from answers' "$INSTALL_SH" \
  || fail "NONINTERACTIVE MANUAL must honor EFI_PART/ROOT_PART"
grep -q 'SKIP_THINKPAD_HW' "$INSTALL_SH" || fail "must detect/skip ThinkPad HW on VM"
grep -q 'INSTALL_SNAPPER_HOME' "$INSTALL_SH" || fail "must offer snapper home"
grep -q 'ESP free after UKI\|ESP nearly full after UKI' "$INSTALL_SH" \
  || fail "must check ESP free space after UKI build"
grep -q 'sbctl verify' "$INSTALL_SH" || fail "must run sbctl verify"
grep -q 'enroll skipped — sbctl verify failed' "$INSTALL_SH" \
  || fail "must block enroll when sbctl verify fails"
grep -q 't14s-selftest' "$INSTALL_SH" || fail "must offer BT/audio self-test"
grep -q 'BTRFS_COMPRESS' "$INSTALL_SH" || fail "must offer Btrfs compression radio"
grep -q 'ZRAM_SIZE' "$INSTALL_SH" || fail "must offer zram size radio"
grep -q 'REFLECTOR_COUNTRY' "$INSTALL_SH" || fail "must honor reflector country"
grep -q 'T14S_DEFAULT_HOOK_URL' "$INSTALL_SH" || fail "must offer hook env preset"
grep -q 'xdg-user-dirs-update' "$INSTALL_SH" || fail "must run xdg-user-dirs-update"
grep -q 'INSTALL_LINUX_STABLE' "$INSTALL_SH" || fail "must offer optional linux UKI"
grep -q 'INSTALL_LINUX_HARDENED' "$ROOT/lib/50-packages.sh" || fail "50-packages must gate linux-hardened on INSTALL_LINUX_HARDENED"
! grep -q 'linux-lts-headers linux-hardened' "$ROOT/lib/50-packages.sh" || fail "linux-hardened must be optional, not unconditional in BASE_PKGS"
grep -q 'if yn_on "\${INSTALL_LINUX_HARDENED:-N}"' "$ROOT/lib/chroot/04-ukis.sh" || fail "04-ukis must gate linux-hardened.preset on INSTALL_LINUX_HARDENED"
grep -q 'linux-zen-headers' "$ROOT/lib/50-packages.sh" || fail "50-packages must add linux-zen + headers"
grep -q 'arch-linux-zen.efi' "$ROOT/lib/chroot/04-ukis.sh" || fail "04-ukis must build arch-linux-zen.efi"
grep -q 'arch-linux-zen.efi' "$ROOT/lib/chroot/12-secureboot-ssh-firewall.sh" || fail "12-secureboot must sign arch-linux-zen.efi"
grep -q 'INSTALL_PLYMOUTH' "$INSTALL_SH" || fail "must offer optional plymouth"
grep -q 'Answers schema' "$ROOT/README.md" || fail "README must document answers schema"
grep -q 'NONINTERACTIVE: skipping REVIEW/confirm' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must skip REVIEW/final confirm"
grep -q 'NONINTERACTIVE AUTO: will erase' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must skip AUTO type-DISK wipe confirm"
grep -q 'NONINTERACTIVE requires T14S_PASS_FILE' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must die early without T14S_PASS_FILE"
# Pass-file gate must appear before ui_password for LUKS
python3 - "$INSTALL_SH" <<'PY' || fail "NONINTERACTIVE pass-file die must precede ui_password"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
die_i = t.find("NONINTERACTIVE requires T14S_PASS_FILE")
pw_i = t.find("ui_password 'LUKS passphrase'")
assert die_i > 0 and pw_i > 0 and die_i < pw_i, (die_i, pw_i)
print("ok pass-file die order")
PY
grep -q 'part_on_disk' "$INSTALL_SH" || fail "MANUAL answers must verify part_on_disk"
grep -q 'yn_canon' "$INSTALL_SH" || fail "must canonicalize flags to Y/N"
grep -q 'chmod 600' "$INSTALL_SH" || fail "answers_save / secrets must chmod 600"
grep -q 'must be mode 0600' "$INSTALL_SH" || fail "secrets_load must require mode 0600"
# Chroot body must define yn_on and not leave stray ] after yn_on calls
python3 - "$CHROOT_SH" <<'PY' || fail "chroot yn_on gates broken"
from pathlib import Path
import re, sys, subprocess, tempfile
body = Path(sys.argv[1]).read_text()
assert "yn_on() {" in body, "chroot missing yn_on"
assert not re.search(r'yn_on[^\n]*"\]', body), "stray ] after yn_on"
assert not re.search(r'\$\{(?:INSTALL_|SKIP_|DESKTOP|ENROLL_|ENABLE_|FW_)[A-Z0-9_]*\^\^\}', body), \
    "chroot still uses ^^ on feature flags"
assert "sd-encrypt" in body and "HOOKS missing sd-encrypt" in body
with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
    f.write(body)
    name = f.name
subprocess.check_call(["bash", "-n", name])
print("ok chroot yn_on + bash -n")
PY
grep -q 'xdg-user-dirs' "$INSTALL_SH" || fail "must pacstrap or call xdg-user-dirs"
grep -q 'T14S_I_WILL_ERASE' "$INSTALL_SH" \
  || fail "NONINTERACTIVE wipe must require T14S_I_WILL_ERASE"
grep -q 'no env passwords' "$INSTALL_SH" \
  || fail "NONINTERACTIVE must refuse ambient env passwords"
grep -q 'unset -v LUKS_PASS USER_PASS ROOT_PASS' "$INSTALL_SH" \
  || fail "must unset ambient password env at start"
grep -q 'cannot read mode of T14S_PASS_FILE' "$INSTALL_SH" \
  || fail "secrets_load must fail closed if mode unknown"
grep -q 'EXTRA_PKGS_LIST' "$INSTALL_SH" \
  || fail "must persist EXTRA_PKGS_LIST in answers"
grep -q "v == y || \$v == yes" "$INSTALL_SH" \
  || fail "yn_on must match y/yes/on/1 only"
grep -q "HOOKS=.*sd-encrypt" "$INSTALL_SH" \
  || fail "HOOKS verify must match ^HOOKS=.*sd-encrypt"
grep -q 'NONINTERACTIVE needs DISK=' "$INSTALL_SH" \
  || fail "NONINTERACTIVE missing DISK must die (not TUI)"
grep -q 'NONINTERACTIVE needs MODE=' "$INSTALL_SH" \
  || fail "NONINTERACTIVE missing MODE must die"
# part_on_disk must not accept nvme0n1 vs nvme0n10 via naive prefix
python3 - "$INSTALL_SH" <<'PY' || fail "part_on_disk must bound nvme prefix"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
i = t.find("part_on_disk()")
assert i > 0
window = t[i:i+700]
assert 'nvme0n1' in window or 'Bound' in window or '${disk}p' in window
assert 'rest=' in window and '^[0-9]+$' in window
print("ok part_on_disk bound")
PY
grep -q 'T14S_I_WILL_ERASE' "$ROOT/README.md" \
  || fail "README must document T14S_I_WILL_ERASE"
grep -q 'EXTRA_PKGS_LIST' "$ROOT/README.md" \
  || fail "README must document EXTRA_PKGS_LIST"
grep -q 'CLEAN_ESP_ARCH' "$INSTALL_SH" || fail "must offer CLEAN_ESP_ARCH"
grep -q 'clean_esp_arch_files' "$INSTALL_SH" || fail "must define clean_esp_arch_files"
grep -q 'clean_esp "' "$INSTALL_SH" || fail "Core checklist must offer clean_esp"
grep -q 'EFI/arch' "$INSTALL_SH" || fail "ESP clean must remove EFI/arch vendor dir"
grep -A25 'arch-chroot /mnt env' "$INSTALL_SH" | grep -q 'CLEAN_ESP_ARCH=' \
  || fail "arch-chroot env must pass CLEAN_ESP_ARCH"
grep -q 'CLEAN_ESP_ARCH' "$ROOT/README.md" || fail "README must document CLEAN_ESP_ARCH"
grep -q 'ESP / EFI layout' "$ROOT/README.md" || fail "README must document ESP/EFI layout"
grep -q 'Securing the EFI' "$ROOT/README.md" || fail "README must document EFI securing"
grep -q 'Can everything live under one directory' "$ROOT/README.md" \
  || fail "README must document why EFI is not one directory"
grep -q 'sbctl verify' "$ROOT/README.md" || fail "README must mention sbctl verify"
# NONINTERACTIVE must keep EXTRA_PKGS_LIST replay (not wipe array empty)
python3 - "$INSTALL_SH" <<'PY' || fail "NONINTERACTIVE must not wipe EXTRA_PKGS after answers replay"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
i = t.find("if (( NONINTERACTIVE )); then\n  # Keep EXTRA_PKGS")
assert i > 0, "missing NI EXTRA_PKGS keep comment"
window = t[i:i+120]
assert "EXTRA_PKGS=()" not in window, "NI still wipes EXTRA_PKGS"
print("ok EXTRA_PKGS_LIST replay")
PY
# Interactive checklist must pre-tick checklist extras and re-apply non-checklist _extras_keep
python3 - "$INSTALL_SH" <<'PY' || fail "interactive must preserve non-checklist EXTRA_PKGS_LIST and pre-tick checklist items"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
assert '_extra_onoff tmux' in t, "checklist must pre-tick EXTRA_PKGS items"
assert '_extras_keep+=("$_p")' in t, "non-checklist EXTRA_PKGS must be kept"
assert 'EXTRA_PKGS+=("${_extras_keep[@]}")' in t, "_extras_keep must be re-applied"
print("ok interactive extras keep")
PY
# Loader cleanup must use arch*.conf only (not linux-*.conf)
python3 - "$INSTALL_SH" <<'PY' || fail "ESP clean must not delete linux-*.conf"
from pathlib import Path
import sys, re
t = Path(sys.argv[1]).read_text()
assert "-name 'arch*.conf'" in t or '-name "arch*.conf"' in t
# No find that deletes linux-*.conf
assert not re.search(r"-name 'linux-\*\.conf'", t), "linux-*.conf still deleted"
print("ok arch*.conf only")
PY
grep -q '_env_on' "$INSTALL_SH" || fail "must parse T14S_NONINTERACTIVE / I_WILL_ERASE with yn-style"
grep -q 'DNS labels only' "$INSTALL_SH" || fail "must validate HOSTNAME charset"
grep -q 'yn_on "\$DESKTOP"' "$INSTALL_SH" || fail "finish path must use yn_on DESKTOP"
grep -q 'flatpak install --user -y flathub com.google.Chrome' "$INSTALL_SH" \
  || fail "finish Chrome hint must use --user"
grep -q 'flatpak install --user' "$ROOT/README.md" \
  || fail "README Chrome tip must match helper (--user)"
grep -q 'Setup Mode' "$ROOT/README.md" || fail "README SB enroll must mention Setup Mode"
grep -q 'FORMAT_EFI=1' "$ROOT/README.md" || fail "README must note CLEAN_ESP ignored when formatting"
grep -q 'dead entries' "$INSTALL_SH" || fail "CLEAN_ESP_ARCH=N must warn about dead boot entries"
# umask must not leak into arch-chroot (regression: /etc/locale.conf 0600 → LANG unset).
grep -vE '^\s*#' "$WIZARD_SH" | grep -qE '^umask ' \
  && fail "script-wide umask leaks into arch-chroot; scope it in a subshell" || true
grep -qx 'umask 022' "$CHROOT_SH" \
  || fail "chroot script must pin umask 022"
grep -q 'fmask=0077' "$INSTALL_SH" || fail "ESP fstab must use fmask/dmask=0077 (random-seed)"
# Chroot must not delete pacstrap's kernels/ucode before mkinitcpio -P
# (regression: "'/boot/vmlinuz-linux-lts' must be readable").
awk '/^mkinitcpio -P/{exit} {print}' "$CHROOT_SH" \
  | grep -vE '^\s*#' \
  | grep -qE 'rm .*(/boot/vmlinuz|/boot/(amd|intel)-ucode\.img)' \
  && fail "chroot removes /boot/vmlinuz* or *-ucode.img before mkinitcpio -P" || true
grep -q 'sudo -u "\$USERNAME" tee -a' "$INSTALL_SH" \
  || fail "starship must append zshrc as the user"
! grep -q "gtk-theme='Adwaita-dark'" "$INSTALL_SH" \
  || fail "dconf must not set stale Adwaita-dark gtk-theme"
python3 - "$INSTALL_SH" <<'PY' || fail "JetBrainsMono dconf must be gated on INSTALL_NERD_FONTS"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
i = t.find("monospace-font-name='JetBrainsMono Nerd Font Mono 11'")
assert i > 0, "monospace line missing"
window = t[max(0, i - 400):i]
assert "INSTALL_NERD_FONTS" in window, "JetBrainsMono dconf not under INSTALL_NERD_FONTS gate"
print("ok nerd dconf gate")
PY
grep -q 'yn_on "\$INSTALL_CHROME_HINT"' "$INSTALL_SH" \
  || fail "chrome hint must use yn_on"
grep -q 'set-x11-keymap' "$INSTALL_SH" || fail "GNOME path must set X11 keymap from console map"
grep -q 'XKB_LAYOUT=gb' "$INSTALL_SH" || fail "XKB remap must map uk → gb"
grep -q 'XkbVariant' "$INSTALL_SH" || fail "XKB conf must support variants (dvorak/colemak/abnt2)"
grep -q 'write_xkb_conf\|00-keyboard.conf' "$INSTALL_SH" \
  || fail "must write 00-keyboard.conf when localectl fails"
grep -A6 'arch-chroot /mnt env' "$INSTALL_SH" | grep -q 'INSTALL_CUPS=' \
  || fail "arch-chroot env must pass INSTALL_CUPS"
grep -A6 'arch-chroot /mnt env' "$INSTALL_SH" | grep -q 'PACMAN_PARALLEL=' \
  || fail "arch-chroot env must pass PACMAN_PARALLEL"
grep -q 'bash-completion' "$INSTALL_SH" || fail "must offer archdi console tools"
grep -q 'T14S_EXTRA_PKGS' "$INSTALL_SH" || fail "must honor T14S_EXTRA_PKGS / free-form extras"
grep -q 'locale=%s' "$INSTALL_SH" || fail "DRYRUN dump must include locale"
grep -q 'archfi' "$ROOT/README.md" || fail "README must credit archfi adaptations"
grep -q 'archdi' "$ROOT/README.md" || fail "README must credit archdi adaptations"
# keymap basename strip unit (no dialog)
python3 - <<'PY' || fail "keymap .map.gz strip logic wrong"
import re
samples = {
  "us.map.gz": "us",
  "lt.baltic.map.gz": "lt.baltic",
  "lt.l4.map.gz": "lt.l4",
  "defkeymap_V1.0.map.gz": "defkeymap_V1.0",
  "pt-latin1.map.gz": "pt-latin1",
  "br-abnt2.map": "br-abnt2",
}
pat = re.compile(r"\.map(\.gz)?$")
for src, want in samples.items():
  got = pat.sub("", src)
  assert got == want, (src, got, want)
print("ok keymap strip")
PY
# Prefer dialog over whiptail for progressbox
grep -q 'Prefer dialog' "$INSTALL_SH" \
  || grep -A2 'command -v dialog' "$INSTALL_SH" | grep -q 'UI=dialog' \
  || fail "bootstrap must prefer dialog when available"
# Leftover cleanup: only after the final confirm + DRYRUN exit, only on the target.
python3 - "$INSTALL_SH" <<'PY' || fail "leftover cleanup must run after confirmation and be target-scoped"
from pathlib import Path
import sys
t = Path(sys.argv[1]).read_text()
confirm = t.find('"Start the installation? The partitions above will be ERASED."')
dry_exit = t.find("exit 0", t.find("if (( DRYRUN )); then\n  printf 'DRYRUN:"))
release = t.find("release_target_devices", dry_exit)
part = t.find('sgdisk --zap-all "$DISK"')
assert 0 < confirm < dry_exit < release < part, (confirm, dry_exit, release, part)
assert "swapoff -a" not in t, "global swapoff -a must not be used"
# Body lives in lib/40-disk.sh (concatenated into INSTALL_SH for greps).
fn = t.find("release_target_devices() {")
assert fn > 0, "release_target_devices must be defined"
body = t[fn:t.find("\n}", fn) + 2]
assert '_on_target "$_src" || die' in body, "umount /mnt must be gated on the target"
assert 'if _on_target "$_sw"; then swapoff "$_sw"' in body, "swapoff must be per-device on the target"
assert "_on_target /dev/mapper/cryptroot" in body, "cryptroot close must be gated on the target"
print("ok scoped leftover cleanup")
PY

# partitioning: partitions chosen from lists, sizes validated
grep -q 'build_part_menu' "$INSTALL_SH" || fail "partition selector helper missing"
grep -q 'pick_part' "$INSTALL_SH" || fail "partition picker missing"
grep -q 'EFI system partition size' "$INSTALL_SH" || fail "ESP size must be selectable"
grep -q 'lsblk_rows "\$_disk" TYPE PATH' "$INSTALL_SH" || fail "partition list must filter to type=part"
grep -q 'root_mb < 8192' "$INSTALL_SH" || fail "must warn on tiny root"

grep -q 'HelllGuest/dotfiles/main/stage-a/install.sh' "$INSTALL_SH" \
  || fail "curl URL must point at dotfiles/stage-a"
grep -E 'Flatpak/Podman|Podman userns' "$INSTALL_SH" \
  && fail "banner must not claim Podman" || true

# Identity validators: real inputs (extract from install.sh; fixtures for CI)
extract_fn() {
  awk -v n="$1" '
    $0 ~ "^" n "\\(\\)" {grab=1}
    grab {print; if ($0 == "}") exit}
  ' "$INSTALL_SH"
}
# shellcheck disable=SC1090
source <(for fn in valid_hostname valid_username valid_timezone valid_locale valid_keymap valid_reflector_country; do
  extract_fn "$fn"
  echo
done)
# reflector --country is written single-quoted into reflector.conf (chroot).
for _c in DE DE,NL "United States" "Germany, France"; do
  valid_reflector_country "$_c" || fail "reflector country '$_c' should pass"
done
for _c in "DE;rm" "DE'x" '$(id)' "1DE" "DE-NL" ""; do
  valid_reflector_country "$_c" && fail "reflector country '$_c' should fail" || true
done
unset -v _c
# The prompt re-asks; an answers-file value gets a box (a bare warn line there
# was drawn over by the Review screen before logging even started).
grep -A6 'REFLECTOR_COUNTRY=".*ui_input' "$WIZARD_SH" | grep -q 'valid_reflector_country' \
  || fail "reflector country prompt must re-ask on invalid input"
grep -A3 '^# Reflector country sanitize' "$WIZARD_SH" | grep -q 'ui_warn' \
  || fail "invalid REFLECTOR_COUNTRY from answers must be shown (ui_warn)"
# Live refresh failure: reason + consequence in a box (a bare warn line was
# drawn over by the download gauge at once); never "skipped" on that path.
_rb="$(awk '/^ML_TMP="\$\(mktemp\)"$/{f=1} f{print} f&&/^unset -v _reflector_args$/{exit}' "$WIZARD_SH")"
grep -q '124) _rfl_why="timed out' <<<"$_rb" || fail "reflector failure must name a timeout"
grep -q '(( NONINTERACTIVE )) || ui_warn "Mirror refresh' <<<"$_rb" || fail "reflector failure must be shown interactively"
grep -q 'reflector skipped, timed out' <<<"$_rb" && fail "failure path must not say 'skipped'"
unset -v _rb
valid_hostname thinkpad-t14s || fail "hostname thinkpad-t14s should pass"
valid_hostname host.example.com || fail "hostname FQDN should pass"
valid_hostname -bad && fail "hostname -bad should fail" || true
valid_hostname bad- && fail "hostname bad- should fail" || true
valid_username root && fail "username root should fail" || true
valid_username bin && fail "username bin should fail" || true
for _g in wheel audio users; do
  if getent group "$_g" >/dev/null 2>&1; then
    valid_username "$_g" && fail "username $_g (group) should fail" || true
  fi
done
_fresh="t14sid$$"
valid_username "$_fresh" || fail "username $_fresh should pass"
_long40='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
valid_username "$_long40" && fail "username len 40 should fail" || true
valid_timezone America/New_York || fail "timezone America/New_York should pass"
valid_timezone UTC || fail "timezone UTC should pass"
valid_timezone '../../../etc/passwd' && fail "timezone traversal should fail" || true
valid_timezone zone.tab && fail "timezone zone.tab should fail" || true
valid_timezone Factory && fail "timezone Factory should fail" || true
if [[ -f /usr/share/zoneinfo/leapseconds ]]; then
  valid_timezone leapseconds && fail "timezone leapseconds should fail" || true
fi
if [[ -f /usr/share/zoneinfo/posixrules ]]; then
  valid_timezone posixrules && fail "timezone posixrules should fail" || true
fi
_idtmp="$(mktemp -d)"
trap 'rm -rf "$_idtmp"' EXIT
printf '%s\n' 'en_US.UTF-8 UTF-8' >"$_idtmp/locales"
mkdir -p "$_idtmp/keymaps" "$_idtmp/bin"
: >"$_idtmp/keymaps/us.map.gz"
: >"$_idtmp/keymaps/extra.map.gz"
# Overrides ignored without T14S_IDENTITY_OVERRIDES=1
LOCALE_FILES="$_idtmp/locales" valid_locale en_US.UTF-8 \
  || fail "locale en_US.UTF-8 should pass via host locale.gen/SUPPORTED"
LOCALE_FILES="$_idtmp/locales" valid_locale NotA_Locale \
  && fail "locale NotA_Locale should fail without overrides inventing it" || true
T14S_IDENTITY_OVERRIDES=1 LOCALE_FILES="$_idtmp/locales" valid_locale en_US.UTF-8 \
  || fail "locale fixture en_US.UTF-8 should pass with overrides"
T14S_IDENTITY_OVERRIDES=1 LOCALE_FILES="$_idtmp/locales" valid_locale NotA_Locale \
  && fail "locale NotA_Locale should fail" || true
T14S_IDENTITY_OVERRIDES=1 KEYMAP_DIR="$_idtmp/keymaps" valid_keymap us \
  || fail "keymap fixture us should pass"
T14S_IDENTITY_OVERRIDES=1 KEYMAP_DIR="$_idtmp/keymaps" valid_keymap '*' \
  && fail "keymap glob * should fail" || true
# Without overrides, KEYMAP_DIR must not redirect the search root
KEYMAP_DIR="$_idtmp/keymaps" valid_keymap extra \
  && fail "KEYMAP_DIR must be ignored without T14S_IDENTITY_OVERRIDES" || true
cat >"$_idtmp/bin/localectl" <<'EOF'
#!/bin/sh
[ "$1" = list-keymaps ] || exit 1
printf '%s\n' us uk dvo
EOF
chmod +x "$_idtmp/bin/localectl"
extract_fn valid_keymap >"$_idtmp/valid_keymap.sh"
# shellcheck disable=SC2016
env T14S_IDENTITY_OVERRIDES=1 KEYMAP_DIR="$_idtmp/keymaps" \
  PATH="$_idtmp/bin:/usr/bin:/bin" bash -c '
  # shellcheck source=/dev/null
  source "$0"
  valid_keymap us || exit 11
  valid_keymap dvo || exit 14
  valid_keymap extra || exit 15
  valid_keymap u. && exit 12
  valid_keymap "..." && exit 13
  exit 0
' "$_idtmp/valid_keymap.sh" \
  || fail "stub localectl: us/dvo/extra pass / u. and ... must fail"

command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning -e SC2015,SC2086,SC2162,SC2034 "$INSTALL_SH" \
  || echo "NOTE: shellcheck skipped or warnings-only"

# Live NONINTERACTIVE dry-run: catches set -e helper return bugs (no disk writes).
_dry_disk=""
while read -r _name _typ; do
  [[ $_typ == disk ]] || continue
  case $_name in
    /dev/zram*|/dev/loop*|/dev/ram*|/dev/md*) continue ;;
  esac
  _dry_disk=$_name
  break
done < <(lsblk -dpno NAME,TYPE 2>/dev/null)
if [[ -z $_dry_disk ]]; then
  echo "SKIP: no whole-disk block device for NONINTERACTIVE dry-run"
else
  _drytmp="$(mktemp -d)"
  trap 'rm -rf "${_idtmp:-}" "$_drytmp"' EXIT
  _ans="$_drytmp/answers.env"
  _pass="$_drytmp/pass.env"
  _out="$_drytmp/answers.out"
  cat >"$_ans" <<EOF
DISK=$_dry_disk
MODE=auto
ESP_MB=2048
HOSTNAME=thinkpad-t14s
TIMEZONE=UTC
LOCALE=en_US.UTF-8
KEYMAP=us
USERNAME=t14sdry
PRESET=minimal
DESKTOP=N
LUKS_WIPE=none
PACMAN_PARALLEL=5
BTRFS_COMPRESS=zstd3
ZRAM_SIZE=half
SKIP_THINKPAD_HW=Y
SKIP_REFLECTOR=Y
EOF
  cat >"$_pass" <<'EOF'
LUKS_PASS=dryrun-luks-pass
USER_PASS=dryrun-user-pass
ROOT_PASS=dryrun-root-pass
EOF
  chmod 600 "$_ans" "$_pass"
  # Ubuntu CI: localectl list-keymaps is empty and /usr/share/kbd/keymaps is
  # missing — use the gated fixture path (same as identity unit tests).
  mkdir -p "$_drytmp/keymaps"
  : >"$_drytmp/keymaps/us.map.gz"
  _dry_log="$_drytmp/dryrun.log"
  if ! T14S_DRYRUN=1 T14S_UI=plain T14S_NONINTERACTIVE=1 T14S_I_WILL_ERASE=1 \
      T14S_IDENTITY_OVERRIDES=1 KEYMAP_DIR="$_drytmp/keymaps" \
      T14S_ANSWERS="$_ans" T14S_PASS_FILE="$_pass" T14S_ANSWERS_OUT="$_out" \
      T14S_LIB_DIR="$ROOT/lib" \
      bash "$ORCH_SH" >"$_dry_log" 2>&1
  then
    tail -n 40 "$_dry_log" >&2 || true
    fail "NONINTERACTIVE dry-run exited non-zero (disk=$_dry_disk)"
  fi
  grep -q '^DRYRUN:' "$_dry_log" \
    || fail "dry-run must print DRYRUN summary line"
  # On non-T14s CI VMs: warn path must not claim ok target profile.
  if ! grep -qiE '21C[QR]' /sys/class/dmi/id/product_name \
        /sys/class/dmi/id/product_sku 2>/dev/null
  then
    grep -q 'DMI not 21CQ/21CR' "$_dry_log" \
      || fail "non-T14s dry-run must warn about DMI mismatch"
    grep -q 'ok target profile: T14s Gen 3 AMD' "$_dry_log" \
      && fail "ok target profile must not print after DMI mismatch" || true
  fi
  echo "ok NONINTERACTIVE dry-run on $_dry_disk"
fi
# Static: DRYRUN exit must precede every destructive write (log grep is useless:
# those commands are not echoed, and start_log runs only after the exit).
python3 - "$INSTALL_SH" <<'PY' || fail "DRYRUN exit must precede destructive commands"
from pathlib import Path
import re, sys
t = Path(sys.argv[1]).read_text().splitlines()
dry = None
for i, ln in enumerate(t):
    if "printf 'DRYRUN:" in ln or 'printf "DRYRUN:' in ln:
        for j in range(i, min(i + 15, len(t))):
            if re.match(r'\s*exit 0\s*$', t[j]):
                dry = j
                break
        break
assert dry is not None, 'DRYRUN summary + exit 0 not found'
# Match command starts, including after | ; & && || (piped cryptsetup etc.).
# Line-position only (not call order); live dry-run covers runtime.
cmd = (
    r'(?:^|[|;&]|&&|\|\|)\s*'
    r'(?:sgdisk --zap-all|cryptsetup (?:luksFormat|open)|wipefs -a|'
    r'mkfs\.fat|mkfs\.btrfs|dd if=/dev/)'
)
pat = re.compile(cmd)

def hits(lines):
    out = []
    for i, ln in enumerate(lines):
        s = ln.lstrip()
        if not s or s.startswith('#'):
            continue
        if pat.search(ln):
            out.append(f'{i+1}:{ln.strip()}')
    return out

before = hits(t[:dry])
if before:
    raise SystemExit('destructive cmds before DRYRUN exit:\n  ' + '\n  '.join(before))
after = hits(t[dry+1:])
assert after, 'no destructive cmds after DRYRUN exit'
# Piped cryptsetup must be visible to the scanner (regression for ^\s* anchor).
assert any('cryptsetup luksFormat' in x for x in after), \
    'piped cryptsetup luksFormat not detected after DRYRUN exit'
print('ok DRYRUN exit before destructive phase')
PY

# ── safety / robustness regressions ─────────────────────────
_pick="$(awk '/^pick_part\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$INSTALL_SH")"
grep -q 'part_on_disk "\$ans" "\$disk"' <<<"$_pick" \
  || fail "pick_part must reject manual partitions on another disk"
grep -qF '[[ -d /run/archiso ]] || (( ALLOW_NON_ISO ))' "$INSTALL_SH" \
  || fail "preflight must require /run/archiso unless T14S_ALLOW_NON_ISO=1"
grep -q 'iflag=count_bytes count="\$size"' "$INSTALL_SH" \
  || fail "LUKS wipe must bound dd to the device size"
grep -q '(( rc == 0 )) || die "LUKS wipe failed' "$INSTALL_SH" \
  || fail "LUKS wipe must only accept dd exit 0"
_tmp="$(mktemp -d)"
dd if=/dev/zero of="$_tmp/w" bs=64M iflag=count_bytes count=1000000 status=none \
  || fail "dd count_bytes wipe returned nonzero"
[[ $(stat -c %s "$_tmp/w") == 1000000 ]] || fail "dd count_bytes wrote wrong size"
# read -a must not glob: "*" stays literal even with files in cwd.
touch "$_tmp/install.sh"
( cd "$_tmp" && read -r -a _a <<<'htop * tmux' && [[ ${_a[*]} == 'htop * tmux' ]] ) \
  || fail "package tokenizing must not pathname-expand"
rm -rf "$_tmp"
! grep -qE 'for _p in \$\{?(EXTRA_PKGS_LIST|_extra_in)' "$INSTALL_SH" \
  || fail "package lists must not use unquoted for-in splitting"
[[ $(grep -cE 'read -r -a _pkgs <<<"\$(EXTRA_PKGS_LIST|_extra_in)"' "$INSTALL_SH") -eq 2 ]] \
  || fail "both package lists must tokenize with read -r -a"
! grep -qF "val=\${val#\$'\\r'}" "$INSTALL_SH" \
  || fail "answers/secrets parsers must strip trailing CR, not leading"
[[ $(grep -cF "val=\${val%\$'\\r'}" "$INSTALL_SH") -eq 2 ]] \
  || fail "both answers and secrets parsers must strip trailing CR"
grep -q 'plain | dialog | whiptail) UI=\$T14S_UI' "$INSTALL_SH" \
  || fail "T14S_UI must be limited to plain|dialog|whiptail"
grep -qF "trap '_on_err \"\$?\" \"\$LINENO\" \"\$BASH_COMMAND\"' ERR" "$ORCH_SH" \
  || fail "ERR trap must pass \$? first to _on_err (a \$(…) in the trap would reset it)"
# Code lives in lib/steps/: a failure must name the stage file; install.sh itself
# runs from a pipe on the curl path (/dev/fd/N) and must still say install.sh.
_oe="$(awk '/^_on_err\(\) *\{/{f=1} f{print} f&&/^}$/{exit}' "$ORCH_SH")"
[[ -n $_oe ]] || fail "could not extract _on_err"
_st="$(mktemp -d)"; printf ': first line\n(exit 3)\n' >"$_st/22-x.sh"
_pre='set -euo pipefail; die() { echo "$1 rc=$2"; exit 1; }'
_trap="trap '_on_err \"\$?\" \"\$LINENO\" \"\$BASH_COMMAND\"' ERR"
_msg="$(bash -c "$_pre"$'\n'"$_oe"$'\n'"$_trap"$'\n''source "$1"' _ "$_st/22-x.sh" 2>&1 || true)"
[[ $_msg == "failed at 22-x.sh:2 (exit 3): ( exit 3 ) rc=3" ]] \
  || fail "ERR inside a stage must name file:line and keep the exit code, got: $_msg"
_msg="$(bash <(printf '%s\n' "$_pre" "$_oe" "$_trap" '(exit 5)') 2>&1 || true)"
[[ $_msg == "failed at install.sh:"*" (exit 5): ( exit 5 ) rc=5" ]] \
  || fail "ERR in install.sh run from a pipe must say install.sh, got: $_msg"
rm -rf -- "$_st"; unset -v _st _msg _oe _pre _trap
grep -qF "trap 'on_exit \$?' EXIT" "$ORCH_SH" \
  || fail "EXIT trap must route through on_exit (backstop for failures inside helpers)"

# T14S_DRYRUN: unknown values abort (never a silent real install) and are
# never evaluated as arithmetic (no $(…) execution).
_tmp="$(mktemp -d)"
for _v in true 'maybe' "a[\$(touch $_tmp/pwned)]"; do
  _rc=0
  T14S_DRYRUN="$_v" T14S_NONINTERACTIVE=1 T14S_LIB_DIR="$ROOT/lib" \
    timeout 30 bash "$ORCH_SH" </dev/null >/dev/null 2>&1 || _rc=$?
  [[ -e $_tmp/pwned ]] && fail "T14S_DRYRUN value was executed: $_v"
  if [[ $_v == true ]]; then
    (( _rc != 2 )) || fail "T14S_DRYRUN=true must be accepted as dry run"
  else
    (( _rc == 2 )) || fail "T14S_DRYRUN=$_v must abort with exit 2 (got $_rc)"
  fi
done

# answers_save: atomic rename, mode 0600, replaces a symlink instead of following it.
printf 'victim\n' >"$_tmp/victim"
ln -s "$_tmp/victim" "$_tmp/answers.env"
_fn="$(awk '/^answers_save\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$INSTALL_SH")"
[[ -n $_fn ]] || fail "could not extract answers_save"
bash -c '
  set -euo pipefail
  die() { echo "die: $*" >&2; exit 9; }
  eval "$1"
  ANSWERS_KEYS=(MODE HOSTNAME); MODE=auto; HOSTNAME=t14s
  answers_save "$2"
' _ "$_fn" "$_tmp/answers.env" || fail "answers_save failed"
[[ ! -L $_tmp/answers.env ]] || fail "answers_save must replace a symlink, not follow it"
[[ $(cat "$_tmp/victim") == victim ]] || fail "answers_save wrote through a symlink"
[[ $(stat -c %a "$_tmp/answers.env") == 600 ]] || fail "answers file must be mode 0600"
grep -qx 'HOSTNAME=t14s' "$_tmp/answers.env" || fail "answers file content missing"
[[ -z $(find "$_tmp" -name '.t14s-answers.*') ]] || fail "answers_save left a temp file"
rm -rf "$_tmp"

# _on_target: only the confirmed target (or, in auto mode, partitions on DISK).
_fn="$(awk '/^_on_target\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$INSTALL_SH")"
[[ -n $_fn ]] || fail "could not extract _on_target"
bash -c '
  set -euo pipefail
  eval "$1"
  part_on_disk() { [[ $1 == /dev/nvme0n1p* && $2 == /dev/nvme0n1 ]]; }
  cryptsetup() { printf "  type:    LUKS2\n  device:  %s\n" "$CRYPT_DEV"; }
  ROOT_PART=/dev/nvme0n1p2 EFI_PART=/dev/nvme0n1p1 DISK=/dev/nvme0n1
  MODE=manual
  _on_target /dev/nvme0n1p2 || exit 11
  _on_target /dev/nvme0n1p1 || exit 12
  ! _on_target /dev/nvme0n1p3 || exit 13        # same disk, not chosen (manual)
  ! _on_target /dev/sda1 || exit 14
  ! _on_target /swapfile || exit 15
  CRYPT_DEV=/dev/nvme0n1p2; _on_target /dev/mapper/cryptroot || exit 16
  CRYPT_DEV=/dev/sda2; ! _on_target /dev/mapper/cryptroot || exit 17
  MODE=auto ROOT_PART= EFI_PART=
  _on_target /dev/nvme0n1p3 || exit 18          # auto: whole disk is the target
  ! _on_target /dev/sda1 || exit 19
' _ "$_fn" || fail "_on_target ownership check wrong (exit $?)"

# Reused ESP: back up loader.conf and the fallback loader, and say so up front.
grep -q 'for _bk in /boot/EFI/BOOT/BOOTX64.EFI /boot/loader/loader.conf; do' "$INSTALL_SH" \
  || fail "reused ESP must back up BOOTX64.EFI and loader.conf"
! grep -q 'BOOTX64.EFI.pre-arch.bak 2>/dev/null || true' "$INSTALL_SH" \
  || fail "ESP backup failure must be reported, not swallowed"
grep -q 'firmware fallback loader) is replaced' "$INSTALL_SH" \
  || fail "ESP reuse prompt must warn that BOOTX64.EFI and loader.conf change"

# NONINTERACTIVE must never block on a keypress or msgbox (VM test: the final
# "INSTALL COMPLETE" waited for [enter] forever with the target unmounted).
_fns=""
for _f in ui_fold ui_msg ui_restore_console die start_log stop_log on_exit; do
  _body="$(awk -v f="$_f" '$0 ~ "^"f"\\(\\) *\\{" {p=1} p{print} p&&/^}/{exit}' "$INSTALL_SH")"
  [[ -n $_body ]] || fail "could not extract $_f"
  _fns+="$_body"$'\n'
done
_ui() { # UI NONINTERACTIVE -> prints PAUSED / TUI if the message would block
  bash -c '
    eval "$1"
    plain_pause() { echo PAUSED; }; tui() { echo TUI; }
    UI=$2 NONINTERACTIVE=$3 W=70 APP_TITLE=t cR= cG= cY= cB= cC= c0=
    ui_msg ok "INSTALL COMPLETE" 2>/dev/null
  ' _ "$_fns" "$1" "$2"
}
[[ -z $(_ui plain 1) ]] || fail "NONINTERACTIVE plain message must not pause"
[[ -z $(_ui dialog 1) ]] || fail "NONINTERACTIVE dialog message must not open a msgbox"
[[ $(_ui plain 0) == PAUSED ]] || fail "interactive plain message must still pause"
# die after start_log: the error must reach the console AND the log.
_tmp="$(mktemp -d)"
_err="$(bash -c '
  eval "$1"
  cleanup_ui() { :; }; ui_critical() { echo CRIT; }; tui() { echo TUI; }
  UI=plain NONINTERACTIVE=1 LOGGING=0 LOG=$2 cR= c0= H=20 W=70
  start_log
  die "boom-on-console" 3
' _ "$_fns" "$_tmp/log" 2>&1 >/dev/null)" || true
grep -q 'ERR boom-on-console' <<<"$_err" || fail "die after start_log must print the error on the console"
grep -q 'ERR boom-on-console' "$_tmp/log" || fail "die after start_log must also record the error in the log"
rm -rf "$_tmp"
unset -f _ui

# t14s-selftest runs as the user (pipewire check): `ufw status` needs root.
_st="$(awk '/cat > \/usr\/local\/bin\/t14s-selftest <<.ST.$/{f=1;next} f&&/^ST$/{exit} f' "$INSTALL_SH")"
[[ -n $_st ]] || fail "could not extract t14s-selftest"
! grep -v '^[[:space:]]*#' <<<"$_st" | grep -q 'ufw status' \
  || fail "selftest must not call root-only 'ufw status'"
grep -q 'check_firewalld' <<<"$_st" \
  || fail "selftest must check firewalld"
grep -qE 'systemctl is-(enabled|active) --quiet firewalld' <<<"$_st" \
  || fail "selftest firewalld check must use systemctl"

# A set -e exit from inside a helper skips the (non-inherited) ERR trap; on_exit
# must still report it. die() must not be reported twice; rc 0 stays silent.
_tmp="$(mktemp -d)"
_run_exit() {
  bash -c '
    eval "$1"
    cleanup_ui() { :; }; ui_critical() { echo CRIT; }; tui() { echo TUI; }
    UI=plain NONINTERACTIVE=1 LOGGING=0 LOG=$2 cR= c0= H=20 W=70 T14S_DIED=0
    set -euo pipefail
    trap "die \"failed at line \$LINENO\" \$?" ERR
    trap "on_exit \$?" EXIT
    helper() { false; echo not-reached; }
    case $3 in
      helper) start_log; helper ;;
      die) die "explicit-die" 4 ;;
      ok) : ;;
    esac
  ' _ "$_fns" "$_tmp/log" "$1" 2>&1 >/dev/null
}
_err="$(_run_exit helper)" && fail "helper failure must exit non-zero"
grep -q 'ERR stopped unexpectedly (exit 1)' <<<"$_err" \
  || fail "on_exit must report a failure inside a helper on the console: $_err"
grep -q 'ERR stopped unexpectedly' "$_tmp/log" || fail "on_exit report must also reach the log"
_err="$(_run_exit die)" && fail "die must exit non-zero"
[[ $(grep -c '^ERR' <<<"$_err") -eq 1 ]] || fail "die must not be reported twice by on_exit: $_err"
[[ -z $(_run_exit ok) ]] || fail "clean exit must stay silent"
rm -rf "$_tmp"
unset -f _run_exit

# TRIM through LUKS, lsm= (not deprecated security=), plymouth before sd-encrypt.
grep -q 'rd.luks.options=discard' "$INSTALL_SH" || fail "cmdline must pass discards through LUKS (fstrim.timer)"
grep -q 'lsm=landlock,lockdown,yama,integrity,apparmor,bpf' "$INSTALL_SH" \
  || fail "cmdline must enable AppArmor via lsm="
! grep -v '^[[:space:]]*#' "$CHROOT_SH" | grep -q 'security=apparmor' || fail "security= is deprecated; use lsm="
while IFS= read -r _h; do
  if [[ $_h == *plymouth* ]]; then
    [[ ${_h%%plymouth*} != *sd-encrypt* ]] || fail "plymouth hook must precede sd-encrypt: $_h"
  fi
done < <(grep -o "HOOKS=([^)]*)" "$CHROOT_SH")
grep -q 'HOOKS=([^)]*plymouth sd-encrypt' "$CHROOT_SH" \
  || fail "missing plymouth HOOKS variant"

# Avahi needs the mdns service in the drop zone (replies are not conntracked).
_fw="$(awk '/^configure_firewalld\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$ROOT/lib/70-firewall.sh")"
grep -q 'INSTALL_AVAHI' <<<"$_fw" && grep -q -- '--add-service=mdns' <<<"$_fw" \
  || fail "configure_firewalld must allow mdns when INSTALL_AVAHI=Y"
_tmp="$(mktemp -d)"
mkdir -p "$_tmp/bin" "$_tmp/etc"
printf '#!/bin/sh\necho "$@" >>"%s/calls"\n' "$_tmp" >"$_tmp/bin/firewall-offline-cmd"
for _c in systemctl systemd-detect-virt firewall-cmd pacman; do printf '#!/bin/sh\nexit 1\n' >"$_tmp/bin/$_c"; done
chmod +x "$_tmp"/bin/*
_fwrun() {
  PATH="$_tmp/bin:$PATH" INSTALL_AVAHI=$1 FIREWALLD_CONF="$_tmp/etc/firewalld/firewalld.conf" bash -c '
    yn_on() { local v=${1,,}; [[ $v == y || $v == yes || $v == on || $v == 1 ]]; }
    source "$1"
    configure_firewalld >/dev/null' _ "$ROOT/lib/70-firewall.sh"
}
_fwrun Y; grep -qx -- '--add-service=mdns' "$_tmp/calls" || fail "INSTALL_AVAHI=Y must add mdns"
grep -qx 'DefaultZone=drop' "$_tmp/etc/firewalld/firewalld.conf" || fail "firewalld.conf must be seeded with DefaultZone=drop"
printf '%s\n' 'DefaultZone=public' 'FirewallBackend=iptables' >"$_tmp/etc/firewalld/firewalld.conf"
rm -f "$_tmp/calls"; _fwrun N
! grep -qs -- 'mdns' "$_tmp/calls" || fail "INSTALL_AVAHI=N must not open mdns"
[[ $(cat "$_tmp/etc/firewalld/firewalld.conf") == $'DefaultZone=drop\nFirewallBackend=nftables' ]] \
  || fail "existing firewalld.conf must be rewritten to drop + nftables"
rm -rf "$_tmp"
unset -f _fwrun

# P15 (Intel) must not get AMD-only post-boot checks.
_st="$(awk '/cat > \/usr\/local\/bin\/t14s-selftest <<.ST.$/{f=1;next} f&&/^ST$/{exit} f' "$INSTALL_SH")"
grep -q 'check intel_pstate' <<<"$_st" || fail "selftest must check intel_pstate on Intel (P15)"
grep -q 'GenuineIntel' <<<"$_st" || fail "selftest cpufreq check must branch on CPU vendor"
grep -q 'CMDLINE_HINT="grep -E .intel_iommu|nvidia_drm' "$WIZARD_SH" \
  || fail "P15 finish screen must check intel_iommu/nvidia_drm, not amd_*"
! grep -q 'Verify after boot: lscpu | grep -i ryzen' "$WIZARD_SH" \
  || fail "finish screen CPU hint must be profile-aware"

# Interrupt (INT/TERM) reports and exits without a dialog to dismiss.
_tmp="$(mktemp -d)"
_err="$(bash -c '
  eval "$1"
  cleanup_ui() { :; }; ui_critical() { echo CRIT >&2; }; tui() { echo TUI >&2; }
  UI=dialog NONINTERACTIVE=0 LOGGING=0 LOG=$2 cR= c0= H=20 W=70 T14S_DIED=0
  trap "on_exit \$?" EXIT
  exit 130
' _ "$_fns" "$_tmp/log" 2>&1 >/dev/null)" && fail "interrupt must exit non-zero"
grep -q 'ERR interrupted (signal 2)' <<<"$_err" || fail "interrupt must be reported: $_err"
! grep -q CRIT <<<"$_err" || fail "interrupt must not open a dialog"
rm -rf "$_tmp"

# reflector.conf: shlex-split per line, so a spaced country must stay one arg.
_rf="$(awk '/^# reflector mirrors/{f=1;next} f{print} f&&/^} > \/etc\/xdg\/reflector\/reflector.conf$/{exit}' "$CHROOT_SH")"
[[ -n $_rf ]] || fail "could not extract reflector.conf writer"
_rfout="$(REFLECTOR_COUNTRY='United States,DE' bash -c "${_rf%>*}")"
python3 -c 'import shlex,sys; a=[t for l in sys.stdin for t in shlex.split(l, comments=True)]; i=a.index("--country"); sys.exit(0 if a[i+1]=="United States,DE" else 1)' <<<"$_rfout" \
  || fail "reflector.conf --country must survive shlex splitting: $_rfout"

# Minor: one install log; ESP size in the step text; env toggles accept y/yes/on.
[[ $(grep -c '^LOG="\$(mktemp' "$ORCH_SH") -eq 1 ]] || fail "install.sh must create the log file once"
! grep -q '2G ESP + LUKS' "$WIZARD_SH" || fail "partition step text must use ESP_MB"
grep -q '_env_on "${T14S_ALLOW_NON_ISO:-0}"' "$WIZARD_SH" || fail "T14S_ALLOW_NON_ISO must accept y/yes/on"
grep -q '_env_on "${T14S_POST_HOOK_I_UNDERSTAND:-0}"' "$WIZARD_SH" \
  || fail "T14S_POST_HOOK_I_UNDERSTAND must accept y/yes/on"

# TUI geometry scales with the real console (pty via script(1)) and never
# exceeds it; size comes from /dev/tty even with every fd redirected.
if command -v script >/dev/null 2>&1; then
  _geo() { # rows cols [redirect] -> "H W LH MH MW"
    local cmd='source "$1"; ui_geometry; echo "GEO $H $W $LH $MH $MW"'
    [[ ${3:-} == redirect ]] && cmd='source "$1"; { ui_geometry; echo "GEO $H $W $LH $MH $MW" >&3; } 3>&1 </dev/null >/dev/null 2>&1'
    script -qec "stty rows $1 cols $2; bash -c '$cmd' _ '$UI_SH'" /dev/null 2>/dev/null \
      | tr -d '\r' | sed -n 's/^GEO //p'
  }
  [[ $(_geo 24 80) == "18 72 10 14 72" ]] || fail "80x24 geometry: $(_geo 24 80)"
  [[ $(_geo 37 120) == "24 84 16 14 84" ]] || fail "120x37 geometry: $(_geo 37 120)"
  [[ $(_geo 56 180) == "37 120 29 14 84" ]] || fail "T14s 2.8K 180x56 geometry: $(_geo 56 180)"
  [[ $(_geo 75 240) == "44 120 36 14 84" ]] || fail "WUXGA 240x75 geometry: $(_geo 75 240)"
  [[ $(_geo 56 180 redirect) == "37 120 29 14 84" ]] \
    || fail "geometry must read /dev/tty when all fds are redirected: $(_geo 56 180 redirect)"
  read -r _gh _gw _ <<<"$(_geo 10 40)"
  (( _gh <= 8 && _gw <= 38 )) || fail "tiny 40x10 console: box must fit the screen ($_gh x $_gw)"
  unset -f _geo; unset -v _gh _gw
else
  echo "skip TUI geometry pty checks (no script(1))"
fi
# whiptail cuts long msgbox/yesno text unless --scrolltext (REVIEW is 30+ lines),
# but --scrolltext moves focus into the text where Enter does nothing (every box
# looked frozen on the ISO console): scroll only bodies taller than the screen.
_um="$(awk '/^ui_msg\(\) *\{/{f=1} f{print} f&&/^}$/{exit}' "$UI_SH")"
grep -q 'msg_overflows "$show"' <<<"$_um" && grep -q 'scroll=(--scrolltext)' <<<"$_um" \
  || fail "whiptail msgbox must use --scrolltext only when the body overflows"
_uy="$(awk '/^ui_yesno\(\) *\{/{f=1} f{print} f&&/^}$/{exit}' "$UI_SH")"
grep -q 'msg_overflows "$folded"' <<<"$_uy" && grep -q 'extra+=(--scrolltext)' <<<"$_uy" \
  || fail "whiptail yesno must use --scrolltext only when the body overflows"
grep -qE '\[\[ \$UI == whiptail \]\] && (scroll=|extra\+=)\(--scrolltext\)' "$UI_SH" \
  && fail "unconditional whiptail --scrolltext is back (Enter ignored on every box)"
# msg_overflows: lines + 6 rows must fit XH.
_mo() { bash -c 'source "$1"; XH=$2; msg_overflows "$(seq 1 "$3")"' _ "$UI_SH" "$1" "$2"; }
_mo 20 14 && fail "14 lines fit a 20-row box (14+6)"
_mo 20 15 || fail "15 lines overflow a 20-row box"
unset -f _mo
# list_height: whiptail (--fullbuttons) shows only H - list - 8 prompt rows;
# dialog keeps LH and shrinks its list itself.
_lh() { bash -c 'source "$1"; UI=$2 H=37 W=$3 LH=29; list_height "$4"' _ "$UI_SH" "$@"; }
[[ $(_lh whiptail 120 $'prompt\n\nhint') == 26 ]] || fail "whiptail list must leave room for prompt+blank+hint+fullbuttons"
[[ $(_lh dialog 120 $'prompt\n\nhint') == 29 ]] || fail "dialog list height must stay LH"
[[ $(_lh whiptail 60 "$(printf 'x%.0s' $(seq 1 200))") == 25 ]] || fail "wrapped prompt rows must be counted (200 cols / 54)"
unset -f _lh
for _f in ui_menu ui_radio ui_checklist; do
  awk "/^${_f}\\(\\) *\\{/{f=1} f{print} f&&/^}\$/{exit}" "$UI_SH" | grep -q 'list_height "' \
    || fail "$_f must size its list with list_height"
done
unset -v _f
# Kernel messages tear the TUI on a VT: muted while it runs, restored first on exit.
awk '/^bootstrap_ui\(\) *\{/{f=1} f{print} f&&/^}$/{exit}' "$UI_SH" | grep -q 'ui_mute_console' \
  || fail "bootstrap_ui must mute kernel console messages"
for _f in die on_exit cleanup_ui; do
  awk "/^${_f}\\(\\) *\\{/{f=1} f{print} f&&/^}\$/{exit}" "$UI_SH" | sed -n 2,4p | grep -q 'ui_restore_console' \
    || fail "$_f must restore the console log level first"
done
unset -v _f
# Off a VT (this test's terminal) the console level is never touched.
[[ -z $(bash -c 'source "$1"; ui_mute_console; printf %s "${UI_PRINTK_SAVED:-}"' _ "$UI_SH") ]] \
  || fail "ui_mute_console must only act on a Linux VT"
# whiptail (ISO default) ignores Esc: its hints must not promise it.
_wh="$(awk '/^if \[\[ \$UI == whiptail \]\]; then$/{f=1} f{print} f&&/^fi$/{exit}' "$WIZARD_SH")"
grep -q 'TUI_HINT_RADIO=' <<<"$_wh" && ! grep -q 'Esc' <<<"$_wh" \
  || fail "whiptail hints must say Tab to Abort, not Esc"
# whiptail long steps: clear the last box before streaming live output.
awk '/^run_progress\(\) *\{/{f=1} f{print} f&&/^}$/{exit}' "$UI_SH" | grep -qF "\e[H\e[2J" \
  || fail "run_progress must clear the stale whiptail box"
unset -v _um _uy

# Partition/disk menus read lsblk -P: spaces stay readable (no "EFI\x20System")
# and an empty FSTYPE must not shift PARTTYPENAME into the fs column.
_tmp="$(mktemp -d)"
mkdir -p "$_tmp/bin"
cat >"$_tmp/bin/lsblk" <<'LSBLK'
#!/bin/sh
# Pairs output only for -P; anything else gets lsblk -r style (escaped spaces).
if [ "$1" != -pnP ]; then echo 'part /dev/nvme0n1p1 2.8G vfat EFI\x20System'; exit 0; fi
case "$*" in
  *TYPE,PATH,SIZE,FSTYPE,PARTTYPENAME*)
    echo 'TYPE="disk" PATH="/dev/nvme0n1" SIZE="953.9G" FSTYPE="" PARTTYPENAME=""'
    echo 'TYPE="part" PATH="/dev/nvme0n1p1" SIZE="2.8G" FSTYPE="vfat" PARTTYPENAME="EFI System"'
    echo 'TYPE="part" PATH="/dev/nvme0n1p2" SIZE="16M" FSTYPE="" PARTTYPENAME="Microsoft reserved"'
    echo 'TYPE="part" PATH="/dev/nvme0n1p5" SIZE="805.4G" FSTYPE="crypto_LUKS" PARTTYPENAME="Linux filesystem"'
    echo 'TYPE="crypt" PATH="/dev/mapper/cryptroot" SIZE="805.4G" FSTYPE="btrfs" PARTTYPENAME=""' ;;
  *SIZE,MODEL*) echo 'SIZE="953.9G" MODEL="SAMSUNG MZVL21T0HCLR-00BL7"' ;;
esac
LSBLK
chmod +x "$_tmp/bin/lsblk"
_menu="$(PATH="$_tmp/bin:$PATH" bash -c '
  source "$1"; arr=(); build_part_menu arr /dev/nvme0n1
  printf "%s\n" "${arr[@]}"' _ "$ROOT/lib/00-common.sh" | paste -d'|' - -)"
grep -qxF '/dev/nvme0n1p1|2.8G    vfat        EFI System' <<<"$_menu" || fail "partition menu row p1: $_menu"
grep -qxF '/dev/nvme0n1p2|16M     empty       Microsoft reserved' <<<"$_menu" \
  || fail "empty FSTYPE must stay empty, not take PARTTYPENAME: $_menu"
! grep -q 'x20\|cryptroot\|953.9G' <<<"$_menu" || fail "menu must list partitions only, unescaped: $_menu"
_model="$(PATH="$_tmp/bin:$PATH" bash -c 'source "$1"; IFS=$'"'"'\x1f'"'"' read -r s m < <(lsblk_rows /dev/nvme0n1 SIZE MODEL); echo "$s|$m"' _ "$ROOT/lib/00-common.sh")"
[[ $_model == '953.9G|SAMSUNG MZVL21T0HCLR-00BL7' ]] || fail "disk model must keep spaces: $_model"
! grep -q 'dnro SIZE,MODEL\|prno TYPE,PATH' "$WIZARD_SH" "$ROOT/lib/00-common.sh" || fail "menus must not use lsblk -r (escapes spaces)"
rm -rf "$_tmp"; unset -v _menu _model

# msg_height counts the last (unterminated) line: 2 lines + 6 rows overhead.
[[ $(bash -c 'source "$1"; MH=1 H=50 XH=50; msg_height "a
b"' _ "$UI_SH") == 8 ]] || fail "msg_height must count the final line"

# The erase / manual-layout screens must fit an 80x24 console (message box
# limit 20 rows = 14 text rows): badge 2 + intro + table (header, disk, parts).
for _scr in 'ui_critical "AUTO mode ERASES' 'ui_info "Manual partitioning on'; do
  _n="$(awk -v s="$_scr" 'index($0, s){f=1} f{n++} f&&/^\$\(lsblk -o NAME/{print n; exit}' "$WIZARD_SH")"
  [[ -n $_n ]] || fail "could not find screen: $_scr"
  (( _n - 1 <= 4 )) || fail "screen '$_scr' has $(( _n - 1 )) intro lines; keep ≤4 so a 5-partition table fits 80x24"
done
unset -v _scr _n

# prefetch_pkgs: downloads retried (mirror resets aborted pacstrap mid-install);
# pacstrap runs once, after a successful prefetch, from the target cache.
_pfx="$(mktemp -d)"; mkdir -p "$_pfx/bin"
cat >"$_pfx/bin/pacman" <<EOF
#!/bin/sh
echo "\$*" >>"$_pfx/calls"
n=\$(wc -l <"$_pfx/calls")
[ "\$n" -ge "\${PF_OK_AT:-3}" ]
EOF
chmod +x "$_pfx/bin/pacman"
_pfrun() { PATH="$_pfx/bin:$PATH" PREFETCH_BACKOFF=0 bash -c 'source "$1"; shift; prefetch_pkgs "$@"' _ \
  "$ROOT/lib/50-packages.sh" "$_pfx/cache" base linux 2>&1; }
_o="$(PF_OK_AT=3 _pfrun)" || fail "prefetch must succeed on the 3rd attempt: $_o"
[[ $(wc -l <"$_pfx/calls") -eq 3 ]] || fail "prefetch must retry until success"
grep -q -- "-Syw --noconfirm --dbpath .* --cachedir $_pfx/cache -- base linux" "$_pfx/calls" \
  || fail "prefetch must download only, into the target cache, with a private db: $(head -1 "$_pfx/calls")"
[[ $(grep -c retrying <<<"$_o") -eq 2 ]] || fail "each failed attempt must say it retries: $_o"
rm -f "$_pfx/calls"
_o="$(PF_OK_AT=99 PREFETCH_TRIES=3 _pfrun)" && fail "prefetch must fail after the last attempt" || true
[[ $(wc -l <"$_pfx/calls") -eq 3 ]] && grep -q 'giving up' <<<"$_o" || fail "must stop after PREFETCH_TRIES and say so: $_o"
_pf_line="$(grep -n 'prefetch_pkgs /mnt/var/cache/pacman/pkg' "$WIZARD_SH" | cut -d: -f1)"
_ps_line="$(grep -n 'pacstrap -K /mnt' "$WIZARD_SH" | head -1 | cut -d: -f1)"
[[ -n $_pf_line && -n $_ps_line ]] && (( _pf_line < _ps_line )) || fail "install.sh must prefetch before pacstrap"
grep -A2 'prefetch_pkgs /mnt/var/cache/pacman/pkg' "$WIZARD_SH" | grep -q '|| die' \
  || fail "a failed prefetch must stop before pacstrap touches the root"
grep -q 'chmod 0755 "$db"' "$ROOT/lib/50-packages.sh" \
  || fail "prefetch db dir must be traversable by pacman's download user (alpm sandbox)"
rm -rf "$_pfx"; unset -v _pfx _o _pf_line _ps_line; unset -f _pfrun

# Firmware boot entry: bootctl in the chroot writes no EFI variables, so the
# host creates "Linux Boot Manager" for the chosen ESP and drops stale ones.
_efi_fx='BootCurrent: 001C
BootOrder: 0003,0001,0002,001C
Boot0001* Linux Boot Manager	HD(1,GPT,0a1d6820-8fd4-47d9-be7c-79d7fdcf6c40,0x800,0x200000)/\EFI\systemd\systemd-bootx64.efi
Boot0002* Fallback Linux Boot Manager	HD(1,GPT,0a1d6820-8fd4-47d9-be7c-79d7fdcf6c40,0x800,0x200000)/\EFI\systemd\systemd-boot-fallbackx64.efi
Boot0003* Windows Boot Manager	HD(1,GPT,CC7AE317-8288-40F3-BFEE-A6983A51C9B5,0x800,0x578000)/\EFI\Microsoft\Boot\bootmgfw.efi
Boot001C* NVMe0	VenMsg(bc7838d2-0f82-4d60-8316-c068ee79d25b,001c)'
_hw() { bash -c 'warn(){ :; }; say(){ :; }; ok(){ :; }; source "$1"; shift; "$@"' _ "$ROOT/lib/30-hardware.sh" "$@"; }
_o="$(_hw sdboot_plan cc7ae317-8288-40f3-bfee-a6983a51c9b5 <<<"$_efi_fx")"
[[ $_o == $'delete 0001\ndelete 0002\ncreate' ]] || fail "stale Linux Boot Manager entries must go, Windows stays, new entry created: $_o"
_o="$(_hw sdboot_plan 0A1D6820-8FD4-47D9-BE7C-79D7FDCF6C40 <<<"$_efi_fx")"
[[ $_o == 'keep 0001' ]] || fail "an entry already on this ESP must be kept (fallback too), not recreated: $_o"
[[ $(_hw sdboot_plan 11111111-2222-3333-4444-555555555555 <<<'BootOrder: 0000') == create ]] || fail "empty NVRAM must create"
[[ $(_hw boot_order_front 0001 <<<"$_efi_fx") == 0001,0003,0002,001C ]] || fail "boot_order_front must move the entry first"
_ebe="$(grep -n 'ensure_boot_entry "$EFI_PART"' "$WIZARD_SH" | cut -d: -f1)"
_cc="$(grep -n 'ok "chroot config complete"' "$WIZARD_SH" | cut -d: -f1)"
_iw="$(grep -n '^INSTALL_WARNINGS=""' "$WIZARD_SH" | cut -d: -f1)"
[[ -n $_ebe && -n $_cc && -n $_iw ]] && (( _cc < _ebe && _ebe < _iw )) \
  || fail "install.sh must write the firmware entry after the chroot and before warnings are collected"
grep -A5 'ensure_boot_entry "$EFI_PART"' "$WIZARD_SH" | grep -q 't14s-warnings.txt' \
  || fail "a missing firmware entry must be listed as an install warning"
grep -B2 -A2 '_ef_reuse=on; _ef_fmt=off' "$WIZARD_SH" | grep -q 'grep -qx vfat' \
  || fail "MANUAL must default to reusing an existing FAT32 ESP (formatting kills Windows' loader)"
unset -v _efi_fx _o _ebe _cc _iw; unset -f _hw

# Audit & generic profile checks:
# 1. Answers load BEFORE hardware detection so HW_PROFILE from T14S_ANSWERS applies.
_ans_line="$(grep -n 'answers_load "\$ANSWERS_IN"' "$WIZARD_SH" | head -1 | cut -d: -f1)"
_hw_line="$(grep -n 'target profile: Generic x86_64' "$WIZARD_SH" | head -1 | cut -d: -f1)"
[[ -n $_ans_line && -n $_hw_line ]] && (( _ans_line < _hw_line )) \
  || fail "answers must load before hardware profile detection (ans=$_ans_line hw=$_hw_line)"
unset -v _ans_line _hw_line

# 2. FORMAT_EFI fails closed (never silently turns N/bogus into format=1).
! grep -q 'FORMAT_EFI:-1} =~ \^\[01\]\$ \]\] || FORMAT_EFI=1' "$WIZARD_SH" \
  || fail "FORMAT_EFI must fail closed, never default invalid values to 1 (format)"
grep -q 'NONINTERACTIVE MANUAL needs FORMAT_EFI=0|1' "$WIZARD_SH" \
  || fail "FORMAT_EFI must die on invalid values"

# 3. valid_locale requires UTF-8 (rejects ISO-8859-1 entries that break locale-gen).
_ltmp="$(mktemp -d)"
printf '%s\n' 'en_US.UTF-8 UTF-8' 'en_US ISO-8859-1' 'de_DE@euro ISO-8859-15' >"$_ltmp/locales"
T14S_IDENTITY_OVERRIDES=1 LOCALE_FILES="$_ltmp/locales" \
  bash -c 'source "$1"; valid_locale en_US.UTF-8' _ "$ROOT/lib/00-common.sh" \
  || fail "valid_locale must accept UTF-8 entry"
T14S_IDENTITY_OVERRIDES=1 LOCALE_FILES="$_ltmp/locales" \
  bash -c 'source "$1"; valid_locale en_US' _ "$ROOT/lib/00-common.sh" \
  && fail "valid_locale must reject non-UTF-8 en_US ISO-8859-1" || true
T14S_IDENTITY_OVERRIDES=1 LOCALE_FILES="$_ltmp/locales" \
  bash -c 'source "$1"; valid_locale de_DE@euro' _ "$ROOT/lib/00-common.sh" \
  && fail "valid_locale must reject non-UTF-8 de_DE@euro" || true
rm -rf "$_ltmp"; unset -v _ltmp

# 4. Generic hardware detection helpers (CPU vendor, GPU vendors, x86-64-v3).
_gtmp="$(mktemp -d)"
mkdir -p "$_gtmp/pci/0000:00:02.0" "$_gtmp/pci/0000:01:00.0" "$_gtmp/pci/0000:02:00.0"
printf '0x030000\n' >"$_gtmp/pci/0000:00:02.0/class"
printf '0x8086\n'   >"$_gtmp/pci/0000:00:02.0/vendor"
printf '0x030200\n' >"$_gtmp/pci/0000:01:00.0/class"
printf '0x10de\n'   >"$_gtmp/pci/0000:01:00.0/vendor"
printf '0x020000\n' >"$_gtmp/pci/0000:02:00.0/class"
printf '0x1002\n'   >"$_gtmp/pci/0000:02:00.0/vendor"
_gpus="$(T14S_PCI_DIR="$_gtmp/pci" bash -c 'source "$1"; detect_gpu_vendors' _ "$ROOT/lib/30-hardware.sh")"
[[ $_gpus == "intel nvidia" ]] || fail "detect_gpu_vendors expected 'intel nvidia', got '$_gpus'"
printf 'vendor_id\t: AuthenticAMD\nflags\t: avx2 bmi1 bmi2 fma movbe f16c\n' >"$_gtmp/cpu_amd"
printf 'vendor_id\t: GenuineIntel\nflags\t: sse2\n' >"$_gtmp/cpu_intel"
[[ $(T14S_CPUINFO="$_gtmp/cpu_amd" bash -c 'source "$1"; detect_cpu_vendor' _ "$ROOT/lib/30-hardware.sh") == amd ]] \
  || fail "detect_cpu_vendor must detect amd"
[[ $(T14S_CPUINFO="$_gtmp/cpu_intel" bash -c 'source "$1"; detect_cpu_vendor' _ "$ROOT/lib/30-hardware.sh") == intel ]] \
  || fail "detect_cpu_vendor must detect intel"
T14S_CPUINFO="$_gtmp/cpu_amd" bash -c 'source "$1"; cpu_has_x86_64_v3' _ "$ROOT/lib/30-hardware.sh" \
  || fail "cpu_has_x86_64_v3 must succeed when all v3 flags present"
T14S_CPUINFO="$_gtmp/cpu_intel" bash -c 'source "$1"; cpu_has_x86_64_v3' _ "$ROOT/lib/30-hardware.sh" \
  && fail "cpu_has_x86_64_v3 must fail on sse2-only CPU fixture" || true

# Behavioral: 08-gnome.sh Wayland/udev/GDM writer blocks must survive set -euo pipefail
# across all generic GPU combinations (VM empty, AMD-only, Intel-only, NVIDIA-only).
_gblk="$(awk '/_libva=""/{f=1} f{print} /unset -v _libva _gpus/{exit}' "$ROOT/lib/chroot/08-gnome.sh")"
[[ -n $_gblk ]] || fail "could not extract 08-gnome.sh Wayland/udev block"
for _case in "generic|" "generic| amd " "generic| intel " "generic| nvidia "; do
  _prof=${_case%%|*}
  _gv=${_case#*|}
  _gout="$_gtmp/g_${_prof}_${_gv// /}"
  mkdir -p "$_gout/etc/environment.d" "$_gout/etc/udev/rules.d" "$_gout/etc/systemd/system/gdm.service.d"
  _gblk_rw="${_gblk//\/etc\//$_gout\/etc\/}"
  HW_PROFILE="$_prof" _gpus="$_gv" bash -c "set -euo pipefail; $_gblk_rw" \
    || fail "08-gnome.sh Wayland/udev block failed under set -e for HW_PROFILE=$_prof _gpus='$_gv'"
  [[ -s $_gout/etc/environment.d/99-wayland.conf ]] \
    || fail "08-gnome.sh did not write 99-wayland.conf for '$_gv'"
done
[[ ! -e "$_gtmp/g_generic_/etc/udev/rules.d/61-gdm-wayland.rules" ]] \
  || fail "VM/empty GPU generic must not write vendor-specific 61-gdm-wayland.rules"
grep -q 'ATTRS{vendor}=="0x1002"' "$_gtmp/g_generic_amd/etc/udev/rules.d/61-gdm-wayland.rules" \
  || fail "generic AMD must write 0x1002 udev rule"
grep -q 'LIBVA_DRIVER_NAME=iHD' "$_gtmp/g_generic_intel/etc/environment.d/99-wayland.conf" \
  || fail "generic Intel must set LIBVA_DRIVER_NAME=iHD"
! grep -q 'LIBVA_DRIVER_NAME=' "$_gtmp/g_generic_nvidia/etc/environment.d/99-wayland.conf" \
  || fail "generic NVIDIA-only must not set bogus LIBVA_DRIVER_NAME"

# Behavioral: FORMAT_EFI fails closed (N->0, 1->1, bogus->die).
_fe_blk="$(awk '/case \$\{FORMAT_EFI:-1\} in/{f=1} f{print} f&&/esac/{exit}' "$ROOT/lib/steps/07-partition.sh")"
[[ $(FORMAT_EFI=N bash -c "set -euo pipefail; die(){ exit 9; }; $_fe_blk; echo \$FORMAT_EFI") == 0 ]] \
  || fail "FORMAT_EFI=N must map to 0 (reuse)"
[[ $(FORMAT_EFI=Y bash -c "set -euo pipefail; die(){ exit 9; }; $_fe_blk; echo \$FORMAT_EFI") == 1 ]] \
  || fail "FORMAT_EFI=Y must map to 1 (format)"
FORMAT_EFI=bogus bash -c "set -euo pipefail; die(){ exit 9; }; $_fe_blk" 2>/dev/null \
  && fail "FORMAT_EFI=bogus must die" || true

# Behavioral: PRESET in NONINTERACTIVE fails closed on unknown preset.
PRESET=minmal NONINTERACTIVE=1 bash -c '
  set -euo pipefail
  die() { echo "DIE:$*" >&2; exit 9; }
  ui_step() { :; }
  detect_vm_thinkpad_skip() { IS_VM=0; SKIP_THINKPAD_HW=N; }
  source "$1"
' _ "$ROOT/lib/steps/05-profile.sh" 2>"$_gtmp/pre.err" \
  && fail "NONINTERACTIVE PRESET=minmal must die" || true
grep -q 'DIE:NONINTERACTIVE needs PRESET=gnome|dev|minimal|vm' "$_gtmp/pre.err" \
  || fail "unexpected error on invalid PRESET: $(cat "$_gtmp/pre.err")"

# Behavioral: _extra_onoff + real _extras_keep block from 11-extras.sh keep free-form extras and drop unchecked items (including htop).
_ex_keep="$(awk '/^[[:space:]]+_extras_keep=\(\)/{f=1} f{print} f&&/^[[:space:]]+unset -v _p$/{exit}' "$ROOT/lib/steps/11-extras.sh")"
[[ -n $_ex_keep ]] || fail "could not extract _extras_keep block from 11-extras.sh"
_ex_out="$(bash -c '
  set -euo pipefail
  eval "$(awk "/^_extra_onoff\\(\\)/{f=1} f{print} f&&/^}\$/{exit}" "$1")"
  EXTRA_PKGS=(htop tmux my-custom-pkg)
  [[ $(_extra_onoff htop) == on && $(_extra_onoff tmux) == on && $(_extra_onoff rsync) == off ]] || exit 2
  eval "$2"
  printf "%s\n" "${_extras_keep[*]}"
' _ "$ROOT/lib/steps/11-extras.sh" "$_ex_keep")"
[[ $_ex_out == "my-custom-pkg" ]] \
  || fail "_extras_keep must keep free-form pkgs and drop unchecked checklist items including htop (got: $_ex_out)"
rm -rf "$_gtmp"; unset -v _gtmp _gpus _gblk _gblk_rw _case _prof _gv _gout _fe_blk _ex_keep _ex_out

# 5. No dead GNOME 51 experimental-features; whiptail maps to libnewt; cleanup_ui cleans fetch dir;
#    AUTO review uses planned sizes; T14S_POST_HOOK_SHA256 validated before wipe & lowercased.
! grep -q 'experimental-features' "$CHROOT_SH" \
  || fail "removed GNOME 51 mutter experimental-features must not be written"
grep -q 'whiptail \]\] && _ui_pkg=libnewt' "$UI_SH" \
  || fail "bootstrap_ui must install libnewt when T14S_UI=whiptail"
grep -q 'T14S_LIB_FETCH_DIR' "$ROOT/lib/10-ui.sh" \
  || fail "cleanup_ui must remove T14S_LIB_FETCH_DIR"
grep -q '_rev_efi_mb="\$ESP_MB"' "$WIZARD_SH" \
  || fail "12-review.sh must show planned ESP_MB in AUTO mode"
grep -q 'T14S_POST_HOOK_SHA256 must be 64 hex chars' "$WIZARD_SH" \
  || fail "12-review.sh must validate T14S_POST_HOOK_SHA256 before wipe"
grep -q 'T14S_POST_HOOK_SHA256,,' "$WIZARD_SH" \
  || fail "post-hook SHA-256 comparison must accept uppercase hex"
grep -q 'NONINTERACTIVE needs PRESET=gnome|dev|minimal|vm' "$WIZARD_SH" \
  || fail "NONINTERACTIVE must reject unknown PRESET instead of defaulting to gnome"
grep -q 'syncthing=\$FW_SYNCTHING kdeconnect=\$FW_KDECONNECT' "$WIZARD_SH" \
  || fail "12-review.sh must surface FW_SYNCTHING and FW_KDECONNECT"
grep -q 'ollama=\$INSTALL_OLLAMA starship=\$INSTALL_STARSHIP' "$WIZARD_SH" \
  || fail "12-review.sh must surface INSTALL_OLLAMA and INSTALL_STARSHIP"
grep -q 'selftest=\$INSTALL_SELFTEST chrome=\$INSTALL_CHROME_HINT thinkfan=\$INSTALL_THINKFAN' "$WIZARD_SH" \
  || fail "12-review.sh must surface helper toggles"
grep -q '_rev_power='\''tlp'\''' "$WIZARD_SH" \
  || fail "12-review.sh must accurately show Power=tlp/none on minimal/headless"
grep -q 'yn_on "\${INSTALL_BLUETOOTH:-N}"' "$ROOT/lib/50-packages.sh" \
  || fail "50-packages.sh must gate bluez/bluez-utils on INSTALL_BLUETOOTH"
grep -q 'yn_on "\${INSTALL_BLUETOOTH:-N}"' "$ROOT/lib/chroot/07-services-snapshots.sh" \
  || fail "07-services-snapshots.sh must gate bluetooth.service on INSTALL_BLUETOOTH"
grep -q 'yn_on "\${INSTALL_FLATPAK_APPS:-N}"' "$ROOT/lib/chroot/08-gnome.sh" \
  || fail "08-gnome.sh must gate first-boot flatpak apps on INSTALL_FLATPAK_APPS"
grep -q '/sys/bus/thunderbolt/devices' "$ROOT/lib/chroot/08-gnome.sh" \
  || fail "08-gnome.sh must gate bolt on Thunderbolt hardware or ThinkPad profile"
grep -q 'INSTALL_FLATPAK_APPS=N' "$ROOT/lib/steps/11-extras.sh" \
  || fail "11-extras.sh must force INSTALL_FLATPAK_APPS=N when DESKTOP=N"
# Behavioral: t14s_base_packages omits bluez and optional kernels by default; adds them only when enabled.
_bp_off="$(bash -c 'source "$1"; source "$2"; UCODE=amd-ucode INSTALL_BLUETOOTH=N t14s_base_packages; printf "%s\n" "${BASE_PKGS[@]}"' \
  _ "$ROOT/lib/00-common.sh" "$ROOT/lib/50-packages.sh")"
_bp_on="$(bash -c 'source "$1"; source "$2"; UCODE=amd-ucode INSTALL_BLUETOOTH=Y INSTALL_LINUX_HARDENED=Y INSTALL_LINUX_STABLE=Y INSTALL_LINUX_ZEN=Y t14s_base_packages; printf "%s\n" "${BASE_PKGS[@]}"' \
  _ "$ROOT/lib/00-common.sh" "$ROOT/lib/50-packages.sh")"
grep -qx 'linux-lts' <<<"$_bp_off" && grep -qx 'linux-lts-headers' <<<"$_bp_off" \
  || fail "t14s_base_packages default must include linux-lts + headers"
! grep -qxE 'bluez|bluez-utils|htop|btop|fastfetch|github-cli|glab|linux-hardened|linux|linux-zen' <<<"$_bp_off" \
  || fail "t14s_base_packages default must omit bluez/optional kernels/moved CLIs"
for _p in bluez bluez-utils linux-hardened linux-hardened-headers linux linux-headers linux-zen linux-zen-headers; do
  grep -qx "$_p" <<<"$_bp_on" || fail "t14s_base_packages (opt-ins=Y) missing $_p"
done
unset -v _bp_off _bp_on _p

# Behavioral: 05-profile.sh INSTALL_BLUETOOTH defaults (N on VM/minimal, Y on bare-metal gnome/dev, answers override).
_bt_prof() {
  local is_vm=$1 preset=$2 ans_bt=${3-}
  NONINTERACTIVE=1 PRESET="$preset" INSTALL_BLUETOOTH="$ans_bt" bash -c '
    set -euo pipefail
    ui_step() { :; }; die() { exit 9; }; apply_extra_pkgs_list() { :; }
    detect_vm_thinkpad_skip() { IS_VM='"$is_vm"'; SKIP_THINKPAD_HW=N; }
    source "$1"
    printf "%s\n" "$INSTALL_BLUETOOTH"
  ' _ "$ROOT/lib/steps/05-profile.sh"
}
[[ $(_bt_prof 1 gnome "") == N ]] || fail "05-profile gnome on VM must default INSTALL_BLUETOOTH=N"
[[ $(_bt_prof 0 gnome "") == Y ]] || fail "05-profile gnome on bare metal must default INSTALL_BLUETOOTH=Y"
[[ $(_bt_prof 0 dev   "") == Y ]] || fail "05-profile dev on bare metal must default INSTALL_BLUETOOTH=Y"
[[ $(_bt_prof 0 minimal "") == N ]] || fail "05-profile minimal must default INSTALL_BLUETOOTH=N"
[[ $(_bt_prof 1 gnome Y) == Y ]] || fail "05-profile must honor explicit INSTALL_BLUETOOTH=Y on VM"
[[ $(_bt_prof 0 gnome N) == N ]] || fail "05-profile must honor explicit INSTALL_BLUETOOTH=N on bare metal"
unset -f _bt_prof

# Behavioral: 11-extras.sh forces INSTALL_FLATPAK_APPS=N when DESKTOP=N.
_fp_gate="$(NONINTERACTIVE=1 DESKTOP=N INSTALL_FLATPAK_APPS=Y INSTALL_BTRFS_ASSISTANT=N INSTALL_TLP=N INSTALL_TUNED=N SKIP_THINKPAD_HW=N bash -c '
  set -euo pipefail
  source "$1"
  ui_step() { :; }; warn() { :; }; ui_warn() { :; }
  EXTRA_PKGS=()
  source "$2"
  printf "%s\n" "$INSTALL_FLATPAK_APPS"
' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/steps/11-extras.sh")"
[[ $_fp_gate == N ]] || fail "11-extras.sh must force INSTALL_FLATPAK_APPS=N when DESKTOP=N (got: $_fp_gate)"
unset -v _fp_gate

# Behavioral: 08-gnome.sh bolt gating respects HW_PROFILE and yn_on(SKIP_THINKPAD_HW).
_bolt_blk="$(awk '/^  _enable_bolt=0$/{f=1} f{print} f&&/^  fi$/{exit}' "$ROOT/lib/chroot/08-gnome.sh")"
[[ -n $_bolt_blk ]] || fail "could not extract _enable_bolt block from 08-gnome.sh"
_bolt_run() {
  HW_PROFILE=$1 SKIP_THINKPAD_HW=$2 bash -c '
    set -euo pipefail
    yn_on() { local v=${1,,}; [[ $v == y || $v == yes || $v == on || $v == 1 ]]; }
    compgen() { return 1; }
    _gnome_pkgs=()
    eval "$1"
    printf "%s:%s\n" "$_enable_bolt" "${_gnome_pkgs[*]:-}"
  ' _ "$_bolt_blk"
}
[[ $(_bolt_run generic N) == "0:" ]] || fail "generic without TB must skip bolt"
[[ $(_bolt_run t14s    N) == "1:bolt" ]] || fail "t14s bare metal must enable bolt"
[[ $(_bolt_run t14s    1) == "0:" ]] || fail "t14s with SKIP_THINKPAD_HW=1 must skip bolt"
unset -v _bolt_blk; unset -f _bolt_run

# Behavioral: t14s-selftest skips bluetooth & pipewire when packages are absent.
_st_tmp="$(mktemp -d)"
awk "/cat > \/usr\/local\/bin\/t14s-selftest <<'ST'/{f=1;next} f&&/^ST$/{exit} f" \
  "$ROOT/lib/chroot/11-helpers-selftest.sh" >"$_st_tmp/selftest.sh"
[[ -s $_st_tmp/selftest.sh ]] || fail "could not extract t14s-selftest"
mkdir -p "$_st_tmp/bin"
cat >"$_st_tmp/bin/pacman" <<'EOF'
#!/bin/sh
exit 1
EOF
cat >"$_st_tmp/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$_st_tmp/bin/nmcli" <<'EOF'
#!/bin/sh
echo "full"
EOF
chmod +x "$_st_tmp/bin/"*
_st_out="$(PATH="$_st_tmp/bin:/usr/bin:/bin" bash "$_st_tmp/selftest.sh" 2>&1 || true)"
! grep -q 'bluetooth' <<<"$_st_out" || fail "t14s-selftest must skip bluetooth when bluez absent: $_st_out"
! grep -q 'pipewire' <<<"$_st_out" || fail "t14s-selftest must skip pipewire when pipewire absent: $_st_out"
grep -q "grep -qw 'mem_sleep_default=s2idle' /proc/cmdline" "$_st_tmp/selftest.sh" \
  || fail "t14s-selftest must gate mem_sleep on /proc/cmdline (not s2idle.conf)"
grep -q 'host_profile != generic.*mem_sleep_default=s2idle' "$ROOT/tests/host-check.sh" \
  || fail "host-check.sh must gate mem_sleep_default=s2idle on non-generic profile/cmdline"
rm -rf "$_st_tmp"; unset -v _st_tmp _st_out

# Behavioral: ROOT_FS=btrfs|ext4|xfs wiring, packages, extras gating, and kernel cmdline.
grep -q 'ROOT_FS' "$ROOT/lib/steps/03-answers.sh" \
  && grep -q 'ROOT_FS="\${ROOT_FS:-btrfs}"' "$ROOT/lib/steps/23-install-chroot.sh" \
  && grep -q 'mkfs\.ext4' "$ROOT/lib/40-disk.sh" \
  && grep -q 'mkfs\.xfs' "$ROOT/lib/40-disk.sh" \
  && grep -q 'ROOT_FS:-btrfs.*== btrfs' "$ROOT/lib/chroot/07-services-snapshots.sh" \
  || fail "ROOT_FS must be wired across answers, chroot env, disk formatters, and snapper gate"

_fs_pkgs() {
  ROOT_FS=$1 UCODE=amd-ucode INSTALL_BLUETOOTH=N bash -c '
    source "$1"; source "$2"; t14s_base_packages; printf "%s\n" "${BASE_PKGS[@]}"
  ' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/50-packages.sh"
}
_p_btrfs="$(_fs_pkgs btrfs)"
_p_ext4="$(_fs_pkgs ext4)"
_p_xfs="$(_fs_pkgs xfs)"
grep -qx 'btrfs-progs' <<<"$_p_btrfs" && grep -qx 'snapper' <<<"$_p_btrfs" && grep -qx 'snap-pac' <<<"$_p_btrfs" \
  || fail "ROOT_FS=btrfs must include btrfs-progs, snapper, snap-pac"
grep -qx 'e2fsprogs' <<<"$_p_ext4" && ! grep -qxE 'btrfs-progs|snapper|snap-pac|xfsprogs' <<<"$_p_ext4" \
  || fail "ROOT_FS=ext4 must include e2fsprogs and omit btrfs/snapper/xfs tools"
grep -qx 'xfsprogs' <<<"$_p_xfs" && ! grep -qxE 'btrfs-progs|snapper|snap-pac|e2fsprogs' <<<"$_p_xfs" \
  || fail "ROOT_FS=xfs must include xfsprogs and omit btrfs/snapper/ext4 tools"
unset -v _p_btrfs _p_ext4 _p_xfs; unset -f _fs_pkgs

# 10-downloads.sh validates & lowercases ROOT_FS in NONINTERACTIVE, and skips BTRFS_COMPRESS radio on ext4/xfs.
for _fs in btrfs ext4 xfs EXT4 XFS; do
  _got_fs="$(NONINTERACTIVE=1 PACMAN_PARALLEL=10 ROOT_FS="$_fs" BTRFS_COMPRESS=zstd3 ZRAM_SIZE=half bash -c '
    set -euo pipefail; ui_step() { :; }; die() { exit 9; }; source "$1"; printf "%s\n" "$ROOT_FS"
  ' _ "$ROOT/lib/steps/10-downloads.sh")" || fail "10-downloads.sh rejected valid ROOT_FS=$_fs"
  [[ $_got_fs == "${_fs,,}" ]] || fail "10-downloads.sh must lowercase ROOT_FS=$_fs (got: $_got_fs)"
done
NONINTERACTIVE=1 PACMAN_PARALLEL=10 ROOT_FS=ntfs BTRFS_COMPRESS=zstd3 ZRAM_SIZE=half bash -c '
  set -euo pipefail; ui_step() { :; }; die() { exit 9; }; source "$1"
' _ "$ROOT/lib/steps/10-downloads.sh" 2>/dev/null \
  && fail "10-downloads.sh must reject invalid ROOT_FS=ntfs" || true
_dl_prompts="$(NONINTERACTIVE=0 PACMAN_PARALLEL=10 ROOT_FS=ext4 BTRFS_COMPRESS=zstd3 ZRAM_SIZE=half bash -c '
  set -euo pipefail; ui_step() { :; }; die() { exit 9; }
  ui_radio() {
    printf "%s\n" "$1" >&2
    case "$1" in
      *ParallelDownloads*) echo 10 ;;
      *Root\ filesystem*) echo ext4 ;;
      *zram*) echo half ;;
      *) echo "UNEXPECTED:$1" >&2; exit 8 ;;
    esac
  }
  source "$1"
' _ "$ROOT/lib/steps/10-downloads.sh" 2>&1)" || fail "10-downloads.sh interactive ext4 failed: $_dl_prompts"
! grep -q 'Btrfs compression' <<<"$_dl_prompts" \
  || fail "10-downloads.sh must skip Btrfs compression prompt when ROOT_FS=ext4"
unset -v _fs _got_fs _dl_prompts

# Behavioral: do_filesystems_and_mount formats ext4/xfs with noatime + no btrfs calls, and rejects invalid ROOT_FS.
_dfm_tmp="$(mktemp -d)"
_dfm_run() {
  local fs=$1
  local log="$_dfm_tmp/calls_${fs}"
  : >"$log"
  ROOT_FS="$fs" FORMAT_EFI=0 EFI_PART=/dev/fake1 CLEAN_ESP_ARCH=N DFM_LOG="$log" bash -c '
    set -euo pipefail
    step() { :; }; ok() { :; }; warn() { :; }; die() { echo "DIE:$*" >&2; exit 9; }
    clean_esp_arch_files() { echo "clean_esp $*" >>"$DFM_LOG"; }
    mkfs.btrfs() { echo "mkfs.btrfs $*" >>"$DFM_LOG"; }
    mkfs.ext4()  { echo "mkfs.ext4 $*"  >>"$DFM_LOG"; }
    mkfs.xfs()   { echo "mkfs.xfs $*"   >>"$DFM_LOG"; }
    btrfs()      { echo "btrfs $*"      >>"$DFM_LOG"; }
    mount()      { echo "mount $*"      >>"$DFM_LOG"; }
    mkdir()      { echo "mkdir $*"      >>"$DFM_LOG"; }
    udevadm()    { :; }
    df()         { printf "FS 1M-blocks\n/dev/fake1 2048\n"; }
    source "$1"
    do_filesystems_and_mount
  ' _ "$ROOT/lib/40-disk.sh"
}
_dfm_run ext4 || fail "do_filesystems_and_mount ext4 failed"
grep -q 'mkfs\.ext4 -F -L archroot /dev/mapper/cryptroot' "$_dfm_tmp/calls_ext4" \
  && grep -q 'mount -o noatime /dev/mapper/cryptroot /mnt' "$_dfm_tmp/calls_ext4" \
  && ! grep -q 'btrfs' "$_dfm_tmp/calls_ext4" \
  || fail "do_filesystems_and_mount ext4 calls unexpected: $(cat "$_dfm_tmp/calls_ext4")"
_dfm_run xfs || fail "do_filesystems_and_mount xfs failed"
grep -q 'mkfs\.xfs -f -L archroot /dev/mapper/cryptroot' "$_dfm_tmp/calls_xfs" \
  && grep -q 'mount -o noatime /dev/mapper/cryptroot /mnt' "$_dfm_tmp/calls_xfs" \
  && ! grep -q 'btrfs' "$_dfm_tmp/calls_xfs" \
  || fail "do_filesystems_and_mount xfs calls unexpected: $(cat "$_dfm_tmp/calls_xfs")"
_dfm_run ntfs 2>/dev/null && fail "do_filesystems_and_mount must reject invalid ROOT_FS=ntfs" || true
rm -rf "$_dfm_tmp"; unset -v _dfm_tmp; unset -f _dfm_run

# Behavioral: 07-services-snapshots.sh skips snapper on non-btrfs; 08-gnome.sh guards btrfs-assistant; 30-finish.sh recovery mount matches ROOT_FS.
_sn_skip="$(ROOT_FS=ext4 INSTALL_BLUETOOTH=N INSTALL_SNAPPER_HOME=N bash -c '
  set -euo pipefail
  stage() { :; }; say() { printf "%s\n" "$*"; }; yn_on() { return 1; }
  systemctl() { :; }; snapper() { echo "SNAPPER_CALLED"; exit 9; }
  source "$1"
' _ "$ROOT/lib/chroot/07-services-snapshots.sh")" || fail "07-services-snapshots.sh must not call snapper on ext4"
grep -q 'snapper skipped (ROOT_FS=ext4)' <<<"$_sn_skip" \
  || fail "07-services-snapshots.sh must log snapper skip on ext4 (got: $_sn_skip)"
grep -q 'yn_on "\${INSTALL_BTRFS_ASSISTANT}" && \[\[ \${ROOT_FS:-btrfs} == btrfs \]\]' "$ROOT/lib/chroot/08-gnome.sh" \
  || fail "08-gnome.sh must guard btrfs-assistant on ROOT_FS=btrfs"
_rm_blk="$(awk '/^if yn_on "\$\{ENCRYPT_ROOT:-Y\}"; then/{f=1} f{print} f&&/^unset -v _rec_dev$/{exit}' "$ROOT/lib/steps/30-finish.sh")"
[[ -n $_rm_blk ]] || fail "could not extract RECOVERY_MOUNT block from 30-finish.sh"
_rm_ext4="$(ENCRYPT_ROOT=Y ROOT_FS=ext4 INSTALL_SNAPPER_HOME=N bash -c '
  set -euo pipefail; source "$1"
  eval "$2"
  printf "%s\n" "$RECOVERY_MOUNT"
' _ "$ROOT/lib/00-common.sh" "$_rm_blk")"
[[ $_rm_ext4 == "mount /dev/mapper/cryptroot /mnt" ]] \
  || fail "30-finish.sh recovery mount on encrypted ext4 must omit subvol=@ (got: $_rm_ext4)"
_rm_vm="$(ENCRYPT_ROOT=N ROOT_FS=ext4 INSTALL_SNAPPER_HOME=N bash -c '
  set -euo pipefail; source "$1"
  eval "$2"
  printf "%s\n" "$RECOVERY_MOUNT"
' _ "$ROOT/lib/00-common.sh" "$_rm_blk")"
[[ $_rm_vm == "mount /dev/<root> /mnt" ]] \
  || fail "30-finish.sh recovery mount on unencrypted ext4 must use /dev/<root> (got: $_rm_vm)"
unset -v _sn_skip _rm_blk _rm_ext4 _rm_vm

# 11-extras.sh forces INSTALL_SNAPPER_HOME=N and INSTALL_BTRFS_ASSISTANT=N on non-btrfs.
for _fs in ext4 xfs; do
  _sn_out="$(NONINTERACTIVE=1 ROOT_FS="$_fs" DESKTOP=Y INSTALL_SNAPPER_HOME=Y INSTALL_BTRFS_ASSISTANT=Y \
    INSTALL_TLP=N INSTALL_TUNED=N SKIP_THINKPAD_HW=N bash -c '
      set -euo pipefail; source "$1"; ui_step() { :; }; warn() { :; }; ui_warn() { :; }
      EXTRA_PKGS=(); source "$2"
      printf "%s:%s\n" "$INSTALL_SNAPPER_HOME" "$INSTALL_BTRFS_ASSISTANT"
    ' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/steps/11-extras.sh")"
  [[ $_sn_out == "N:N" ]] || fail "11-extras.sh must force snapper_home+btrfs_assistant off on ROOT_FS=$_fs (got: $_sn_out)"
done
unset -v _fs _sn_out

# 03-initramfs-cmdline.sh emits rootflags=subvol=@ ONLY on btrfs (never ext4/xfs).
_cmd_blk="$(awk '/^# kernel cmdline/{f=1} f{print} /^unset -v _cmdline$/{exit}' "$ROOT/lib/chroot/03-initramfs-cmdline.sh")"
[[ -n $_cmd_blk ]] || fail "could not extract _cmdline block from 03-initramfs-cmdline.sh"
_cmd_tmp="$(mktemp -d)"; mkdir -p "$_cmd_tmp/etc/kernel"
_cmd_blk_rw="${_cmd_blk//\/etc\/kernel/$_cmd_tmp\/etc\/kernel}"
for _fs in btrfs ext4 xfs; do
  ENCRYPT_ROOT=Y ROOT_FS="$_fs" LUKS_UUID=test-uuid HW_PROFILE=t14s INSTALL_PLYMOUTH=N VM_SERIAL_CONSOLE=N bash -c '
    set -euo pipefail
    yn_on() { local v=${1,,}; [[ $v == y || $v == yes || $v == on || $v == 1 ]]; }
    eval "$1"
  ' _ "$_cmd_blk_rw" || fail "03-initramfs-cmdline.sh failed for ROOT_FS=$_fs"
  if [[ $_fs == btrfs ]]; then
    grep -q 'rootflags=subvol=@' "$_cmd_tmp/etc/kernel/cmdline" \
      || fail "ROOT_FS=btrfs cmdline must include rootflags=subvol=@"
  else
    ! grep -q 'rootflags=subvol=@' "$_cmd_tmp/etc/kernel/cmdline" \
      || fail "ROOT_FS=$_fs cmdline must NOT include rootflags=subvol=@"
  fi
done
rm -rf "$_cmd_tmp"; unset -v _cmd_blk _cmd_blk_rw _cmd_tmp _fs

# Behavioral: Quick VM (PRESET=vm) defaults, hypervisor detect, fast pkgs, unencrypted LUKS/initramfs/cmdline/mount.
_vm_prof="$(NONINTERACTIVE=1 PRESET=vm bash -c '
  set -euo pipefail; source "$1"
  ui_step() { :; }; die() { exit 9; }; apply_extra_pkgs_list() { :; }
  detect_vm_thinkpad_skip() { IS_VM=1; SKIP_THINKPAD_HW=Y; }
  source "$2"
  printf "%s:%s:%s:%s:%s:%s:%s:%s:%s\n" "$ROOT_FS" "$ENCRYPT_ROOT" "$ESP_MB" "$ENABLE_SSHD" \
    "$INSTALL_VM_GUEST" "$VM_FAST_PKG" "$VM_SERIAL_CONSOLE" "$TIMEZONE" "$LOCALE"
' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/steps/05-profile.sh")"
[[ $_vm_prof == "ext4:N:1024:Y:Y:Y:Y:UTC:en_US.UTF-8" ]] \
  || fail "PRESET=vm defaults mismatch (got: $_vm_prof)"
unset -v _vm_prof

[[ $(T14S_VIRT=kvm bash -c 'source "$1"; detect_vm_hypervisor' _ "$ROOT/lib/30-hardware.sh") == kvm ]] \
  || fail "detect_vm_hypervisor kvm failed"
[[ $(T14S_VIRT=vmware bash -c 'source "$1"; detect_vm_hypervisor' _ "$ROOT/lib/30-hardware.sh") == vmware ]] \
  || fail "detect_vm_hypervisor vmware failed"
[[ $(T14S_VIRT=oracle bash -c 'source "$1"; detect_vm_hypervisor' _ "$ROOT/lib/30-hardware.sh") == virtualbox ]] \
  || fail "detect_vm_hypervisor oracle->virtualbox failed"
# Regression: arch-chroot causes bare systemd-detect-virt to emit container-other; must use --vm and fall back to DMI.
_dmi_tmp="$(mktemp -d)"
printf 'QEMU\n' >"$_dmi_tmp/sys_vendor"; printf 'Standard PC (Q35)\n' >"$_dmi_tmp/product_name"
[[ $(T14S_VIRT=container-other T14S_DMI_DIR="$_dmi_tmp" bash -c 'source "$1"; detect_vm_hypervisor' _ "$ROOT/lib/30-hardware.sh") == kvm ]] \
  || fail "detect_vm_hypervisor must ignore container-other and fall back to DMI (kvm)"
grep -q 'systemd-detect-virt --vm' "$ROOT/lib/30-hardware.sh" \
  || fail "detect_vm_hypervisor must pass --vm to systemd-detect-virt (chroot safety)"
grep -q 'host_profile == generic && " \$cmdline " != \*" rd\.luks\."\*' "$ROOT/tests/host-check.sh" \
  || fail "host-check.sh must gate LUKS checks on rd.luks. (cryptsetup is pulled by systemd)"
# 04-hardware.sh auto-selects HW_PROFILE=generic on VMs without prompting ui_radio.
_hw_vm="$(NONINTERACTIVE=0 HW_PROFILE="" T14S_DMI_DIR="$_dmi_tmp" bash -c '
  set -euo pipefail; ui_step() { :; }; ok() { :; }; warn() { :; }; die() { exit 9; }
  ui_radio() { echo "RADIO_CALLED" >&2; exit 8; }
  detect_vm_hypervisor() { echo kvm; }; detect_cpu_vendor() { echo amd; }; detect_gpu_vendors() { echo ""; }
  source "$2"; source "$1"; printf "%s\n" "$HW_PROFILE"
' _ "$ROOT/lib/steps/04-hardware.sh" "$ROOT/lib/05-policy.sh")"
[[ $_hw_vm == generic ]] || fail "04-hardware.sh must auto-select generic on VM without ui_radio (got: $_hw_vm)"
rm -rf "$_dmi_tmp"; unset -v _dmi_tmp _hw_vm

_vm_pkgs="$(ROOT_FS=ext4 ENCRYPT_ROOT=N VM_FAST_PKG=Y UCODE="" INSTALL_BLUETOOTH=N bash -c '
  source "$1"; source "$2"; t14s_base_packages; printf "%s\n" "${BASE_PKGS[@]}"
' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/50-packages.sh")"
grep -qx 'e2fsprogs' <<<"$_vm_pkgs" && grep -qx 'linux-lts' <<<"$_vm_pkgs" \
  && ! grep -qxE 'linux-firmware|cryptsetup|btrfs-progs|snapper|snap-pac|amd-ucode|intel-ucode' <<<"$_vm_pkgs" \
  || fail "Quick VM base packages must omit linux-firmware/cryptsetup/btrfs/ucode"
unset -v _vm_pkgs

# 08-luks.sh skips LUKS when ENCRYPT_ROOT=N, and requires LUKS_PASS when ENCRYPT_ROOT=Y in NONINTERACTIVE.
NONINTERACTIVE=1 ENCRYPT_ROOT=N SECRETS_FROM_FILE=1 bash -c '
  set -euo pipefail; source "$1"; ui_step() { :; }; ok() { :; }; die() { exit 9; }
  source "$2"
' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/steps/08-luks.sh" \
  || fail "08-luks.sh must allow empty LUKS_PASS when ENCRYPT_ROOT=N"
NONINTERACTIVE=1 ENCRYPT_ROOT=Y SECRETS_FROM_FILE=1 bash -c '
  set -euo pipefail; source "$1"; ui_step() { :; }; ok() { :; }; die() { exit 9; }
  source "$2"
' _ "$ROOT/lib/00-common.sh" "$ROOT/lib/steps/08-luks.sh" 2>/dev/null \
  && fail "08-luks.sh must require LUKS_PASS when ENCRYPT_ROOT=Y in NONINTERACTIVE" || true

# 03-initramfs-cmdline.sh unencrypted ext4 + serial console: no sd-encrypt/rd.luks, uses root=UUID + console=ttyS0.
_ic_tmp="$(mktemp -d)"; mkdir -p "$_ic_tmp/etc/kernel"
printf 'HOOKS=(base udev autodetect filesystems)\n' >"$_ic_tmp/etc/mkinitcpio.conf"
_ic_blk="$(awk '/^if yn_on "\$\{ENCRYPT_ROOT:-Y\}"; then/{f=1} f{print} /^unset -v _cmdline$/{exit}' "$ROOT/lib/chroot/03-initramfs-cmdline.sh")"
[[ -n $_ic_blk ]] || fail "could not extract initramfs/cmdline block from 03-initramfs-cmdline.sh"
_ic_blk_rw="${_ic_blk//\/etc\//$_ic_tmp\/etc\/}"
ENCRYPT_ROOT=N ROOT_FS=ext4 ROOT_UUID=1111-2222 HW_PROFILE=generic INSTALL_PLYMOUTH=N VM_SERIAL_CONSOLE=Y bash -c '
  set -euo pipefail
  yn_on() { local v=${1,,}; [[ $v == y || $v == yes || $v == on || $v == 1 ]]; }
  detect_cpu_vendor() { echo amd; }; detect_gpu_vendors() { echo ""; }
  eval "$1"
' _ "$_ic_blk_rw" || fail "03-initramfs-cmdline.sh failed for unencrypted Quick VM"
! grep -q 'sd-encrypt' "$_ic_tmp/etc/mkinitcpio.conf" \
  || fail "unencrypted Quick VM HOOKS must omit sd-encrypt"
grep -q 'root=UUID=1111-2222' "$_ic_tmp/etc/kernel/cmdline" \
  && grep -q 'console=tty0 console=ttyS0,115200n8' "$_ic_tmp/etc/kernel/cmdline" \
  && ! grep -qE 'rd\.luks|rootflags=subvol=@' "$_ic_tmp/etc/kernel/cmdline" \
  || fail "unencrypted Quick VM cmdline wrong: $(cat "$_ic_tmp/etc/kernel/cmdline")"
rm -rf "$_ic_tmp"; unset -v _ic_tmp _ic_blk _ic_blk_rw

# do_filesystems_and_mount honors ROOT_DEV=/dev/vda2 for unencrypted installs.
_vd_log="$(mktemp)"
ROOT_FS=ext4 ROOT_DEV=/dev/vda2 FORMAT_EFI=0 EFI_PART=/dev/vda1 CLEAN_ESP_ARCH=N DFM_LOG="$_vd_log" bash -c '
  set -euo pipefail
  step() { :; }; ok() { :; }; warn() { :; }; die() { exit 9; }; clean_esp_arch_files() { :; }
  mkfs.ext4() { echo "mkfs.ext4 $*" >>"$DFM_LOG"; }
  mount() { echo "mount $*" >>"$DFM_LOG"; }
  mkdir() { :; }; udevadm() { :; }; df() { printf "FS 1M\n/dev/vda1 1024\n"; }
  source "$1"; do_filesystems_and_mount
' _ "$ROOT/lib/40-disk.sh" || fail "do_filesystems_and_mount failed with ROOT_DEV=/dev/vda2"
grep -q 'mkfs\.ext4 -F -L archroot /dev/vda2' "$_vd_log" \
  && grep -q 'mount -o noatime /dev/vda2 /mnt' "$_vd_log" \
  || fail "do_filesystems_and_mount did not use ROOT_DEV=/dev/vda2: $(cat "$_vd_log")"
rm -f "$_vd_log"; unset -v _vd_log
echo "ok audit + generic profile checks"

# Behavioral: Back/Previous navigation in Stage A UI widgets and wizard step loop.
bash -euo pipefail -c '
  UI=dialog NONINTERACTIVE=0 T14S_RC_BACK=10 WIZARD_CAN_BACK=1
  APP_TITLE=T TUI_TITLE= TUI_NEWT= TUI_DIALOGRC= H=20 W=70 LH=10 MW=66 MH=8 XH=20
  TUI_HINT_MENU=h TUI_HINT_RADIO=h TUI_HINT_CHECK=h LOG=/dev/null
  ui_geometry() { :; }
  source "$1"
  tui() { printf "%s\n" "$@" | grep -qx back && { echo back; return 0; }; return 1; }
  rc=0; ui_menu "M" a A >/dev/null || rc=$?
  [[ $rc -eq 10 ]] || { echo "ui_menu back rc=$rc" >&2; exit 1; }
  rc=0; ui_radio "R" a A on >/dev/null || rc=$?
  [[ $rc -eq 10 ]] || { echo "ui_radio back rc=$rc" >&2; exit 1; }
  rc=0; ui_checklist "C" a A on >/dev/null || rc=$?
  [[ $rc -eq 10 ]] || { echo "ui_checklist back rc=$rc" >&2; exit 1; }
  tui() { printf "%s\n" "$@" | grep -qx Back && return 1; echo ok; }
  rc=0; ui_input "I" def >/dev/null || rc=$?
  [[ $rc -eq 10 ]] || { echo "ui_input back rc=$rc" >&2; exit 1; }
  rc=0; ui_password "P" >/dev/null || rc=$?
  [[ $rc -eq 10 ]] || { echo "ui_password back rc=$rc" >&2; exit 1; }
  # With WIZARD_CAN_BACK=0, back item must not be offered and cancel stays rc=1.
  WIZARD_CAN_BACK=0
  tui() { printf "%s\n" "$@" | grep -qx back && exit 99; return 1; }
  rc=0; ui_menu "M" a A >/dev/null || rc=$?
  [[ $rc -eq 1 ]] || { echo "ui_menu cancel rc=$rc" >&2; exit 1; }
  # msg_height / msg_overflows account for whiptail --fullbuttons (+8) vs dialog (+6).
  body13=$(printf "L%02d\n" $(seq 1 13))
  UI=whiptail; [[ $(msg_height "$body13") -eq 20 ]] && msg_overflows "$body13" \
    || { echo "whiptail 13-line body must overflow XH=20" >&2; exit 1; }
  UI=dialog; [[ $(msg_height "$body13") -eq 19 ]] && ! msg_overflows "$body13" \
    || { echo "dialog 13-line body must fit XH=20" >&2; exit 1; }
' _ "$ROOT/lib/12-ui-screens.sh" || fail "Stage A UI Back navigation check failed"
# Behavioral: wizard loop empty-history Back safety, 04-hardware re-entry, intra-step Back, Review filtering.
bash -euo pipefail -c '
  ROOT=$1
  # 1) Empty-history WIZARD_BACK=1 in stage-a/install.sh must NOT advance to 20-install-disk.sh.
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  mkdir -p "$tmp/steps"
  for s in 01-preflight.sh 02-welcome.sh 03-answers.sh 04-hardware.sh 05-profile.sh \
           06-disk.sh 07-partition.sh 08-luks.sh 09-identity.sh 10-downloads.sh \
           11-extras.sh; do
    echo "WIZARD_SKIPPED_STEP=1" >"$tmp/steps/$s"
  done
  cat >"$tmp/steps/12-review.sh" <<EOF
_rev_calls=\$((\${_rev_calls:-0} + 1))
if (( _rev_calls == 1 )); then WIZARD_BACK=1; return 0; fi
exit 0
EOF
  echo "echo REACHED_DISK_WIPE >&2; exit 99" >"$tmp/steps/20-install-disk.sh"
  for s in 21-install-filesystems.sh 22-install-base.sh 23-install-chroot.sh 30-finish.sh; do
    : >"$tmp/steps/$s"
  done
  _loop=$(sed -n "/^_t14s_steps=(/,/^unset -v _t14s_step/p" "$ROOT/install.sh")
  NONINTERACTIVE=0
  _lib_path() { _LIB_PATH="$tmp/$1"; }
  ( eval "$_loop" )
  # 2) 04-hardware.sh re-prompts on Back re-entry instead of skipping.
  _HW_PROMPTED=0 HW_PROFILE="" NONINTERACTIVE=0 T14S_DMI_DIR="$tmp/nodmi"
  : >"$tmp/hw_calls"
  ui_step() { :; }; ok() { :; }; warn() { :; }; die() { echo "DIE: $*" >&2; exit 1; }
  dmi_matches_t14s() { return 1; }; dmi_matches_p15_gen1() { return 1; }
  detect_vm_hypervisor() { echo none; }; detect_cpu_vendor() { echo x86; }; detect_gpu_vendors() { echo none; }
  ui_radio() { echo x >>"$tmp/hw_calls"; echo generic; }
  WIZARD_SKIPPED_STEP=0; source "$ROOT/lib/steps/04-hardware.sh"
  [[ $(wc -l <"$tmp/hw_calls") -eq 1 && $WIZARD_SKIPPED_STEP -eq 0 && $_HW_PROMPTED -eq 1 ]] || { echo "04-hw pass1 bad" >&2; exit 1; }
  WIZARD_SKIPPED_STEP=0; source "$ROOT/lib/steps/04-hardware.sh"
  [[ $(wc -l <"$tmp/hw_calls") -eq 2 && $WIZARD_SKIPPED_STEP -eq 0 ]] || { echo "04-hw re-entry skipped prompt" >&2; exit 1; }
  # 3) 10-downloads.sh Back on ROOT_FS steps back to PACMAN_PARALLEL (not WIZARD_BACK=1).
  PACMAN_PARALLEL=10 ROOT_FS=btrfs BTRFS_COMPRESS=zstd3 ZRAM_SIZE=half QUICK_VM=0 T14S_RC_BACK=10 WIZARD_BACK=0
  : >"$tmp/dl_calls"
  ui_radio() {
    echo x >>"$tmp/dl_calls"
    case $(wc -l <"$tmp/dl_calls") in
      1) echo 10 ;;          # PACMAN_PARALLEL
      2) return 10 ;;        # Back on ROOT_FS -> back to PACMAN_PARALLEL
      3) echo 15 ;;          # PACMAN_PARALLEL again
      4) echo ext4 ;;        # ROOT_FS
      5) echo quarter ;;     # ZRAM_SIZE
    esac
  }
  source "$ROOT/lib/steps/10-downloads.sh"
  [[ $WIZARD_BACK -eq 0 && $PACMAN_PARALLEL -eq 15 && $ROOT_FS == ext4 && $ZRAM_SIZE == quarter ]] \
    || { echo "10-downloads intra-step back failed: WB=$WIZARD_BACK PP=$PACMAN_PARALLEL FS=$ROOT_FS ZR=$ZRAM_SIZE" >&2; exit 1; }
  # 4) 12-review.sh hides back when _t14s_hist is empty and hides skipped Quick VM steps in jump.
  _t14s_hist=() QUICK_VM=1 ENCRYPT_ROOT=N _HW_PROMPTED=0 DRYRUN=0
  DISK=/dev/vda EFI_PART=/dev/vda1 ROOT_PART=/dev/vda2 MODE=auto FORMAT_EFI=1 ESP_MB=1024 CLEAN_ESP_ARCH=Y LUKS_WIPE=none
  size_mb() { echo 20480; }; yn_on() { [[ ${1:-N} == Y ]]; }; ui_info() { :; }; ui_yesno() { return 1; }
  _seen_menus="$tmp/menus"
  ui_menu() {
    printf "%s\n" "$*" >>"$_seen_menus"
    if [[ $1 == *"go back"* ]]; then echo jump; else echo 12-review.sh; fi
  }
  DESKTOP=N PRESET=vm PACMAN_PARALLEL=10 ZRAM_SIZE=half SKIP_REFLECTOR=Y SKIP_THINKPAD_HW=Y
  EXTRA_PKGS=() INSTALL_FLATPAK_APPS=N INSTALL_BLUETOOTH=N INSTALL_NERD_FONTS=N
  INSTALL_SNAPPER_HOME=N INSTALL_BTRFS_ASSISTANT=N INSTALL_MULTILIB=N INSTALL_YAY=N
  INSTALL_TUNED=N INSTALL_DEVTOOLS=N INSTALL_OLLAMA=N INSTALL_STARSHIP=N
  INSTALL_LINUX_HARDENED=N INSTALL_LINUX_STABLE=N INSTALL_LINUX_ZEN=N INSTALL_PLYMOUTH=N
  INSTALL_CLI=N INSTALL_PODMAN=N INSTALL_DOCKER=N INSTALL_VIRT=N INSTALL_AVAHI=N
  INSTALL_WIREGUARD=N INSTALL_TAILSCALE=N FW_SYNCTHING=N FW_KDECONNECT=N
  INSTALL_CUPS=N INSTALL_TLP=N ENROLL_SB=N ENABLE_SSHD=N INSTALL_FAIL2BAN=N
  INSTALL_SELFTEST=N INSTALL_CHROME_HINT=N INSTALL_THINKFAN=N
  HOSTNAME=vm USERNAME=arch TIMEZONE=UTC LOCALE=en_US.UTF-8 KEYMAP=us
  ( source "$ROOT/lib/steps/12-review.sh" )
  ! grep -q "Back to previous step" "$_seen_menus" || { echo "12-review offered back with empty hist" >&2; exit 1; }
  ! grep -q "08-luks.sh" "$_seen_menus" && ! grep -q "11-extras.sh" "$_seen_menus" \
    || { echo "12-review jump listed skipped Quick VM steps" >&2; exit 1; }
' _ "$ROOT" || fail "Stage A wizard loop / step Back behavioral checks failed"
grep -q 'WIZARD_JUMP=' "$ORCH_SH" && grep -q 'WIZARD_BACK=' "$ORCH_SH" \
  && grep -q 'Jump to which step?' "$ROOT/lib/steps/12-review.sh" \
  || fail "Stage A wizard must support Back and Review step jump"
echo "ok Stage A back/previous navigation"

echo "PASS: smoke.test.sh"
