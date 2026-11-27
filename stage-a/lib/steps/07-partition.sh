# 07-partition.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Wizard step 5/11: partition strategy (AUTO / MANUAL, ESP handling).
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

require_ni_erase() {
  (( WILL_ERASE == 1 )) \
    || die "NONINTERACTIVE destructive install needs T14S_I_WILL_ERASE=1 (or y/yes/on)"
}

# ── 2. partition strategy ───────────────────────────────────
ui_step 5 Partition
_part_step=mode
while :; do
if [[ $_part_step == mode ]]; then
  if (( NONINTERACTIVE )); then
    [[ ${MODE:-} == auto || ${MODE:-} == manual ]] \
      || die "NONINTERACTIVE needs MODE=auto|manual in answers"
  elif (( ${QUICK_VM:-0} )); then
    MODE=auto
    WIZARD_SKIPPED_STEP=1
  else
    _mode_auto=on; _mode_man=off
    [[ ${MODE:-auto} == manual ]] && { _mode_auto=off; _mode_man=on; }
    _rc=0
    MODE="$(ui_radio "How should $DISK be partitioned?" \
      auto "wipe ALL of $DISK: EFI + root" "$_mode_auto" \
      manual "select existing partitions (EFI format or reuse)" "$_mode_man")" || _rc=$?
    unset -v _mode_auto _mode_man
    if (( _rc == ${T14S_RC_BACK:-10} )); then
      unset -v _rc _part_step; WIZARD_BACK=1; return 0
    elif (( _rc != 0 )); then
      die "aborted"
    fi
    unset -v _rc
  fi
  _part_step=body
fi

if [[ $MODE == auto ]]; then
  FORMAT_EFI=1
  _auto_back=0
  while :; do
    if (( NONINTERACTIVE )); then
      [[ ${ESP_MB:-} =~ ^(1024|2048|4096)$ ]] \
        || die "NONINTERACTIVE AUTO needs ESP_MB=1024|2048|4096 in answers"
    elif (( ${QUICK_VM:-0} )); then
      ESP_MB=${ESP_MB:-1024}
    else
      _e2=off; _e1=off; _e4=off
      case ${ESP_MB:-2048} in
        1024) _e1=on ;;
        4096) _e4=on ;;
        *) _e2=on; ESP_MB=2048 ;;
      esac
      _rc=0
      ESP_MB="$(WIZARD_CAN_BACK=1 ui_radio "EFI system partition size on $DISK" \
        2048 "2G — recommended for dual UKIs" "$_e2" \
        1024 "1G — minimum comfortable" "$_e1" \
        4096 "4G — extra multiboot headroom" "$_e4")" || _rc=$?
      unset -v _e2 _e1 _e4
      if (( _rc == ${T14S_RC_BACK:-10} )); then
        unset -v _rc; _auto_back=1; break
      elif (( _rc != 0 )); then
        die "aborted"
      fi
      unset -v _rc
    fi
    disk_mb="$(size_mb "$DISK")"
    (( disk_mb > ESP_MB + 8192 )) && break
    if (( NONINTERACTIVE || ${QUICK_VM:-0} )); then
      die "Disk is only ${disk_mb}MB — ESP_MB=${ESP_MB} will not fit with 8GB root"
    fi
    ui_error "Disk is only ${disk_mb}MB — ${ESP_MB}MB ESP plus an 8GB root will not fit.
Pick a smaller ESP."
    ESP_MB=""
  done
  if (( _auto_back )); then
    unset -v _auto_back; _part_step=mode; continue
  fi
  unset -v _auto_back

  if (( NONINTERACTIVE )); then
    require_ni_erase
    warn "NONINTERACTIVE AUTO: will erase entire $DISK (ESP ${ESP_MB}MB + root)"
  elif (( ${QUICK_VM:-0} )); then
    # Quick VM skips intermediate type-DISK prompt; final Erase confirm still runs in Review.
    ok "Quick VM AUTO layout: ${ESP_MB}MB ESP + ${ROOT_FS:-ext4} root on $DISK"
  else
    # Compact on purpose: the partition table being erased must fit an 80x24
    # console without scrolling.
    ui_critical "AUTO mode ERASES the ENTIRE disk $DISK,
including any Windows / other-OS partitions on it.
Plan: GPT · ${ESP_MB}MB ESP (FAT32) · remainder LUKS2 + root FS

$(lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME "$DISK" 2>/dev/null)"
    _rc=0
    CONF="$(WIZARD_CAN_BACK=1 ui_input "Type the disk path to confirm total wipe" "")" || _rc=$?
    if (( _rc == ${T14S_RC_BACK:-10} )); then
      unset -v _rc; _part_step=body; continue
    elif (( _rc != 0 )); then
      die "aborted"
    fi
    unset -v _rc
    [[ $CONF == "$DISK" ]] || die "disk confirmation mismatch — aborting"
    ui_yesno "ERASE $DISK now?" no erase || die "aborted"
  fi
  # names only; the destructive writes run in the execute phase
  EFI_PART="$(part_of "$DISK" 1)"
  ROOT_PART="$(part_of "$DISK" 2)"
  break
else
  # MANUAL: honor EFI_PART/ROOT_PART/FORMAT_EFI from answers under NONINTERACTIVE.
  if (( NONINTERACTIVE )); then
    [[ -n ${EFI_PART:-} && -n ${ROOT_PART:-} && -b ${EFI_PART:-/dev/null} && -b ${ROOT_PART:-/dev/null} ]] \
      || die "NONINTERACTIVE MANUAL needs EFI_PART and ROOT_PART block devices in answers"
    require_ni_erase
    EFI_PART="$(readlink -f -- "$EFI_PART" 2>/dev/null || printf '%s' "$EFI_PART")"
    ROOT_PART="$(readlink -f -- "$ROOT_PART" 2>/dev/null || printf '%s' "$ROOT_PART")"
    [[ $EFI_PART != "$ROOT_PART" ]] || die "EFI_PART and ROOT_PART must differ"
    part_on_disk "$EFI_PART" "$DISK" \
      || die "EFI_PART $EFI_PART is not on DISK $DISK"
    part_on_disk "$ROOT_PART" "$DISK" \
      || die "ROOT_PART $ROOT_PART is not on DISK $DISK"
    case ${FORMAT_EFI:-1} in
      0|n|N|no|NO|off|OFF|false|FALSE) FORMAT_EFI=0 ;;
      1|y|Y|yes|YES|on|ON|true|TRUE) FORMAT_EFI=1 ;;
      *) die "NONINTERACTIVE MANUAL needs FORMAT_EFI=0|1 (or N/Y), got: ${FORMAT_EFI}" ;;
    esac
    efifs="$(part_fs "$EFI_PART")"
    if (( FORMAT_EFI == 0 )) && [[ $efifs != vfat ]]; then
      die "FORMAT_EFI=0 but $EFI_PART is '${efifs:-empty}', not FAT32"
    fi
    efi_mb="$(size_mb "$EFI_PART")"
    root_mb="$(size_mb "$ROOT_PART")"
    if (( efi_mb < 512 )); then
      die "ESP $EFI_PART is only ${efi_mb}MB (need ≥512; enlarge or pick another)"
    fi
    if (( root_mb < 8192 )); then
      die "ROOT $ROOT_PART is only ${root_mb}MB (need ≥8192)"
    fi
    ok "MANUAL partitions from answers: EFI=$EFI_PART ROOT=$ROOT_PART format_efi=$FORMAT_EFI"
    break
  else
    ui_info "Manual partitioning on $DISK. Current layout (pick from lists next):

$(lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME "$DISK" 2>/dev/null)"

    _man_back=0
    while :; do
      _rc=0
      ROOT_PART="$(WIZARD_CAN_BACK=1 pick_part "Select ROOT — ERASED, becomes LUKS2 + Btrfs" "$DISK")" || _rc=$?
      if (( _rc == ${T14S_RC_BACK:-10} )); then
        unset -v _rc; _man_back=1; break
      elif (( _rc != 0 )); then
        die "aborted"
      fi
      unset -v _rc
      _efi_back=0
      while :; do
        # Default to reuse when the disk already has a FAT32 ESP (shared with
        # Windows / another OS); formatting it would delete their boot loaders.
        _ef_reuse=off; _ef_fmt=on
        if lsblk -prno FSTYPE "$DISK" 2>/dev/null | grep -qx vfat; then _ef_reuse=on; _ef_fmt=off; fi
        _rc=0
        EFIMODE="$(WIZARD_CAN_BACK=1 ui_radio "EFI handling for $ROOT_PART" \
          reuse "keep an existing FAT32 ESP (multiboot-safe)" "$_ef_reuse" \
          format "format a partition as ESP (destroys its contents)" "$_ef_fmt")" || _rc=$?
        unset -v _ef_reuse _ef_fmt
        if (( _rc == ${T14S_RC_BACK:-10} )); then
          unset -v _rc; _efi_back=1; break
        elif (( _rc != 0 )); then
          die "aborted"
        fi
        unset -v _rc
        if [[ $EFIMODE == reuse ]]; then FORMAT_EFI=0; else FORMAT_EFI=1; fi

        if (( FORMAT_EFI == 0 )) && ! lsblk -prno FSTYPE "$DISK" 2>/dev/null | grep -qx vfat; then
          ui_warn "No FAT32 ESP exists on $DISK. Pick format mode instead (or cancel to abort)."
          continue
        fi

        _rc=0
        if (( FORMAT_EFI == 0 )); then
          EFI_PART="$(WIZARD_CAN_BACK=1 pick_part "Select the existing ESP (must be FAT32)" "$DISK" any "$ROOT_PART")" || _rc=$?
        else
          EFI_PART="$(WIZARD_CAN_BACK=1 pick_part "Select the partition to FORMAT as ESP" "$DISK" any "$ROOT_PART")" || _rc=$?
        fi
        if (( _rc == ${T14S_RC_BACK:-10} )); then unset -v _rc; continue; fi
        if (( _rc != 0 )); then die "aborted"; fi
        unset -v _rc
        [[ $EFI_PART != "$ROOT_PART" ]] || { ui_error "EFI and ROOT cannot be the same partition."; continue; }

        efifs="$(part_fs "$EFI_PART")"
        if (( FORMAT_EFI == 0 )) && [[ $efifs != vfat ]]; then
          ui_error "$EFI_PART is '${efifs:-empty}', not FAT32 — reuse needs an existing ESP.
Pick format mode or another partition."
          continue
        fi
        efi_mb="$(size_mb "$EFI_PART")"
        if (( efi_mb < 512 )); then
          ui_yesno "ESP $EFI_PART is only ${efi_mb}MB. Dual UKIs will not fit.
Use it anyway?" no warn || continue
        elif (( efi_mb < 1024 )); then
          ui_warn "Note: ESP is ${efi_mb}MB — 1G+ is recommended for dual UKIs."
        fi
        break
      done
      if (( _efi_back )); then unset -v _efi_back; continue; fi
      unset -v _efi_back
      break
    done
    if (( _man_back )); then
      unset -v _man_back; _part_step=mode; continue
    fi
    unset -v _man_back

    root_mb="$(size_mb "$ROOT_PART")"
    if (( root_mb < 8192 )); then
      ui_yesno "ROOT $ROOT_PART is only ${root_mb}MB — 8G+ is recommended.
Use it anyway?" no warn || die "aborted"
    fi

    if (( FORMAT_EFI == 0 )); then
      _m="$(mktemp -d)"
      _esp_entries=""
      if mount -o ro "$EFI_PART" "$_m" 2>/dev/null; then
        _esp_entries="$(find "$_m/EFI" -maxdepth 1 -mindepth 1 2>/dev/null | sed 's,.*/,   ,' || true)"
        umount "$_m" || true
      fi
      rmdir "$_m" 2>/dev/null || true
      ui_info "Reusing ESP $EFI_PART (FAT, kept).

Existing /EFI entries (other OSes stay bootable):
${_esp_entries:-   (none)}

Changed on this ESP: systemd-boot is installed, /EFI/BOOT/BOOTX64.EFI (the
firmware fallback loader) is replaced, and /loader/loader.conf is rewritten.
Originals are kept as *.pre-arch.bak next to them."
    elif [[ $efifs == vfat ]]; then
      ui_critical "DANGER: $EFI_PART is ALREADY FAT — likely a shared ESP.
Formatting ERASES other OSes' bootloaders."
    fi

    ROOT_PART="$(readlink -f -- "$ROOT_PART" 2>/dev/null || printf '%s' "$ROOT_PART")"
    EFI_PART="$(readlink -f -- "$EFI_PART" 2>/dev/null || printf '%s' "$EFI_PART")"
    # Precompute sizes/labels so the prompt has no nested quotes (smoke parses it).
    _proc_root_mb="$(size_mb "$ROOT_PART")"
    _proc_efi_lbl=$([[ $FORMAT_EFI == 1 ]] && echo FORMATTED || echo REUSED)
    ui_yesno "Proceed with these partitions?

  ROOT  $ROOT_PART  ${_proc_root_mb}MB  ERASED → LUKS2
  EFI   $EFI_PART  ${efi_mb}MB  ${_proc_efi_lbl}" no erase \
      || die "aborted"
    unset -v _proc_root_mb _proc_efi_lbl
    break
  fi
fi
done
unset -v _part_step
ok "EFI=$EFI_PART  ROOT=$ROOT_PART  (format_efi=$FORMAT_EFI)"
