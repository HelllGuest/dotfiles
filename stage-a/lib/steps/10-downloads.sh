# 10-downloads.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# Wizard step 8/11: pacman parallel downloads, root filesystem, Btrfs compression, zram.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

ui_step 8 Storage
ROOT_FS="${ROOT_FS:-btrfs}"
ROOT_FS="${ROOT_FS,,}"
if (( NONINTERACTIVE || ${QUICK_VM:-0} )); then
  [[ $PACMAN_PARALLEL =~ ^(5|10|15)$ ]] \
    || die "NONINTERACTIVE needs PACMAN_PARALLEL=5|10|15"
  [[ ${ROOT_FS:-btrfs} =~ ^(btrfs|ext4|xfs)$ ]] \
    || die "NONINTERACTIVE needs ROOT_FS=btrfs|ext4|xfs (got: ${ROOT_FS:-})"
  if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
    [[ $BTRFS_COMPRESS =~ ^(zstd1|zstd3|zstd15|none)$ ]] \
      || die "NONINTERACTIVE needs BTRFS_COMPRESS=zstd1|zstd3|zstd15|none"
  fi
  [[ $ZRAM_SIZE =~ ^(half|quarter|8192)$ ]] \
    || die "NONINTERACTIVE needs ZRAM_SIZE=half|quarter|8192"
else
  _p5=off; _p10=on; _p15=off
  case $PACMAN_PARALLEL in 5) _p5=on; _p10=off ;; 15) _p15=on; _p10=off ;; esac
  PACMAN_PARALLEL="$(ui_radio "pacman ParallelDownloads (live + target)" \
    5 "conservative (slow / flaky links)" "$_p5" \
    10 "balanced (default)" "$_p10" \
    15 "aggressive (fast links)" "$_p15")" || die "aborted"
  unset -v _p5 _p10 _p15

  _fb=on; _fe=off; _fx=off
  case ${ROOT_FS:-btrfs} in
    ext4) _fe=on; _fb=off ;;
    xfs)  _fx=on; _fb=off ;;
    *)    ROOT_FS=btrfs ;;
  esac
  ROOT_FS="$(ui_radio "Root filesystem (inside LUKS2)" \
    btrfs "Btrfs — subvolumes, zstd compression, Snapper snapshots (default)" "$_fb" \
    ext4 "ext4 — mature, simple, fast fsck (no Snapper)" "$_fe" \
    xfs "XFS — high-throughput journaled FS (no Snapper, no shrink)" "$_fx")" || die "aborted"
  unset -v _fb _fe _fx

  if [[ $ROOT_FS == btrfs ]]; then
    _bc3=on; _bc1=off; _bc15=off; _bc0=off
    case $BTRFS_COMPRESS in
      zstd1) _bc1=on; _bc3=off ;;
      zstd15) _bc15=on; _bc3=off ;;
      none) _bc0=on; _bc3=off ;;
      *) BTRFS_COMPRESS=zstd3 ;;
    esac
    BTRFS_COMPRESS="$(ui_radio "Btrfs compression (mount options)" \
      zstd3 "zstd:3 — default balance" "$_bc3" \
      zstd1 "zstd:1 — faster, larger" "$_bc1" \
      zstd15 "zstd:15 — smaller, slower" "$_bc15" \
      none "no compression" "$_bc0")" || die "aborted"
    unset -v _bc3 _bc1 _bc15 _bc0
  fi

  _zh=on; _zq=off; _z8=off
  case $ZRAM_SIZE in
    quarter) _zq=on; _zh=off ;;
    8192) _z8=on; _zh=off ;;
    *) ZRAM_SIZE=half ;;
  esac
  ZRAM_SIZE="$(ui_radio "zram size" \
    half "min(RAM/2, 16G) — default" "$_zh" \
    quarter "min(RAM/4, 8G)" "$_zq" \
    8192 "fixed 8G" "$_z8")" || die "aborted"
  unset -v _zh _zq _z8
fi
[[ $PACMAN_PARALLEL =~ ^(5|10|15)$ ]] || PACMAN_PARALLEL=10
[[ ${ROOT_FS:-btrfs} =~ ^(btrfs|ext4|xfs)$ ]] || ROOT_FS=btrfs
[[ $BTRFS_COMPRESS =~ ^(zstd1|zstd3|zstd15|none)$ ]] || BTRFS_COMPRESS=zstd3
[[ $ZRAM_SIZE =~ ^(half|quarter|8192)$ ]] || ZRAM_SIZE=half
