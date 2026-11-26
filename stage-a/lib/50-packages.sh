#!/usr/bin/env bash
# 50-packages.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash

# Package list assembly, prefetch and pacman_tune. pacstrap itself runs in
# lib/steps/22-install-base.sh.

t14s_base_packages() {
  # Populates BASE_PKGS; call after UCODE and optional kernel / PLYMOUTH flags are set.
  if [[ ! -v UCODE ]]; then UCODE=amd-ucode; fi
  BASE_PKGS=(
    base base-devel
    linux-lts linux-lts-headers
    networkmanager sudo zsh git vim nano
    reflector pacman-contrib
    mkinitcpio zram-generator
    apparmor firewalld sbctl efibootmgr
    wireless-regdb
    xdg-user-dirs
  )
  if ! yn_on "${VM_FAST_PKG:-N}"; then
    BASE_PKGS+=(linux-firmware)
  fi
  if yn_on "${ENCRYPT_ROOT:-Y}"; then
    BASE_PKGS+=(cryptsetup)
  fi
  case ${ROOT_FS:-btrfs} in
    btrfs) BASE_PKGS+=(btrfs-progs snapper snap-pac) ;;
    ext4)  BASE_PKGS+=(e2fsprogs) ;;
    xfs)   BASE_PKGS+=(xfsprogs) ;;
    *)     die "unsupported ROOT_FS=${ROOT_FS:-} (use btrfs|ext4|xfs)" ;;
  esac
  if [[ -n $UCODE ]]; then
    BASE_PKGS+=("$UCODE")
  fi
  if yn_on "${INSTALL_BLUETOOTH:-N}"; then
    BASE_PKGS+=(bluez bluez-utils)
  fi
  if yn_on "${INSTALL_LINUX_HARDENED:-N}"; then
    BASE_PKGS+=(linux-hardened linux-hardened-headers)
  fi
  if yn_on "${INSTALL_LINUX_STABLE:-N}"; then
    BASE_PKGS+=(linux linux-headers)
  fi
  if yn_on "${INSTALL_LINUX_ZEN:-N}"; then
    BASE_PKGS+=(linux-zen linux-zen-headers)
  fi
  if yn_on "${INSTALL_PLYMOUTH:-N}"; then
    BASE_PKGS+=(plymouth)
  fi
}

# prefetch_pkgs CACHE PKG...: download every package (and every dependency)
# into the target's package cache before pacstrap. A download is safe to retry
# (resumes, never touches the new root), so flaky mirrors get several attempts
# here; pacstrap then installs from the cache. pacstrap itself must stay a
# single run: re-running it on a half-populated root hits "conflicting files".
# An empty temporary local db makes pacman fetch the full dependency closure
# (the live ISO's installed packages would otherwise be skipped).
prefetch_pkgs() {
  local cache=$1 tries=${PREFETCH_TRIES:-4} backoff=${PREFETCH_BACKOFF:-10}
  shift
  (
    db="$(mktemp -d)"
    trap 'rm -rf -- "$db"' EXIT
    # pacman downloads as the unprivileged DownloadUser (alpm) in a sandbox: the
    # db dir must be traversable (mktemp -d is 0700), or every sync fails with
    # "could not open file …/sync/download-*/core.db.part: Permission denied".
    chmod 0755 "$db"
    mkdir -p "$db/local" "$cache"
    local -a cache_args=(--cachedir "$cache")
    if [[ -n ${EXTRA_PACMAN_CACHEDIR:-} && -d $EXTRA_PACMAN_CACHEDIR ]]; then
      cache_args+=(--cachedir "$EXTRA_PACMAN_CACHEDIR")
    fi
    for ((try = 1; try <= tries; try++)); do
      if pacman -Syw --noconfirm --dbpath "$db" "${cache_args[@]}" -- "$@"; then
        exit 0
      fi
      if (( try < tries )); then
        echo "package download failed (attempt $try/$tries); retrying" >&2
        sleep $(( try * backoff ))
      else
        echo "package download failed (attempt $try/$tries); giving up" >&2
      fi
    done
    exit 1
  )
}

# Tune a pacman.conf in place (live ISO and target; shipped into the chroot via
# declare -f). $1 conf, $2 ParallelDownloads, $3 Y = enable [multilib].
#   * no XferCommand (it serializes downloads and ignores ParallelDownloads)
#   * DisableDownloadTimeout (slow mirrors stall instead of aborting)
#   * Color + ILoveCandy, VerbosePkgLists, CheckSpace
pacman_tune() {
  local conf=$1 par=${2:-10} multilib=${3:-N}
  [[ -f $conf ]] || return 1
  sed -i '/^XferCommand[[:space:]]*=/d' "$conf"
  if grep -qE '^#?ParallelDownloads' "$conf"; then
    sed -i -E "s/^#?ParallelDownloads.*/ParallelDownloads = ${par}/" "$conf"
  else
    sed -i "/^\\[options\\]/a ParallelDownloads = ${par}" "$conf"
  fi
  sed -i -E 's/^#(Color|VerbosePkgLists|CheckSpace)[[:space:]]*$/\1/' "$conf"
  grep -q '^Color' "$conf" || sed -i '/^\[options\]/a Color' "$conf"
  grep -q '^ILoveCandy' "$conf" || sed -i '/^Color/a ILoveCandy' "$conf"
  grep -q '^DisableDownloadTimeout' "$conf" \
    || sed -i '/^\[options\]/a DisableDownloadTimeout' "$conf"
  if [[ $multilib == Y ]]; then
    # Only [multilib] and its Include line — never [multilib-testing].
    sed -i '/^#\[multilib\]$/{s/^#//;n;s/^#Include/Include/}' "$conf"
  fi
  return 0
}
