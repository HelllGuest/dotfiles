# 12-review.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Wizard step 10/11: review, answers save, DRYRUN exit. Nothing written before this.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── final summary ───────────────────────────────────────────
ui_step 10 Review
_rev_disk_mb="$(size_mb "$DISK")"
if [[ $MODE == auto ]]; then
  _rev_efi_mb="$ESP_MB"
  _rev_root_mb=$(( _rev_disk_mb > ESP_MB ? _rev_disk_mb - ESP_MB : 0 ))
else
  _rev_efi_mb="$(size_mb "$EFI_PART")"
  _rev_root_mb="$(size_mb "$ROOT_PART")"
fi
if [[ $INSTALL_TUNED == Y && $DESKTOP == Y ]]; then
  _rev_power='tuned + tuned-ppd'
elif [[ $INSTALL_TUNED == Y ]]; then
  _rev_power='tuned'
elif [[ $DESKTOP == Y ]]; then
  _rev_power='power-profiles-daemon'
elif [[ $INSTALL_TLP == Y ]]; then
  _rev_power='tlp'
else
  _rev_power='none'
fi
_REVIEW="REVIEW — nothing has been written yet.

  Hardware      ${HW_PROFILE:-generic}
  Disk          $DISK ${_rev_disk_mb}MB ($([[ $MODE == auto ]] && echo "AUTO wipe, ${ESP_MB}MB ESP" || echo manual))
  EFI           $EFI_PART ${_rev_efi_mb}MB ($([[ $FORMAT_EFI == 1 ]] && echo format || echo reuse))
  Clean ESP     $CLEAN_ESP_ARCH (old Arch UKIs/entries/EFI/arch)
  ROOT          $ROOT_PART ${_rev_root_mb}MB ($([[ ${ENCRYPT_ROOT:-Y} == Y ]] && echo "LUKS2, wipe=${LUKS_WIPE}" || echo "unencrypted"))
  Hostname      $HOSTNAME
  Timezone      $TIMEZONE
  Locale        $LOCALE
  Keymap        $KEYMAP
  User          $USERNAME
  Profile       $PRESET
  Parallel DL   $PACMAN_PARALLEL
  FS / zram     $([[ ${ROOT_FS:-btrfs} == btrfs ]] && echo "btrfs (compress=$BTRFS_COMPRESS)" || echo "${ROOT_FS}") zram=$ZRAM_SIZE
  VM opts       guest=${INSTALL_VM_GUEST:-N} serial=${VM_SERIAL_CONSOLE:-N} fast_pkg=${VM_FAST_PKG:-N}
  Reflector     $([[ $SKIP_REFLECTOR == Y ]] && echo "skip (ISO mirrorlist until the weekly reflector run)" || echo "refresh${REFLECTOR_COUNTRY:+ ($REFLECTOR_COUNTRY)}")
  ThinkPad HW   $([[ $SKIP_THINKPAD_HW == Y ]] && echo skip || echo apply)
  Extra pkgs    $( ((${#EXTRA_PKGS[@]})) && printf '%s ' "${EXTRA_PKGS[@]}" || echo none)
  Desktop       $([[ $DESKTOP == Y ]] && echo "minimal GNOME (flatpak-apps=$INSTALL_FLATPAK_APPS)" || echo none)
  Bluetooth     $INSTALL_BLUETOOTH
  Nerd Fonts    $([[ $INSTALL_NERD_FONTS == Y ]] && echo 'JetBrainsMono + Inter/Noto' || echo no)
  Snapper       $([[ ${ROOT_FS:-btrfs} == btrfs ]] && echo "home=$INSTALL_SNAPPER_HOME gui=$INSTALL_BTRFS_ASSISTANT" || echo "none ($ROOT_FS)")
  pacman/AUR    multilib=$INSTALL_MULTILIB yay=$INSTALL_YAY
  Power         $_rev_power
  Dev/Ollama    devtools=$INSTALL_DEVTOOLS ollama=$INSTALL_OLLAMA starship=$INSTALL_STARSHIP
  Kernels       lts=Y hardened=$INSTALL_LINUX_HARDENED stable=$INSTALL_LINUX_STABLE zen=$INSTALL_LINUX_ZEN plymouth=$INSTALL_PLYMOUTH
  CLI/Podman    cli=$INSTALL_CLI podman=$INSTALL_PODMAN docker=$INSTALL_DOCKER virt=$INSTALL_VIRT
  Net           avahi=$INSTALL_AVAHI wg=$INSTALL_WIREGUARD tailscale=$INSTALL_TAILSCALE
  Firewall      default=drop syncthing=$FW_SYNCTHING kdeconnect=$FW_KDECONNECT
  CUPS/TLP/SB   cups=$INSTALL_CUPS tlp=$INSTALL_TLP sb=$ENROLL_SB
  SSH/f2b       sshd=$ENABLE_SSHD pubkey=$([[ -n ${SSH_PUBKEY:-} ]] && echo set || echo none) fail2ban=$INSTALL_FAIL2BAN
  Helpers       selftest=$INSTALL_SELFTEST chrome=$INSTALL_CHROME_HINT thinkfan=$INSTALL_THINKFAN
  Hook URL      ${POST_HOOK_URL:-none}
  Pass file     ${PASS_FILE:-none}

Typed passwords are not redisplayed."
if (( NONINTERACTIVE )); then
  ok "NONINTERACTIVE: skipping REVIEW/confirm UI"
  printf '%s\n' "$_REVIEW" | while IFS= read -r _l; do say "$_l"; done
else
  ui_info "$_REVIEW"
  if ! ui_yesno "Start the installation? The partitions above will be ERASED." no erase; then
    _rev_opts=()
    if (( ${#_t14s_hist[@]} > 0 )); then
      _rev_opts+=(back "Back to previous step")
    fi
    _rev_opts+=(
      jump "Jump to a specific step"
      abort "Abort installation"
    )
    _rev_act="$(WIZARD_CAN_BACK=0 ui_menu "Installation not started — go back to change an option or abort?" \
      "${_rev_opts[@]}")" || die "aborted by user"
    unset -v _rev_opts
    case $_rev_act in
      back)
        unset -v _REVIEW _l _rev_disk_mb _rev_efi_mb _rev_root_mb _rev_power _rev_act
        WIZARD_BACK=1
        return 0
        ;;
      jump)
        _jump_opts=()
        if (( ${_HW_PROMPTED:-0} )); then
          _jump_opts+=(04-hardware.sh "Step 2 · Hardware profile")
        fi
        _jump_opts+=(
          05-profile.sh "Step 3 · Profile preset"
          06-disk.sh    "Step 4 · Target disk"
        )
        if (( ! ${QUICK_VM:-0} )); then
          _jump_opts+=(07-partition.sh "Step 5 · Partition layout")
        fi
        if yn_on "${ENCRYPT_ROOT:-Y}"; then
          _jump_opts+=(08-luks.sh "Step 6 · LUKS passphrase & wipe")
        fi
        _jump_opts+=(09-identity.sh "Step 7 · Hostname, timezone, locale, user")
        if (( ! ${QUICK_VM:-0} )); then
          _jump_opts+=(
            10-downloads.sh "Step 8 · Parallel downloads, FS, zram"
            11-extras.sh    "Step 9 · Extras, reflector, hook"
          )
        fi
        _jump_opts+=(12-review.sh "Back to Review")
        _jump_step="$(WIZARD_CAN_BACK=0 ui_menu "Jump to which step?" \
          "${_jump_opts[@]}")" || die "aborted by user"
        unset -v _REVIEW _l _rev_disk_mb _rev_efi_mb _rev_root_mb _rev_power _rev_act _jump_opts
        WIZARD_JUMP="$_jump_step"
        unset -v _jump_step
        return 0
        ;;
      *) die "aborted by user" ;;
    esac
  fi
fi
unset -v _REVIEW _l _rev_disk_mb _rev_efi_mb _rev_root_mb _rev_power

# Validate optional post-hook URL and SHA-256 pin before wipe / DRYRUN exit.
if [[ -n ${POST_HOOK_URL:-} ]]; then
  [[ $POST_HOOK_URL =~ ^https://[^[:space:]@]+$ ]] \
    || die "POST_HOOK_URL must be https://… with no userinfo or spaces (got: $POST_HOOK_URL)"
fi
if [[ -n ${T14S_POST_HOOK_SHA256:-} ]]; then
  [[ $T14S_POST_HOOK_SHA256 =~ ^[0-9a-fA-F]{64}$ ]] \
    || die "T14S_POST_HOOK_SHA256 must be 64 hex chars (got: $T14S_POST_HOOK_SHA256)"
fi

ANSWERS_OUT="${T14S_ANSWERS_OUT:-/tmp/t14s-answers.env}"
answers_save "$ANSWERS_OUT" || warn "could not write answers to $ANSWERS_OUT"
ok "answers saved: $ANSWERS_OUT (reload: T14S_ANSWERS=$ANSWERS_OUT)"

if (( DRYRUN )); then
  printf 'DRYRUN: preset=%s fs=%s EFI=%s ROOT=%s host=%s user=%s locale=%s tz=%s keymap=%s wipe=%s parallel=%s desktop=%s nerd=%s cli=%s podman=%s docker=%s virt=%s avahi=%s sshd=%s extra=%s\n' \
    "$PRESET" "${ROOT_FS:-btrfs}" "$EFI_PART" "$ROOT_PART" "$HOSTNAME" "$USERNAME" \
    "$LOCALE" "$TIMEZONE" "$KEYMAP" "$LUKS_WIPE" "$PACMAN_PARALLEL" \
    "$DESKTOP" "$INSTALL_NERD_FONTS" "$INSTALL_CLI" "$INSTALL_PODMAN" \
    "$INSTALL_DOCKER" "$INSTALL_VIRT" "$INSTALL_AVAHI" "$ENABLE_SSHD" \
    "${EXTRA_PKGS[*]:-}"
  exit 0
fi
