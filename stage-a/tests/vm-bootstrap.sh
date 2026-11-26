#!/usr/bin/env bash
# Runs inside the Arch ISO guest (root). Fetched via archiso script= URL.
# Host serves the t14s-arch-install tree at http://10.0.2.2:${HOST_PORT:-8000}/
set -euo pipefail

HOST="${T14S_VM_HOST:-10.0.2.2}"
PORT="${T14S_VM_PORT:-8000}"
BASE="http://${HOST}:${PORT}"
DISK="${T14S_VM_DISK:-/dev/vda}"
LOG=/tmp/t14s-vm-install.log
RESULT=/tmp/t14s-vm-result.txt

exec > >(tee -a "$LOG") 2>&1
echo "=== t14s VM bootstrap $(date -Is) ==="
echo "BASE=$BASE DISK=$DISK"

# Wait for DHCP / DNS
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 "$BASE/install.sh" >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS --max-time 10 "$BASE/install.sh" >/dev/null \
  || { echo "FAIL: cannot reach $BASE/install.sh"; echo FAIL >"$RESULT"; exit 1; }

# Answers + secrets (minimal preset; verify firewalld + ssh path)
cat >/tmp/t14s-answers.env <<EOF
DISK=$DISK
MODE=auto
ESP_MB=2048
HOSTNAME=t14s-vm
TIMEZONE=UTC
LOCALE=en_US.UTF-8
KEYMAP=us
USERNAME=t14svm
PRESET=minimal
DESKTOP=N
ENABLE_SSHD=Y
FW_SYNCTHING=N
FW_KDECONNECT=N
LUKS_WIPE=none
PACMAN_PARALLEL=5
BTRFS_COMPRESS=zstd3
ZRAM_SIZE=half
SKIP_THINKPAD_HW=Y
SKIP_REFLECTOR=Y
CLEAN_ESP_ARCH=Y
INSTALL_SELFTEST=Y
EOF
cat >/tmp/t14s-pass.env <<EOF
LUKS_PASS=${T14S_VM_LUKS_PASS:-vmtest-luks-pass-change-me}
USER_PASS=${T14S_VM_USER_PASS:-vmtest-user-pass-change-me}
ROOT_PASS=${T14S_VM_ROOT_PASS:-vmtest-root-pass-change-me}
EOF
# Full desktop rehearsal: T14S_VM_DESKTOP=Y (default minimal, no GNOME).
if [[ ${T14S_VM_DESKTOP:-N} == Y ]]; then
  sed -i 's/^DESKTOP=N$/DESKTOP=Y/' /tmp/t14s-answers.env
fi
chmod 600 /tmp/t14s-answers.env /tmp/t14s-pass.env

export T14S_BASE_URL="$BASE"
export T14S_UI=plain
export T14S_NONINTERACTIVE=1
export T14S_I_WILL_ERASE=1
export T14S_ANSWERS=/tmp/t14s-answers.env
export T14S_PASS_FILE=/tmp/t14s-pass.env
export T14S_ANSWERS_OUT=/tmp/t14s-answers.out

echo "=== starting installer ==="
# Optional host pacman cache (9p ro from vm-run.sh): speeds up prefetch + pacstrap.
# Mount outside /mnt so mounting the target root on /mnt never shadows it.
if [[ ${T14S_VM_PKGCACHE:-0} == 1 ]]; then
  mkdir -p /run/t14s-pkgcache-raw /run/t14s-pkgcache
  if mount -t 9p -o trans=virtio,version=9p2000.L,ro pkgcache /run/t14s-pkgcache-raw 2>/dev/null; then
    # Filter host-0600 files: QEMU 9p allows stat() but returns EACCES on open().
    _ok=()
    for _p in /run/t14s-pkgcache-raw/*; do
      [[ -f $_p ]] || continue
      if { : <"$_p"; } 2>/dev/null; then _ok+=("$_p"); fi
    done
    if (( ${#_ok[@]} )); then
      printf '%s\0' "${_ok[@]}" | xargs -0 -r ln -s -t /run/t14s-pkgcache
    fi
    for _p in /run/t14s-pkgcache/*.pkg.tar.*; do
      [[ -e $_p && $_p != *.sig ]] || continue
      if [[ -e "/run/t14s-pkgcache-raw/${_p##*/}.sig" && ! -e "${_p}.sig" ]]; then
        rm -f "$_p"
      fi
    done
    export EXTRA_PACMAN_CACHEDIR=/run/t14s-pkgcache
    # Keep writable target cache first so pacman writes missing packages there, then checks ro host cache.
    sed -i '/^\[options\]/a CacheDir = /mnt/var/cache/pacman/pkg/\nCacheDir = /run/t14s-pkgcache/' /etc/pacman.conf
    echo "=== mounted host pkgcache at /run/t14s-pkgcache (ro, ${#_ok[@]} readable files) ==="
  fi
fi
set +e
bash <(curl -fsSL "$BASE/install.sh")
rc=$?
set -e
echo "=== installer exit $rc ==="

# Quick post-chroot probes while still in ISO (target mounted? cleanup may umount)
if [[ -d /mnt/etc/firewalld ]]; then
  grep -H '^DefaultZone=' /mnt/etc/firewalld/firewalld.conf || true
  ls /mnt/etc/firewalld/zones 2>/dev/null | head || true
fi
if [[ -x /mnt/usr/bin/firewall-offline-cmd ]] || [[ -x /mnt/usr/bin/firewall-cmd ]]; then
  arch-chroot /mnt firewall-offline-cmd --list-all 2>/dev/null | head -40 || true
fi

if (( rc == 0 )); then
  echo PASS >"$RESULT"
  # Drop a marker on the ESP so host can inspect after reboot if needed
  if mountpoint -q /mnt/boot 2>/dev/null || mount /dev/disk/by-label/EFI /mnt/boot 2>/dev/null; then
    echo "t14s-vm PASS $(date -Is)" >/mnt/boot/t14s-vm-pass.txt 2>/dev/null || true
  fi
else
  echo FAIL >"$RESULT"
fi

# Print result on serial for the host harness
echo "T14S_VM_RESULT=$(cat "$RESULT")"
exit "$rc"
