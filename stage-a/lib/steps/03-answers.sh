# 03-answers.sh — part of HelllGuest/t14s-arch-install
# shellcheck shell=bash
# Answers file (T14S_ANSWERS): load known keys before hardware detection; saved again before install.
# Sourced by install.sh at top level, in order: shares its globals, set -e
# and ERR/EXIT traps exactly as if the code were inline.

# ── answers helpers (T14S_ANSWERS=file; export at end) ───────
# Known keys only — never eval the answers file.
ANSWERS_KEYS=(
  PRESET DESKTOP INSTALL_NERD_FONTS INSTALL_FLATPAK_APPS INSTALL_BLUETOOTH ENROLL_SB ENABLE_SSHD INSTALL_CUPS
  SKIP_REFLECTOR INSTALL_TLP INSTALL_CLI INSTALL_PODMAN INSTALL_DOCKER
  INSTALL_VIRT INSTALL_AVAHI INSTALL_WIREGUARD INSTALL_TAILSCALE
  INSTALL_STARSHIP INSTALL_CHROME_HINT INSTALL_FAIL2BAN INSTALL_THINKFAN
  INSTALL_SNAPPER_HOME INSTALL_LINUX_HARDENED INSTALL_LINUX_STABLE INSTALL_LINUX_ZEN INSTALL_PLYMOUTH INSTALL_SELFTEST
  INSTALL_MULTILIB INSTALL_YAY INSTALL_TUNED INSTALL_DEVTOOLS INSTALL_BTRFS_ASSISTANT
  CLEAN_ESP_ARCH HW_PROFILE INSTALL_OLLAMA
  FW_SYNCTHING FW_KDECONNECT POST_HOOK_URL
  PACMAN_PARALLEL LUKS_WIPE HOSTNAME TIMEZONE LOCALE KEYMAP USERNAME
  MODE ESP_MB FORMAT_EFI DISK EFI_PART ROOT_PART
  ENCRYPT_ROOT ROOT_FS BTRFS_COMPRESS ZRAM_SIZE REFLECTOR_COUNTRY SKIP_THINKPAD_HW
  INSTALL_VM_GUEST VM_FAST_PKG VM_SERIAL_CONSOLE SSH_PUBKEY
  EXTRA_PKGS_LIST
)

if [[ -n $ANSWERS_IN ]]; then
  if answers_load "$ANSWERS_IN"; then
    ok "loaded answers from $ANSWERS_IN"
  else
    die "T14S_ANSWERS not readable: $ANSWERS_IN"
  fi
fi
if [[ -n $PASS_FILE ]]; then
  if secrets_load "$PASS_FILE"; then
    SECRETS_FROM_FILE=1
    ok "loaded secrets from $PASS_FILE (passwords not saved to answers)"
  else
    die "T14S_PASS_FILE not readable: $PASS_FILE"
  fi
fi
if (( NONINTERACTIVE )); then
  [[ -n $PASS_FILE && $SECRETS_FROM_FILE == 1 ]] \
    || die "NONINTERACTIVE requires T14S_PASS_FILE (mode 0600; no env passwords)"
  [[ -n ${USER_PASS:-} && -n ${ROOT_PASS:-} ]] \
    || die "T14S_PASS_FILE must set USER_PASS and ROOT_PASS (plus LUKS_PASS when ENCRYPT_ROOT=Y)"
fi
