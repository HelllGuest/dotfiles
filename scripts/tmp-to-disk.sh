#!/usr/bin/env bash
# tmp-to-disk.sh — move /tmp off tmpfs onto a dedicated btrfs @tmp subvolume.
#
# Why: systemd defaults /tmp to tmpfs capped at RAM/2 (~7.7G on this 16G box).
# Big builds/extracts fill it AND steal RAM. @tmp on disk (610G) can't realistically
# fill, uses nodatacow (no CoW churn/fragmentation on temp files), and is excluded
# from snapper snapshots (nested subvol, so @ snapshots don't capture it).
#
# Idempotent. Run with sudo, then reboot. Reversible: delete the /tmp line in
# /etc/fstab (timestamped backup saved) and reboot to return to tmpfs.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root: sudo $0"; exit 1; }

DEV=/dev/mapper/cryptroot
UUID=$(findmnt -no UUID /)
TOP=/mnt/btrfs-top
# nofail: a /tmp mount failure must not drop the boot to emergency — it falls back
# to the empty /tmp dir on @ instead. nodatacow disables compression by design.
OPTS="rw,noatime,nodatacow,nosuid,nodev,nofail,ssd,space_cache=v2,subvol=/@tmp"

echo ">> root btrfs UUID: $UUID"

# 1. backup fstab
cp -v /etc/fstab "/etc/fstab.bak-$(date +%F-%H%M%S)"

# 2. create @tmp subvolume if missing (mount the btrfs top-level to reach it)
mkdir -p "$TOP"
mountpoint -q "$TOP" && umount "$TOP" || true   # guard: clean up a prior interrupted run
mount -o subvolid=5 "$DEV" "$TOP"
if [[ ! -e "$TOP/@tmp" ]]; then
    btrfs subvolume create "$TOP/@tmp"
    chattr +C "$TOP/@tmp"      # nodatacow inheritance for files created inside
    echo ">> created @tmp"
else
    echo ">> @tmp already exists"
fi
chmod 1777 "$TOP/@tmp"         # sticky + world-writable, required for /tmp
ls -ld "$TOP/@tmp"; lsattr -d "$TOP/@tmp"
umount "$TOP"; rmdir "$TOP"

# 3. add fstab entry if not present
if grep -qE '^[^#]*[[:space:]]/tmp[[:space:]]+btrfs' /etc/fstab; then
    echo ">> fstab already has a /tmp btrfs entry — leaving as-is"
else
    printf '\n# /tmp on disk (btrfs @tmp, nodatacow, excluded from snapshots) — was tmpfs RAM/2\nUUID=%s\t/tmp\tbtrfs\t%s\t0 0\n' "$UUID" "$OPTS" >> /etc/fstab
    echo ">> added /tmp -> @tmp to /etc/fstab"
fi

# 4. validate fstab + regenerate mount units
systemctl daemon-reload
findmnt --verify --verbose || echo "WARN: review /etc/fstab before rebooting"

cat <<'EOF'

>> DONE. /tmp switches to disk on next boot (live tmpfs left alone to not break
   running apps). Then:

     sudo reboot
     findmnt /tmp            # expect: btrfs, subvol=/@tmp, ~610G (not tmpfs)
     mount | grep ' /tmp '   # expect: nodatacow,nosuid,nodev

>> Revert: delete the '/tmp ... @tmp' line in /etc/fstab (backup saved next to it),
   then reboot — tmpfs /tmp returns automatically.
EOF
