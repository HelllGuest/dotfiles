# 21-install-filesystems.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# LUKS2 format, root filesystem (btrfs/ext4/xfs), mounts.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── 5. encrypt (optional) + filesystems ─────────────────────
wipefs -a "$ROOT_PART" >/dev/null 2>&1 || true   # clear stale signatures (dirty/reused disk)
if yn_on "${ENCRYPT_ROOT:-Y}"; then
  step "LUKS2 format (argon2id) on $ROOT_PART"
  printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --type luks2 --pbkdf argon2id --batch-mode "$ROOT_PART" -
  printf '%s' "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot -
  unset -v LUKS_PASS
  LUKS_UUID="$(cryptsetup luksUUID "$ROOT_PART")"   # LUKS header UUID (for rd.luks.name)
  [[ -n $LUKS_UUID ]] || die "could not read LUKS UUID from $ROOT_PART"
  ROOT_DEV=/dev/mapper/cryptroot
  ok "LUKS open as /dev/mapper/cryptroot (LUKS UUID=$LUKS_UUID)"
  apply_luks_wipe
else
  unset -v LUKS_PASS
  LUKS_UUID=""
  ROOT_DEV="$ROOT_PART"
  ok "unencrypted root on $ROOT_DEV (ENCRYPT_ROOT=N)"
fi

# Format root filesystem + mount + ESP.
do_filesystems_and_mount
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV" 2>/dev/null || true)"
if ! yn_on "${ENCRYPT_ROOT:-Y}"; then
  [[ -n $ROOT_UUID ]] || die "could not read filesystem UUID from $ROOT_DEV"
fi
