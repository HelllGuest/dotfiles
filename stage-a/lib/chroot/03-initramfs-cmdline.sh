# 03-initramfs-cmdline.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Chroot stage 6-8 %: mkinitcpio hooks, kernel cmdline, ThinkPad charge thresholds.
# Sourced by 80-chroot-setup.sh inside arch-chroot, at top level and in
# order: shares its helpers, globals, set -e and umask as if inline.

stage 6 8 "initramfs and kernel cmdline"
# initramfs (systemd + optional sd-encrypt for LUKS + optional plymouth)
if yn_on "${ENCRYPT_ROOT:-Y}"; then
  _HOOKS='HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)'
  if yn_on "${INSTALL_PLYMOUTH}"; then
    # plymouth before sd-encrypt so the LUKS prompt shows on the splash (ArchWiki).
    _HOOKS='HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block plymouth sd-encrypt filesystems fsck)'
  fi
else
  _HOOKS='HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)'
  if yn_on "${INSTALL_PLYMOUTH}"; then
    _HOOKS='HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block plymouth filesystems fsck)'
  fi
fi
sed -i "s/^HOOKS=.*/${_HOOKS}/" /etc/mkinitcpio.conf
unset -v _HOOKS
if yn_on "${ENCRYPT_ROOT:-Y}"; then
  grep -Eq '^HOOKS=.*sd-encrypt' /etc/mkinitcpio.conf \
    || { echo "ERROR: mkinitcpio HOOKS missing sd-encrypt after sed" >&2; exit 1; }
else
  grep -Eq '^HOOKS=.*filesystems' /etc/mkinitcpio.conf \
    || { echo "ERROR: mkinitcpio HOOKS missing filesystems after sed" >&2; exit 1; }
fi

# kernel cmdline (shared by UKIs)
mkdir -p /etc/kernel
# BIOS Sleep = "Windows and Linux" pairs with mem_sleep_default=s2idle.
# rd.luks.options=discard: pass TRIM through dm-crypt (fstrim.timer is enabled;
# without it the SSD never sees discards). Trade-off: free-block layout is visible
# to someone holding the disk; contents stay encrypted.
# lsm= replaces the deprecated security=apparmor (ArchWiki AppArmor order).
if yn_on "${ENCRYPT_ROOT:-Y}"; then
  _cmdline="rd.luks.name=${LUKS_UUID}=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot"
else
  [[ -n ${ROOT_UUID:-} ]] || { echo "ERROR: ROOT_UUID empty for unencrypted root" >&2; exit 1; }
  _cmdline="root=UUID=${ROOT_UUID}"
fi
if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
  _cmdline+=" rootflags=subvol=@"
fi
_cmdline+=" rw quiet loglevel=3 lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
case ${HW_PROFILE:-t14s} in
  p15)
    _cmdline+=" mem_sleep_default=s2idle intel_iommu=on nvidia_drm.modeset=1 rd.driver.blacklist=nouveau"
    ;;
  t14s)
    _cmdline+=" mem_sleep_default=s2idle amd_iommu=on amd_pstate=active"
    ;;
  *)
    case $(detect_cpu_vendor) in
      amd)   _cmdline+=" amd_iommu=on amd_pstate=active" ;;
      intel) _cmdline+=" intel_iommu=on" ;;
    esac
    if [[ " $(detect_gpu_vendors) " == *" nvidia "* ]]; then
      _cmdline+=" nvidia_drm.modeset=1 rd.driver.blacklist=nouveau"
    fi
    ;;
esac
if yn_on "${INSTALL_PLYMOUTH}"; then
  _cmdline+=" splash"
fi
if yn_on "${VM_SERIAL_CONSOLE:-N}"; then
  _cmdline+=" console=tty0 console=ttyS0,115200n8"
fi
printf '%s\n' "$_cmdline" > /etc/kernel/cmdline
unset -v _cmdline

# Canonical hardware policy (CHARGE_START / CHARGE_END) + monorepo system/ source.
[[ -f /root/t14s-lib/05-policy.sh ]] && source /root/t14s-lib/05-policy.sh
CHARGE_START="${CHARGE_START:-70}"
CHARGE_END="${CHARGE_END:-80}"
if ! [[ $CHARGE_START =~ ^[0-9]+$ && $CHARGE_END =~ ^[0-9]+$ ]] \
  || (( CHARGE_START < 0 || CHARGE_START > 99 || CHARGE_END < 1 || CHARGE_END > 100 || CHARGE_START >= CHARGE_END )); then
  echo "ERROR: invalid CHARGE_START/CHARGE_END (${CHARGE_START}/${CHARGE_END}; need 0 <= START < END <= 100)" >&2
  exit 1
fi
_SYS_SRC=/root/t14s-lib/system

# Install canonical system/ file when deployed from monorepo, else embedded curl fallback.
_sys_install() {
  local rel=$1 dst=$2 mode=${3:-0644}
  mkdir -p "$(dirname "$dst")"
  if [[ -f $_SYS_SRC/$rel ]]; then
    install -m "$mode" "$_SYS_SRC/$rel" "$dst"
  else
    cat >"$dst"
    chmod "$mode" "$dst"
  fi
}

# Render system/templates/*.tmpl (or stdin fallback) replacing @@START@@/@@END@@/@@APPLY@@.
_sys_render_tmpl() {
  local rel=$1 dst=$2 mode=${3:-0644}
  local apply=/usr/local/lib/thinkpad/apply-charge-thresholds.sh line
  mkdir -p "$(dirname "$dst")"
  : >"$dst"
  if [[ -f $_SYS_SRC/$rel ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line//@@START@@/$CHARGE_START}
      line=${line//@@END@@/$CHARGE_END}
      line=${line//@@APPLY@@/$apply}
      printf '%s\n' "$line" >>"$dst"
    done <"$_SYS_SRC/$rel"
  else
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line//@@START@@/$CHARGE_START}
      line=${line//@@END@@/$CHARGE_END}
      line=${line//@@APPLY@@/$apply}
      printf '%s\n' "$line" >>"$dst"
    done
  fi
  chmod "$mode" "$dst"
}

# systemd sleep: enforce s2idle on ThinkPad profiles (generic leaves platform default).
if [[ ${HW_PROFILE:-t14s} != generic ]]; then
  _sys_install etc/systemd/sleep.conf.d/s2idle.conf /etc/systemd/sleep.conf.d/s2idle.conf 0644 <<'EOF'
[Sleep]
SuspendState=mem
MemorySleepMode=s2idle
HibernateMode=shutdown
EOF
fi

# Charge window, touchpad s2idle wakeup disable, lid policy — skipped on VM / SKIP_THINKPAD_HW.
mkdir -p /etc/tmpfiles.d /usr/local/lib/thinkpad /etc/udev/rules.d /etc/systemd/logind.conf.d
if ! yn_on "${SKIP_THINKPAD_HW}"; then
_sys_install templates/thinkpad-charge-thresholds.conf /etc/tmpfiles.d/thinkpad-charge-thresholds.conf 0644 <<'EOF'
# ThinkPad charge thresholds 70–80 (PPD host; no TLP).
# Canonical BAT0 template for bare-metal installer scripts/arch-install-t14s.sh
# (generic arch-install.sh does not seed charge). Live hosts: prefer
# system/scripts/thinkpad-charge-thresholds.sh (discovers all BAT*, refreshes this path,
# and installs thinkpad-charge-thresholds.service +
# /usr/local/lib/thinkpad/apply-charge-thresholds.sh for late BAT* sysfs).
# Keep installer heredocs in sync with this file (tests/thinkpad-t14s.test.sh).
w /sys/class/power_supply/BAT0/charge_control_start_threshold - - - - 70
w /sys/class/power_supply/BAT0/charge_control_end_threshold - - - - 80
EOF
if [[ $CHARGE_START != 70 || $CHARGE_END != 80 ]]; then
  sed -i -e "s/charge_control_start_threshold - - - - 70/charge_control_start_threshold - - - - ${CHARGE_START}/" \
         -e "s/charge_control_end_threshold - - - - 80/charge_control_end_threshold - - - - ${CHARGE_END}/" \
    /etc/tmpfiles.d/thinkpad-charge-thresholds.conf
fi
_sys_install etc/udev/rules.d/61-thinkpad-charge-limit.rules /etc/udev/rules.d/61-thinkpad-charge-limit.rules 0644 <<'EOF'
# UPower 1.90+ / GNOME Preserve Battery Health:
# 60-upower-battery.rules only imports CHARGE_LIMIT from hwdb if
# charge_control_start_threshold already exists when BAT0 is added (races
# thinkpad_acpi) and defaults to 75,80. Explicitly export CHARGE_LIMIT=70,80
# on BAT* so upowerd writes 70–80 instead of clobbering start_threshold to 0.
ACTION!="remove", SUBSYSTEM=="power_supply", KERNEL=="BAT*", ENV{CHARGE_LIMIT}="70,80"
EOF
if [[ $CHARGE_START != 70 || $CHARGE_END != 80 ]]; then
  sed -i "s/ENV{CHARGE_LIMIT}=\"70,80\"/ENV{CHARGE_LIMIT}=\"${CHARGE_START},${CHARGE_END}\"/" \
    /etc/udev/rules.d/61-thinkpad-charge-limit.rules
fi
_sys_install etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules /etc/udev/rules.d/71-thinkpad-t14s-touchpad-wakeup.rules 0644 <<'EOF'
# ThinkPad T14s Gen 3 AMD (21CQ/21CR): disable I2C touchpad wakeup from s2idle.
# Prevents spurious wakeups when the lid flexes in transit (ArchWiki T14s Gen 3 AMD).
# Matches both Elan (i2c-ELAN0678:00) and Synaptics (i2c-SYNA8018:00) SKUs.
ACTION=="add|change", SUBSYSTEM=="i2c", KERNEL=="i2c-ELAN0678:*|i2c-SYNA8018:*", ATTR{power/wakeup}="disabled"
EOF
_sys_install etc/systemd/logind.conf.d/thinkpad-lid.conf /etc/systemd/logind.conf.d/thinkpad-lid.conf 0644 <<'EOF'
[Login]
# Battery / unknown: suspend on lid. On charger: stay awake (GNOME mirrors this).
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
_sys_render_tmpl templates/apply-charge-thresholds.sh.tmpl /usr/local/lib/thinkpad/apply-charge-thresholds.sh 0755 <<'EOF'
#!/usr/bin/env bash
# Wait for thinkpad_acpi BAT* charge_control_*, then apply @@START@@-@@END@@.
# Exit 0 if absent (VM / no battery sysfs).
# Canonical template: system/templates/apply-charge-thresholds.sh.tmpl
# Rendered by thinkpad-charge-thresholds.sh; keep machine Stage A installers in sync (tests).
set -euo pipefail
START=@@START@@
END=@@END@@
for _ in $(seq 1 60); do
  shopt -s nullglob
  found=(/sys/class/power_supply/BAT*/charge_control_end_threshold)
  shopt -u nullglob
  ((${#found[@]} > 0)) && break
  sleep 1
done
shopt -s nullglob
for bat in /sys/class/power_supply/BAT*; do
  [[ -d $bat ]] || continue
  if [[ -e $bat/charge_control_start_threshold ]]; then
    printf '%s\n' "$START" >"$bat/charge_control_start_threshold" || true
  fi
  if [[ -e $bat/charge_control_end_threshold ]]; then
    printf '%s\n' "$END" >"$bat/charge_control_end_threshold" || true
  fi
done
shopt -u nullglob
exit 0
EOF
_sys_render_tmpl templates/thinkpad-charge-thresholds.service.tmpl /etc/systemd/system/thinkpad-charge-thresholds.service 0644 <<'EOF'
[Unit]
Description=ThinkPad battery charge thresholds (@@START@@-@@END@@)
Documentation=file://@@APPLY@@
After=multi-user.target
# Do not use ConditionPathExists*: BAT* may appear after early boot.

[Service]
Type=oneshot
ExecStart=@@APPLY@@
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable thinkpad-charge-thresholds.service
else
  say "SKIP_THINKPAD_HW — charge thresholds not installed"
fi
unset -v _SYS_SRC
unset -f _sys_install _sys_render_tmpl
