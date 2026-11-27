# 11-extras.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Wizard step 9/11: extras checklists, reflector country, post-install hook.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# Split checklists (Core / Tools / Network). Defaults from preset + answers.
flag_from_opts() {
  local opts=$1 tag=$2
  printf '%s\n' "$opts" | grep -qx "$tag"
}
_extra_onoff() {
  local want=$1 p
  for p in "${EXTRA_PKGS[@]}"; do
    [[ $p == "$want" ]] && { printf on; return 0; }
  done
  printf off
}

ui_step 9 Extras
_extra_in=${T14S_EXTRA_PKGS:-}
if (( NONINTERACTIVE )); then
  # Keep EXTRA_PKGS already filled from EXTRA_PKGS_LIST (answers replay).
  :
elif (( ${QUICK_VM:-0} )); then
  # Quick VM skips interactive checklists and keeps preset defaults.
  WIZARD_SKIPPED_STEP=1
else
  _ex_step=0
  while (( _ex_step < 6 )); do
    case $_ex_step in
      0)
        _rc=0
        OPTS_CORE="$(ui_checklist "Core extras — Space toggles, Enter = Next" \
          gnome "Minimal GNOME desktop + Flatpak/Flathub" "$(def_onoff "$DESKTOP")" \
          flatpak_apps "First-boot Flatpak apps (Brave, Zen, LibreWolf, ProtonVPN; needs GNOME)" "$(def_onoff "$INSTALL_FLATPAK_APPS")" \
          bluetooth "Bluetooth stack (bluez + bluez-utils)" "$(def_onoff "$INSTALL_BLUETOOTH")" \
          vm_guest "VM guest agent (qemu-guest-agent / open-vm-tools / vbox)" "$(def_onoff "${INSTALL_VM_GUEST:-N}")" \
          vm_serial "Serial console (console=ttyS0 + serial-getty@ttyS0)" "$(def_onoff "${VM_SERIAL_CONSOLE:-N}")" \
          nerd_fonts "JetBrainsMono Nerd + Inter/Noto fonts" "$(def_onoff "$INSTALL_NERD_FONTS")" \
          sbctl "Enroll Secure Boot keys now (Setup Mode)" "$(def_onoff "$ENROLL_SB")" \
          sshd "Enable SSH server (sshd) after install" "$(def_onoff "$ENABLE_SSHD")" \
          cups "CUPS printing (cups + cups-pdf + ghostscript)" "$(def_onoff "$INSTALL_CUPS")" \
          skip_reflector "Skip live reflector; keep ISO mirrorlist" "$(def_onoff "$SKIP_REFLECTOR")" \
          tlp "TLP power mgmt (console-only; skipped if GNOME)" "$(def_onoff "$INSTALL_TLP")" \
          thinkfan "Write thinkfan AUR note (not in official repos)" "$(def_onoff "$INSTALL_THINKFAN")" \
          snapper_home "Snapper config for @home (Btrfs only)" "$([[ ${ROOT_FS:-btrfs} == btrfs ]] && def_onoff "$INSTALL_SNAPPER_HOME" || echo off)" \
          btrfs_assistant "btrfs-assistant (snapshot GUI; Btrfs + GNOME)" "$([[ ${ROOT_FS:-btrfs} == btrfs ]] && def_onoff "$INSTALL_BTRFS_ASSISTANT" || echo off)" \
          tuned "tuned + tuned-ppd + tuned-gui (replaces power-profiles-daemon)" "$(def_onoff "$INSTALL_TUNED")" \
          multilib "Enable [multilib] (32-bit: Steam, Wine)" "$(def_onoff "$INSTALL_MULTILIB")" \
          yay "yay AUR helper (yay-bin, built as your user)" "$(def_onoff "$INSTALL_YAY")" \
          linux_hardened "Also install linux-hardened (security kernel) UKI" "$(def_onoff "$INSTALL_LINUX_HARDENED")" \
          linux_stable "Also install linux (stable) UKI" "$(def_onoff "$INSTALL_LINUX_STABLE")" \
          linux_zen "Also install linux-zen (low-latency desktop) UKI" "$(def_onoff "$INSTALL_LINUX_ZEN")" \
          plymouth "Plymouth splash (optional)" "$(def_onoff "$INSTALL_PLYMOUTH")" \
          selftest "Write post-boot BT/audio self-test script" "$(def_onoff "$INSTALL_SELFTEST")" \
          clean_esp "Clean old Arch files from ESP (UKIs/entries/EFI/arch)" "$(def_onoff "$CLEAN_ESP_ARCH")" \
          chrome_hint "Write post-boot Chrome Flatpak helper script" "$(def_onoff "$INSTALL_CHROME_HINT")")" \
          || _rc=$?
        if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc _ex_step; WIZARD_BACK=1; return 0; fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc
        _ex_step=1
        ;;
      1)
        _rc=0
        OPTS_TOOLS="$(WIZARD_CAN_BACK=1 ui_checklist "Dev / CLI tools" \
          devtools "Dev toolchains: gcc/clang/gdb, python, node, go, rustup, gh/glab, nvim, code" "$(def_onoff "$INSTALL_DEVTOOLS")" \
          cli "ripgrep fd fzf bat eza jq git-delta btop fastfetch" "$(def_onoff "$INSTALL_CLI")" \
          starship "starship prompt (+ wire into user zsh)" "$(def_onoff "$INSTALL_STARSHIP")" \
          podman "podman + buildah (rootless)" "$(def_onoff "$INSTALL_PODMAN")" \
          docker "docker + docker-compose (heavier)" "$(def_onoff "$INSTALL_DOCKER")" \
          virt "libvirt + qemu-desktop + virt-manager" "$(def_onoff "$INSTALL_VIRT")" \
          ollama "ollama / ollama-cuda (localhost:11434; P15/generic)" "$([[ ${HW_PROFILE:-} == p15 || ${HW_PROFILE:-} == generic ]] && def_onoff "${INSTALL_OLLAMA:-N}" || echo off)" \
          htop "htop" "$(_extra_onoff htop)" \
          tmux "tmux" "$(_extra_onoff tmux)" \
          rsync "rsync" "$(_extra_onoff rsync)" \
          bash_completion "bash-completion" "$(_extra_onoff bash-completion)" \
          wget "wget" "$(_extra_onoff wget)" \
          usbutils "usbutils" "$(_extra_onoff usbutils)" \
          lsof "lsof" "$(_extra_onoff lsof)" \
          dmidecode "dmidecode" "$(_extra_onoff dmidecode)" \
          powertop "powertop" "$(_extra_onoff powertop)" \
          mc "mc (midnight commander)" "$(_extra_onoff mc)" \
          traceroute "traceroute" "$(_extra_onoff traceroute)" \
          bind "bind (dig/nslookup)" "$(_extra_onoff bind)" \
          smartmontools "smartmontools (smartctl)" "$(_extra_onoff smartmontools)")" || _rc=$?
        if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _ex_step=0; continue; fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc
        _ex_step=2
        ;;
      2)
        _rc=0
        OPTS_NET="$(WIZARD_CAN_BACK=1 ui_checklist "Network / security extras" \
          avahi "avahi + nss-mdns (.local discovery)" "$(def_onoff "$INSTALL_AVAHI")" \
          wireguard "wireguard-tools" "$(def_onoff "$INSTALL_WIREGUARD")" \
          tailscale "tailscale" "$(def_onoff "$INSTALL_TAILSCALE")" \
          fail2ban "fail2ban (useful with sshd)" "$(def_onoff "$INSTALL_FAIL2BAN")" \
          fw_syncthing "firewalld allow Syncthing 22000/tcp+udp" "$(def_onoff "$FW_SYNCTHING")" \
          fw_kdeconnect "firewalld allow KDE Connect 1714:1764/tcp+udp" "$(def_onoff "$FW_KDECONNECT")" )" \
          || _rc=$?
        if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _ex_step=1; continue; fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc

        DESKTOP=N; INSTALL_FLATPAK_APPS=N; INSTALL_BLUETOOTH=N; INSTALL_VM_GUEST=N; VM_SERIAL_CONSOLE=N; INSTALL_NERD_FONTS=N; ENROLL_SB=N; ENABLE_SSHD=N
        INSTALL_CUPS=N; SKIP_REFLECTOR=N; INSTALL_TLP=N; INSTALL_THINKFAN=N
        INSTALL_SNAPPER_HOME=N; INSTALL_LINUX_HARDENED=N; INSTALL_LINUX_STABLE=N; INSTALL_LINUX_ZEN=N; INSTALL_PLYMOUTH=N
        INSTALL_SELFTEST=N; CLEAN_ESP_ARCH=N; INSTALL_CHROME_HINT=N
        INSTALL_MULTILIB=N; INSTALL_YAY=N; INSTALL_TUNED=N; INSTALL_DEVTOOLS=N
        INSTALL_BTRFS_ASSISTANT=N
        INSTALL_CLI=N; INSTALL_STARSHIP=N
        INSTALL_PODMAN=N; INSTALL_DOCKER=N; INSTALL_VIRT=N
        INSTALL_AVAHI=N; INSTALL_WIREGUARD=N; INSTALL_TAILSCALE=N
        INSTALL_FAIL2BAN=N; FW_SYNCTHING=N; FW_KDECONNECT=N; INSTALL_OLLAMA=N
        # Preserve free-form packages loaded from EXTRA_PKGS_LIST; the 13 checklist
        # items above were pre-ticked and are now controlled by OPTS_TOOLS.
        _extras_keep=()
        for _p in "${EXTRA_PKGS[@]}"; do
          case $_p in
            htop|tmux|rsync|bash-completion|wget|usbutils|lsof|dmidecode|powertop|mc|traceroute|bind|smartmontools) ;;
            *) _extras_keep+=("$_p") ;;
          esac
        done
        unset -v _p
        EXTRA_PKGS=()

        flag_from_opts "$OPTS_CORE" gnome && DESKTOP=Y || true
        flag_from_opts "$OPTS_CORE" flatpak_apps && INSTALL_FLATPAK_APPS=Y || true
        flag_from_opts "$OPTS_CORE" bluetooth && INSTALL_BLUETOOTH=Y || true
        flag_from_opts "$OPTS_CORE" vm_guest && INSTALL_VM_GUEST=Y || true
        flag_from_opts "$OPTS_CORE" vm_serial && VM_SERIAL_CONSOLE=Y || true
        flag_from_opts "$OPTS_CORE" nerd_fonts && INSTALL_NERD_FONTS=Y || true
        flag_from_opts "$OPTS_CORE" sbctl && ENROLL_SB=Y || true
        flag_from_opts "$OPTS_CORE" sshd && ENABLE_SSHD=Y || true
        flag_from_opts "$OPTS_CORE" cups && INSTALL_CUPS=Y || true
        flag_from_opts "$OPTS_CORE" skip_reflector && SKIP_REFLECTOR=Y || true
        flag_from_opts "$OPTS_CORE" tlp && INSTALL_TLP=Y || true
        flag_from_opts "$OPTS_CORE" thinkfan && INSTALL_THINKFAN=Y || true
        flag_from_opts "$OPTS_CORE" snapper_home && INSTALL_SNAPPER_HOME=Y || true
        flag_from_opts "$OPTS_CORE" linux_hardened && INSTALL_LINUX_HARDENED=Y || true
        flag_from_opts "$OPTS_CORE" linux_stable && INSTALL_LINUX_STABLE=Y || true
        flag_from_opts "$OPTS_CORE" linux_zen && INSTALL_LINUX_ZEN=Y || true
        flag_from_opts "$OPTS_CORE" plymouth && INSTALL_PLYMOUTH=Y || true
        flag_from_opts "$OPTS_CORE" selftest && INSTALL_SELFTEST=Y || true
        flag_from_opts "$OPTS_CORE" clean_esp && CLEAN_ESP_ARCH=Y || true
        flag_from_opts "$OPTS_CORE" chrome_hint && INSTALL_CHROME_HINT=Y || true
        flag_from_opts "$OPTS_CORE" btrfs_assistant && INSTALL_BTRFS_ASSISTANT=Y || true
        flag_from_opts "$OPTS_CORE" tuned && INSTALL_TUNED=Y || true
        flag_from_opts "$OPTS_CORE" multilib && INSTALL_MULTILIB=Y || true
        flag_from_opts "$OPTS_CORE" yay && INSTALL_YAY=Y || true

        flag_from_opts "$OPTS_TOOLS" devtools && INSTALL_DEVTOOLS=Y || true
        flag_from_opts "$OPTS_TOOLS" cli && INSTALL_CLI=Y || true
        flag_from_opts "$OPTS_TOOLS" starship && INSTALL_STARSHIP=Y || true
        flag_from_opts "$OPTS_TOOLS" podman && INSTALL_PODMAN=Y || true
        flag_from_opts "$OPTS_TOOLS" docker && INSTALL_DOCKER=Y || true
        flag_from_opts "$OPTS_TOOLS" virt && INSTALL_VIRT=Y || true
        flag_from_opts "$OPTS_TOOLS" ollama && INSTALL_OLLAMA=Y || true
        flag_from_opts "$OPTS_TOOLS" htop && EXTRA_PKGS+=(htop) || true
        flag_from_opts "$OPTS_TOOLS" tmux && EXTRA_PKGS+=(tmux) || true
        flag_from_opts "$OPTS_TOOLS" rsync && EXTRA_PKGS+=(rsync) || true
        flag_from_opts "$OPTS_TOOLS" bash_completion && EXTRA_PKGS+=(bash-completion) || true
        flag_from_opts "$OPTS_TOOLS" wget && EXTRA_PKGS+=(wget) || true
        flag_from_opts "$OPTS_TOOLS" usbutils && EXTRA_PKGS+=(usbutils) || true
        flag_from_opts "$OPTS_TOOLS" lsof && EXTRA_PKGS+=(lsof) || true
        flag_from_opts "$OPTS_TOOLS" dmidecode && EXTRA_PKGS+=(dmidecode) || true
        flag_from_opts "$OPTS_TOOLS" powertop && EXTRA_PKGS+=(powertop) || true
        flag_from_opts "$OPTS_TOOLS" mc && EXTRA_PKGS+=(mc) || true
        flag_from_opts "$OPTS_TOOLS" traceroute && EXTRA_PKGS+=(traceroute) || true
        flag_from_opts "$OPTS_TOOLS" bind && EXTRA_PKGS+=(bind) || true
        flag_from_opts "$OPTS_TOOLS" smartmontools && EXTRA_PKGS+=(smartmontools) || true

        flag_from_opts "$OPTS_NET" avahi && INSTALL_AVAHI=Y || true
        flag_from_opts "$OPTS_NET" wireguard && INSTALL_WIREGUARD=Y || true
        flag_from_opts "$OPTS_NET" tailscale && INSTALL_TAILSCALE=Y || true
        flag_from_opts "$OPTS_NET" fail2ban && INSTALL_FAIL2BAN=Y || true
        flag_from_opts "$OPTS_NET" fw_syncthing && FW_SYNCTHING=Y || true
        flag_from_opts "$OPTS_NET" fw_kdeconnect && FW_KDECONNECT=Y || true

        # Re-apply answers extras after checklist rebuild (dedupe later at pacstrap).
        if ((${#_extras_keep[@]})); then
          EXTRA_PKGS+=("${_extras_keep[@]}")
        fi
        unset -v _extras_keep
        if [[ $SKIP_REFLECTOR != Y ]]; then _ex_step=3; else REFLECTOR_COUNTRY=; _ex_step=4; fi
        ;;
      3)
        _ref_back=0
        while :; do
          _rc=0
          REFLECTOR_COUNTRY="$(WIZARD_CAN_BACK=1 ui_input "Reflector --country (ISO codes, comma-ok; empty=worldwide)" \
            "${REFLECTOR_COUNTRY:-}")" || _rc=$?
          if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _ref_back=1; break; fi
          if (( _rc != 0 )); then die "aborted"; fi
          unset -v _rc
          [[ -z $REFLECTOR_COUNTRY ]] || valid_reflector_country "$REFLECTOR_COUNTRY" && break
          ui_error "Reflector country: letters, spaces and commas only (e.g. DE,NL or Germany). Got: $REFLECTOR_COUNTRY"
        done
        if (( _ref_back )); then unset -v _ref_back; _ex_step=2; continue; fi
        unset -v _ref_back
        _ex_step=4
        ;;
      4)
        # Hook preset: none / env default (T14S_DEFAULT_HOOK_URL) / custom URL.
        # Never hardcode a private repo URL (smoke forbids linking private trees).
        _hp_none=on; _hp_env=off; _hp_custom=off
        if [[ -n ${POST_HOOK_URL:-} ]]; then
          _hp_none=off; _hp_custom=on
        elif [[ -n ${T14S_DEFAULT_HOOK_URL:-} ]]; then
          _hp_none=off; _hp_env=on
        fi
        _hook_menu=(none "skip post-install hook" "$_hp_none")
        if [[ -n ${T14S_DEFAULT_HOOK_URL:-} ]]; then
          _hook_menu+=(env "use T14S_DEFAULT_HOOK_URL" "$_hp_env")
        fi
        _hook_menu+=(custom "type a HTTPS hook URL" "$_hp_custom")
        _rc=0
        HOOK_PRESET="$(WIZARD_CAN_BACK=1 ui_radio "Post-install hook (curl|bash as root in new system)" \
          "${_hook_menu[@]}")" || _rc=$?
        unset -v _hp_none _hp_env _hp_custom _hook_menu
        if (( _rc == ${T14S_RC_BACK:-10} )); then
          unset -v _rc
          if [[ $SKIP_REFLECTOR != Y ]]; then _ex_step=3; else _ex_step=2; fi
          continue
        fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc
        case $HOOK_PRESET in
          env)
            POST_HOOK_URL=${T14S_DEFAULT_HOOK_URL:-}
            [[ -n $POST_HOOK_URL ]] || die "T14S_DEFAULT_HOOK_URL empty"
            ;;
          custom)
            _rc=0
            POST_HOOK_URL="$(WIZARD_CAN_BACK=1 ui_input "Post-install hook URL (HTTPS; empty=skip)" \
              "${POST_HOOK_URL:-}")" || _rc=$?
            if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc HOOK_PRESET; continue; fi
            if (( _rc != 0 )); then die "aborted"; fi
            unset -v _rc
            ;;
          *) POST_HOOK_URL= ;;
        esac
        unset -v HOOK_PRESET
        _ex_step=5
        ;;
      5)
        _rc=0
        _extra_in="$(WIZARD_CAN_BACK=1 ui_input "More pacstrap packages (space-separated, empty=none)" \
          "$_extra_in")" || _rc=$?
        if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; _ex_step=4; continue; fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc
        _ex_step=6
        ;;
    esac
  done
  unset -v _ex_step
fi

# TLP conflicts with GNOME power-profiles-daemon and with tuned — force off.
if yn_on "$DESKTOP" && yn_on "$INSTALL_TLP"; then
  warn "TLP skipped — GNOME uses power-profiles-daemon / tuned-ppd"
  INSTALL_TLP=N
fi
if yn_on "$INSTALL_TUNED" && yn_on "$INSTALL_TLP"; then
  warn "TLP skipped — tuned selected (tlp conflicts with tuned)"
  INSTALL_TLP=N
fi
# btrfs-assistant and first-boot Flatpak apps require GNOME desktop.
if [[ ${ROOT_FS:-btrfs} != btrfs ]]; then
  if yn_on "${INSTALL_SNAPPER_HOME:-N}"; then
    warn "Snapper @home skipped — ROOT_FS=${ROOT_FS} (Btrfs only)"
    INSTALL_SNAPPER_HOME=N
  fi
  if yn_on "${INSTALL_BTRFS_ASSISTANT:-N}"; then
    warn "btrfs-assistant skipped — ROOT_FS=${ROOT_FS} (Btrfs only)"
    INSTALL_BTRFS_ASSISTANT=N
  fi
fi
if yn_on "$INSTALL_BTRFS_ASSISTANT" && ! yn_on "$DESKTOP"; then
  warn "btrfs-assistant skipped — no desktop (use snapper CLI)"
  INSTALL_BTRFS_ASSISTANT=N
fi
if yn_on "${INSTALL_FLATPAK_APPS:-N}" && ! yn_on "$DESKTOP"; then
  warn "first-boot Flatpak apps skipped — no desktop"
  INSTALL_FLATPAK_APPS=N
fi
# Re-apply VM/ThinkPad skip after checklist (thinkfan may have been re-enabled).
if yn_on "$SKIP_THINKPAD_HW"; then
  INSTALL_THINKFAN=N
fi
# Ollama toggle applies to P15 and generic profiles (interactive + NONINTERACTIVE).
if yn_on "${INSTALL_OLLAMA:-N}" && [[ ${HW_PROFILE:-} != p15 && ${HW_PROFILE:-} != generic ]]; then
  warn "ollama skipped — supported on p15/generic profiles only"
  INSTALL_OLLAMA=N
fi
# Fresh-format ESP already empty; CLEAN_ESP_ARCH is ignored (forced Y in answers).
if [[ ${FORMAT_EFI:-1} == 1 ]]; then
  CLEAN_ESP_ARCH=Y
elif ! yn_on "${CLEAN_ESP_ARCH:-Y}"; then
  warn "CLEAN_ESP_ARCH=N — keeping prior Arch UKIs/arch*.conf; kernels/ucode still removed (pacstrap). Boot menu may show dead entries until you delete them."
fi
# Reflector country sanitize (answers file / env; the prompt already re-asks).
if [[ -n ${REFLECTOR_COUNTRY:-} ]] && ! valid_reflector_country "$REFLECTOR_COUNTRY"; then
  ui_warn "Ignoring invalid REFLECTOR_COUNTRY=$REFLECTOR_COUNTRY (letters, spaces and commas only): mirrors will be ranked worldwide."
  REFLECTOR_COUNTRY=
fi

# Optional free-form extras (archfi -cpl spirit). Env T14S_EXTRA_PKGS appends.
if [[ -n ${_extra_in// /} ]]; then
  read -r -a _pkgs <<<"$_extra_in"
  for _p in "${_pkgs[@]}"; do
    if [[ $_p =~ ^[a-z0-9][a-z0-9@._+-]*$ ]]; then
      EXTRA_PKGS+=("$_p")
    else
      ui_warn "Skipping invalid package name: $_p"
    fi
  done
fi
unset -v _extra_in _p _pkgs
# Persist extras for answers replay (space-separated).
EXTRA_PKGS_LIST="${EXTRA_PKGS[*]:-}"

# Canonicalize boolean flags (answers may use on/1; chroot + saves want Y/N).
for _flag in DESKTOP ENCRYPT_ROOT INSTALL_FLATPAK_APPS INSTALL_BLUETOOTH INSTALL_VM_GUEST VM_FAST_PKG VM_SERIAL_CONSOLE \
  INSTALL_NERD_FONTS ENROLL_SB ENABLE_SSHD INSTALL_CUPS \
  SKIP_REFLECTOR INSTALL_TLP INSTALL_CLI INSTALL_PODMAN INSTALL_DOCKER \
  INSTALL_VIRT INSTALL_AVAHI INSTALL_WIREGUARD INSTALL_TAILSCALE \
  INSTALL_STARSHIP INSTALL_CHROME_HINT INSTALL_FAIL2BAN INSTALL_THINKFAN \
  INSTALL_SNAPPER_HOME INSTALL_LINUX_HARDENED INSTALL_LINUX_STABLE INSTALL_LINUX_ZEN INSTALL_PLYMOUTH INSTALL_SELFTEST \
  CLEAN_ESP_ARCH INSTALL_MULTILIB INSTALL_YAY INSTALL_TUNED INSTALL_DEVTOOLS INSTALL_BTRFS_ASSISTANT \
  INSTALL_OLLAMA FW_SYNCTHING FW_KDECONNECT \
  SKIP_THINKPAD_HW
do
  [[ -v $_flag ]] || printf -v "$_flag" '%s' N
  yn_canon "$_flag"
done
unset -v _flag
