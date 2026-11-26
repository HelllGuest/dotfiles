#!/usr/bin/env bash
# 40-disk.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# LUKS/Btrfs helpers. Orchestrator calls these after disk selection.

# True if path is the confirmed install target (root/EFI or AUTO child of DISK).
_on_target() {
  local d=$1 rp ep
  if [[ $d == /dev/mapper/cryptroot ]]; then
    d=$(cryptsetup status cryptroot 2>/dev/null | awk '$1 == "device:" {print $2}')
  fi
  [[ -n $d ]] || return 1
  d=$(readlink -f -- "$d" 2>/dev/null || printf '%s' "$d")
  rp=$(readlink -f -- "${ROOT_PART:-}" 2>/dev/null || printf '%s' "${ROOT_PART:-}")
  ep=$(readlink -f -- "${EFI_PART:-}" 2>/dev/null || printf '%s' "${EFI_PART:-}")
  if [[ $d == "$rp" || $d == "$ep" ]]; then return 0; fi
  if [[ $MODE == auto ]]; then part_on_disk "$d" "$DISK"; else return 1; fi
}

# Wipe LUKS mapper before mkfs. count_bytes = exact size → dd exit 0 on success.
_luks_wipe() {
  local desc=$1; shift
  local rc=0 size
  size=$(blockdev --getsize64 /dev/mapper/cryptroot) || die "LUKS wipe: cannot read cryptroot size"
  set +e
  run_progress "$desc" "$@" iflag=count_bytes count="$size"
  rc=$?
  set -e
  (( rc == 0 )) || die "LUKS wipe failed (dd exit $rc)"
}

# Release leftover mounts/swap/cryptroot on the confirmed target only.
release_target_devices() {
  if mountpoint -q /mnt; then
    local _src
    _src=$(findmnt -nvo SOURCE /mnt)
    _on_target "$_src" || die "/mnt is mounted from $_src, not the install target — unmount it and re-run"
    umount -R /mnt
  fi
  local _sw
  while read -r _sw; do
    if _on_target "$_sw"; then swapoff "$_sw"; fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null)
  if [[ -e /dev/mapper/cryptroot ]]; then
    _on_target /dev/mapper/cryptroot \
      || die "/dev/mapper/cryptroot is open on another device — close it and re-run"
    cryptsetup close cryptroot
  fi
}

# Optional LUKS mapper wipe (archfi normal/fast).
apply_luks_wipe() {
  case ${LUKS_WIPE:-none} in
    fast)
      _luks_wipe "wiping cryptroot (fast dd bs=64M)" \
        dd if=/dev/zero of=/dev/mapper/cryptroot bs=64M status=progress
      ;;
    normal)
      _luks_wipe "wiping cryptroot (dd)" \
        dd if=/dev/zero of=/dev/mapper/cryptroot status=progress
      ;;
  esac
}

# Root filesystem (btrfs / ext4 / xfs) + mount layout + ESP.
do_filesystems_and_mount() {
  local rdev=${ROOT_DEV:-/dev/mapper/cryptroot}
  case ${ROOT_FS:-btrfs} in
    btrfs)
      step "btrfs + subvolumes on $rdev"
      mkfs.btrfs -f -L archroot "$rdev" >/dev/null
      mount "$rdev" /mnt
      local sv
      for sv in @ @home @snapshots @var_log @var_cache @tmp; do
        btrfs subvolume create "/mnt/$sv" >/dev/null
      done
      chattr +C /mnt/@tmp 2>/dev/null || true   # nodatacow inheritance
      umount /mnt

      local CO
      case ${BTRFS_COMPRESS:-zstd3} in
        zstd1) CO="noatime,compress=zstd:1,ssd,space_cache=v2" ;;
        zstd15) CO="noatime,compress=zstd:15,ssd,space_cache=v2" ;;
        none) CO="noatime,ssd,space_cache=v2" ;;
        *) CO="noatime,compress=zstd:3,ssd,space_cache=v2" ;;
      esac
      mount -o "$CO,subvol=@" "$rdev" /mnt
      mkdir -p /mnt/{home,.snapshots,var/log,var/cache,tmp,boot}
      mount -o "$CO,subvol=@home"      "$rdev" /mnt/home
      mount -o "$CO,subvol=@snapshots" "$rdev" /mnt/.snapshots
      mount -o "$CO,subvol=@var_log"   "$rdev" /mnt/var/log
      mount -o "$CO,subvol=@var_cache" "$rdev" /mnt/var/cache
      mount -o "noatime,nodatacow,nosuid,nodev,subvol=@tmp" "$rdev" /mnt/tmp
      chmod 1777 /mnt/tmp
      ;;
    ext4)
      step "ext4 on $rdev"
      mkfs.ext4 -F -L archroot "$rdev" >/dev/null
      mount -o noatime "$rdev" /mnt
      mkdir -p /mnt/boot
      ;;
    xfs)
      step "xfs on $rdev"
      mkfs.xfs -f -L archroot "$rdev" >/dev/null
      mount -o noatime "$rdev" /mnt
      mkdir -p /mnt/boot
      ;;
    *)
      die "unsupported ROOT_FS=${ROOT_FS:-} (use btrfs|ext4|xfs)"
      ;;
  esac

  if [[ ${FORMAT_EFI:-0} == 1 ]]; then
    step "format ESP $EFI_PART"
    wipefs -a "$EFI_PART" >/dev/null 2>&1 || true
    mkfs.fat -F32 -n EFI "$EFI_PART"
    sync
  fi
  udevadm settle 2>/dev/null || true
  mount -t vfat "$EFI_PART" /mnt/boot
  local esp_mb
  esp_mb=$(df -Pm /mnt/boot | awk 'NR==2{print $2}'); esp_mb=${esp_mb:-0}
  (( esp_mb >= 1024 )) || warn "ESP is ${esp_mb}MB — dual-kernel UKIs want >=1024MB; install may fill it"
  step "cleaning prior Arch boot artifacts on ESP (CLEAN_ESP_ARCH=$CLEAN_ESP_ARCH)"
  clean_esp_arch_files /mnt/boot
  ok "filesystems mounted (${ROOT_FS:-btrfs}, ESP ${esp_mb}MB)"
}
