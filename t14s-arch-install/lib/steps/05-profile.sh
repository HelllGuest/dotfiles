# 05-profile.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# Wizard step 3/11: install profile preset (feeds checklist defaults).
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── profile preset (feeds checklist defaults) ───────────────
detect_vm_thinkpad_skip
if [[ -z ${PRESET:-} ]]; then
  if (( IS_VM && ! NONINTERACTIVE )); then PRESET=vm; else PRESET=gnome; fi
fi
ui_step 3 Profile
if (( NONINTERACTIVE )); then
  [[ $PRESET == gnome || $PRESET == dev || $PRESET == minimal || $PRESET == vm ]] \
    || die "NONINTERACTIVE needs PRESET=gnome|dev|minimal|vm (got: $PRESET)"
else
  _pg=off; _pd=off; _pm=off; _pv=off
  case $PRESET in
    dev) _pd=on ;;
    minimal) _pm=on ;;
    vm) _pv=on ;;
    *) _pg=on; PRESET=gnome ;;
  esac
  PRESET="$(ui_radio "Install profile (sets defaults; Quick VM uses a fast 4-screen flow)" \
    gnome "GNOME laptop — desktop, Nerd Fonts, mDNS, yay, tuned, multilib" "$_pg" \
    dev "Dev laptop — GNOME + dev toolchains, CLI, Podman, Starship, home snapper" "$_pd" \
    minimal "Minimal — no desktop, LUKS2, small tool set" "$_pm" \
    vm "Quick VM — fast unencrypted ext4, guest agent, SSH, serial console" "$_pv")" || die "aborted"
  unset -v _pg _pd _pm _pv
fi
QUICK_VM=0
_bt_def=Y
if (( IS_VM )); then _bt_def=N; fi
case $PRESET in
  vm)
    if (( ! NONINTERACTIVE )); then
      QUICK_VM=1
      _vd_min=on; _vd_gn=off
      if yn_on "${DESKTOP:-N}"; then _vd_min=off; _vd_gn=on; fi
      _vm_de="$(ui_radio "Quick VM environment" \
        minimal "Headless minimal + SSH + serial console (fastest)" "$_vd_min" \
        gnome "Minimal GNOME Wayland + SPICE/guest agent" "$_vd_gn")" || die "aborted"
      if [[ $_vm_de == gnome ]]; then DESKTOP=Y; else DESKTOP=N; fi
      unset -v _vd_min _vd_gn _vm_de
    fi
    DESKTOP=${DESKTOP:-N}
    if yn_on "$DESKTOP"; then INSTALL_NERD_FONTS=${INSTALL_NERD_FONTS:-Y}
    else INSTALL_NERD_FONTS=${INSTALL_NERD_FONTS:-N}; fi
    ENCRYPT_ROOT=${ENCRYPT_ROOT:-N}
    ROOT_FS=${ROOT_FS:-ext4}
    MODE=${MODE:-auto}
    ESP_MB=${ESP_MB:-1024}
    LUKS_WIPE=none
    ENABLE_SSHD=${ENABLE_SSHD:-Y}
    INSTALL_VM_GUEST=${INSTALL_VM_GUEST:-Y}
    VM_FAST_PKG=${VM_FAST_PKG:-Y}
    VM_SERIAL_CONSOLE=${VM_SERIAL_CONSOLE:-Y}
    INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-N}
    INSTALL_FLATPAK_APPS=${INSTALL_FLATPAK_APPS:-N}
    INSTALL_CLI=${INSTALL_CLI:-N}; INSTALL_PODMAN=${INSTALL_PODMAN:-N}
    INSTALL_STARSHIP=${INSTALL_STARSHIP:-N}; INSTALL_AVAHI=${INSTALL_AVAHI:-N}
    INSTALL_TLP=${INSTALL_TLP:-N}; INSTALL_SELFTEST=${INSTALL_SELFTEST:-N}
    INSTALL_MULTILIB=${INSTALL_MULTILIB:-N}; INSTALL_YAY=${INSTALL_YAY:-N}
    INSTALL_TUNED=${INSTALL_TUNED:-N}; INSTALL_DEVTOOLS=${INSTALL_DEVTOOLS:-N}
    INSTALL_BTRFS_ASSISTANT=${INSTALL_BTRFS_ASSISTANT:-N}
    INSTALL_SNAPPER_HOME=${INSTALL_SNAPPER_HOME:-N}
    TIMEZONE=${TIMEZONE:-UTC}
    LOCALE=${LOCALE:-en_US.UTF-8}
    KEYMAP=${KEYMAP:-us}
    ;;
  minimal)
    _min_tlp=N
    if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then _min_tlp=Y; fi
    DESKTOP=${DESKTOP:-N}; INSTALL_NERD_FONTS=${INSTALL_NERD_FONTS:-N}
    INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-N}; INSTALL_FLATPAK_APPS=${INSTALL_FLATPAK_APPS:-N}
    INSTALL_CLI=${INSTALL_CLI:-N}; INSTALL_PODMAN=${INSTALL_PODMAN:-N}
    INSTALL_STARSHIP=${INSTALL_STARSHIP:-N}; INSTALL_AVAHI=${INSTALL_AVAHI:-N}
    INSTALL_TLP=${INSTALL_TLP:-$_min_tlp}; INSTALL_SELFTEST=${INSTALL_SELFTEST:-N}
    INSTALL_MULTILIB=${INSTALL_MULTILIB:-N}; INSTALL_YAY=${INSTALL_YAY:-N}
    INSTALL_TUNED=${INSTALL_TUNED:-N}; INSTALL_DEVTOOLS=${INSTALL_DEVTOOLS:-N}
    INSTALL_BTRFS_ASSISTANT=${INSTALL_BTRFS_ASSISTANT:-N}
    unset -v _min_tlp
    ;;
  dev)
    DESKTOP=${DESKTOP:-Y}; INSTALL_NERD_FONTS=${INSTALL_NERD_FONTS:-Y}
    INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-$_bt_def}; INSTALL_FLATPAK_APPS=${INSTALL_FLATPAK_APPS:-N}
    INSTALL_CLI=${INSTALL_CLI:-Y}; INSTALL_PODMAN=${INSTALL_PODMAN:-Y}
    INSTALL_STARSHIP=${INSTALL_STARSHIP:-Y}; INSTALL_AVAHI=${INSTALL_AVAHI:-Y}
    INSTALL_CHROME_HINT=${INSTALL_CHROME_HINT:-Y}
    INSTALL_TLP=${INSTALL_TLP:-N}; INSTALL_SELFTEST=${INSTALL_SELFTEST:-Y}
    INSTALL_MULTILIB=${INSTALL_MULTILIB:-Y}; INSTALL_YAY=${INSTALL_YAY:-Y}
    INSTALL_TUNED=${INSTALL_TUNED:-Y}; INSTALL_DEVTOOLS=${INSTALL_DEVTOOLS:-Y}
    INSTALL_BTRFS_ASSISTANT=${INSTALL_BTRFS_ASSISTANT:-Y}
    INSTALL_SNAPPER_HOME=${INSTALL_SNAPPER_HOME:-Y}
    ;;
  *)
    PRESET=gnome
    DESKTOP=${DESKTOP:-Y}; INSTALL_NERD_FONTS=${INSTALL_NERD_FONTS:-Y}
    INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-$_bt_def}; INSTALL_FLATPAK_APPS=${INSTALL_FLATPAK_APPS:-N}
    INSTALL_CLI=${INSTALL_CLI:-N}; INSTALL_PODMAN=${INSTALL_PODMAN:-N}
    INSTALL_STARSHIP=${INSTALL_STARSHIP:-N}; INSTALL_AVAHI=${INSTALL_AVAHI:-Y}
    INSTALL_TLP=${INSTALL_TLP:-N}; INSTALL_SELFTEST=${INSTALL_SELFTEST:-Y}
    INSTALL_MULTILIB=${INSTALL_MULTILIB:-Y}; INSTALL_YAY=${INSTALL_YAY:-Y}
    INSTALL_TUNED=${INSTALL_TUNED:-Y}; INSTALL_DEVTOOLS=${INSTALL_DEVTOOLS:-N}
    INSTALL_BTRFS_ASSISTANT=${INSTALL_BTRFS_ASSISTANT:-Y}
    ;;
esac
unset -v _bt_def
# Fill remaining flags with N if unset
: "${ENROLL_SB:=N}" "${ENABLE_SSHD:=N}" "${INSTALL_CUPS:=N}" "${SKIP_REFLECTOR:=N}"
: "${INSTALL_BLUETOOTH:=N}" "${INSTALL_FLATPAK_APPS:=N}"
: "${INSTALL_DOCKER:=N}" "${INSTALL_VIRT:=N}" "${INSTALL_WIREGUARD:=N}"
: "${INSTALL_TAILSCALE:=N}" "${INSTALL_CHROME_HINT:=N}" "${INSTALL_FAIL2BAN:=N}"
: "${INSTALL_THINKFAN:=N}" "${FW_SYNCTHING:=N}" "${FW_KDECONNECT:=N}"
: "${INSTALL_OLLAMA:=N}"
: "${INSTALL_SNAPPER_HOME:=N}" "${INSTALL_LINUX_HARDENED:=N}" "${INSTALL_LINUX_STABLE:=N}" "${INSTALL_LINUX_ZEN:=N}" "${INSTALL_PLYMOUTH:=N}"
: "${INSTALL_SELFTEST:=N}" "${CLEAN_ESP_ARCH:=Y}"
: "${INSTALL_MULTILIB:=N}" "${INSTALL_YAY:=N}" "${INSTALL_TUNED:=N}"
: "${INSTALL_DEVTOOLS:=N}" "${INSTALL_BTRFS_ASSISTANT:=N}"
: "${PACMAN_PARALLEL:=10}" "${LUKS_WIPE:=none}"
: "${ENCRYPT_ROOT:=Y}" "${INSTALL_VM_GUEST:=N}" "${VM_FAST_PKG:=N}" "${VM_SERIAL_CONSOLE:=N}" "${SSH_PUBKEY:=}"
: "${ROOT_FS:=btrfs}" "${BTRFS_COMPRESS:=zstd3}" "${ZRAM_SIZE:=half}" "${REFLECTOR_COUNTRY:=}"
: "${FORMAT_EFI:=1}"

# clean_esp_arch_files: lib/30-hardware.sh (kernels/ucode always; Arch UKIs when CLEAN_ESP_ARCH=Y).
apply_extra_pkgs_list
