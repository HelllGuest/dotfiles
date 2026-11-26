# 20-install-disk.sh — part of HelllGuest/dotfiles (stage-a)
# shellcheck shell=bash
# Step 11/11 begins: log to file, release leftovers, write the partition table.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

start_log
ui_step 11 Install

# Release leftover state from a previous interrupted run on the CONFIRMED target
# (an open cryptroot / mounted /mnt keeps the disk busy → sgdisk/mkfs fail).
release_target_devices

# ── 4b. write the partition table (AUTO only) ───────────────
if [[ $MODE == auto ]]; then
  if yn_on "${ENCRYPT_ROOT:-Y}"; then
    step "partitioning $DISK (GPT: ${ESP_MB}MB ESP + LUKS)"
    sgdisk --zap-all "$DISK" >/dev/null
    sgdisk -n1:0:+"${ESP_MB}"M -t1:ef00 -c1:EFI "$DISK" >/dev/null
    sgdisk -n2:0:0     -t2:8309 -c2:cryptroot "$DISK" >/dev/null
  else
    step "partitioning $DISK (GPT: ${ESP_MB}MB ESP + root)"
    sgdisk --zap-all "$DISK" >/dev/null
    sgdisk -n1:0:+"${ESP_MB}"M -t1:ef00 -c1:EFI "$DISK" >/dev/null
    sgdisk -n2:0:0     -t2:8304 -c2:archroot "$DISK" >/dev/null
  fi
  partprobe "$DISK"; udevadm settle 2>/dev/null || sleep 2
fi
