#!/usr/bin/env bash
# Runs inside the installed guest as the Stage A user (t14svm).
# Expects DOTFILES_SRC (9p or extracted tree) and DOTFILES_USER_PASS for sudo -S.
set -euo pipefail

exec > >(tee -a /tmp/dotfiles-stageb.log) 2>&1
echo "=== dotfiles Stage B $(date -Is) ==="

PASS="${DOTFILES_USER_PASS:?set DOTFILES_USER_PASS}"
SRC="${DOTFILES_SRC:-/mnt/dotfiles}"
DEST="${HOME}/dotfiles"

sudo_cmd() { printf '%s\n' "$PASS" | sudo -S -p '' "$@"; }

# Mount 9p share if present and not already mounted
if [[ ! -f $SRC/install.sh ]]; then
  sudo_cmd mkdir -p /mnt/dotfiles
  if ! mountpoint -q /mnt/dotfiles; then
    sudo_cmd mount -t 9p -o trans=virtio,version=9p2000.L dotfiles /mnt/dotfiles \
      || sudo_cmd mount -t 9p -o trans=virtio dotfiles /mnt/dotfiles
  fi
  SRC=/mnt/dotfiles
fi
[[ -f $SRC/install.sh ]] || { echo "FAIL: no install.sh at $SRC"; echo DOTFILES_STAGEB_RESULT=FAIL; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"
# Prefer rsync; fall back to cp
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude '.git/objects' "$SRC"/ "$DEST"/
else
  cp -a "$SRC"/. "$DEST"/
fi
cd "$DEST"
echo "→ tree ready at $DEST ($(du -sh . | awk '{print $1}'))"

# VM-only: temporary NOPASSWD so long install.sh / zone scripts never block.
SUDOERS_DROP=/etc/sudoers.d/t14s-vm-stageb
GUEST_NAME="$(id -un)"
stageb_sudoers_rm() {
  sudo sed -i '\|^CacheDir = /run/stageb-pkgcache/$|d' /etc/pacman.conf 2>/dev/null || true
  sudo rm -rf /run/stageb-pkgcache 2>/dev/null || true
  sudo umount /run/stageb-pkgcache-raw 2>/dev/null || true
  sudo rmdir /run/stageb-pkgcache-raw 2>/dev/null || true
  sudo rm -f "$SUDOERS_DROP" 2>/dev/null || true
}
# Drop leftovers from a prior killed run before installing a fresh one.
printf '%s\n' "$PASS" | sudo -S -p '' rm -f "$SUDOERS_DROP" 2>/dev/null || true
printf '%s\n' "$PASS" | sudo -S -p '' bash -c \
  "printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\nDefaults:%s verifypw = any\n' '$GUEST_NAME' '$GUEST_NAME' >'$SUDOERS_DROP' && chmod 440 '$SUDOERS_DROP'"
trap 'stageb_sudoers_rm' EXIT
sudo -n true || { echo "FAIL: sudo -n still blocked"; echo DOTFILES_STAGEB_RESULT=FAIL; exit 1; }

# Optional host pacman cache (9p ro from vm-stageb-run.sh): speeds up pacman -Syu.
if [[ ${STAGEB_VM_PKGCACHE:-0} == 1 ]]; then
  sudo mkdir -p /run/stageb-pkgcache-raw /run/stageb-pkgcache
  if sudo mount -t 9p -o trans=virtio,version=9p2000.L,ro pkgcache /run/stageb-pkgcache-raw 2>/dev/null; then
    # Filter host-0600 files: QEMU 9p allows stat() but returns EACCES on open().
    sudo bash -euo pipefail -c '
      ok=()
      for p in /run/stageb-pkgcache-raw/*; do
        [[ -f $p ]] || continue
        if { : <"$p"; } 2>/dev/null; then ok+=("$p"); fi
      done
      if (( ${#ok[@]} )); then
        printf "%s\0" "${ok[@]}" | xargs -0 -r ln -s -t /run/stageb-pkgcache
      fi
      for p in /run/stageb-pkgcache/*.pkg.tar.*; do
        [[ -e $p && $p != *.sig ]] || continue
        if [[ -e "/run/stageb-pkgcache-raw/${p##*/}.sig" && ! -e "${p}.sig" ]]; then
          rm -f "$p"
        fi
      done
      echo "=== mounted host pkgcache at /run/stageb-pkgcache (ro, ${#ok[@]} readable files) ==="
    '
    sudo sed -i '\|^CacheDir = /run/stageb-pkgcache/$|d' /etc/pacman.conf
    sudo sed -i '/^\[options\]/a CacheDir = /var/cache/pacman/pkg/\nCacheDir = /run/stageb-pkgcache/' /etc/pacman.conf
  fi
fi

echo "=== configure.sh (defaults: SETUP_FIREWALLD) ==="
# plain UI: empty line keeps checklist defaults (SETUP_FIREWALLD on)
set +e
# Force plain UI: dialog/whiptail hang with no TTY on serial.
printf '\n' | CONFIGURE_UI=plain bash provision/scripts/configure.sh
cfg_rc=$?
set -e
echo "configure.sh exit=$cfg_rc"
(( cfg_rc == 0 )) || { echo DOTFILES_STAGEB_RESULT=FAIL; exit "$cfg_rc"; }

echo "=== firewalld post-check ==="
firewall-cmd --get-default-zone || true
firewall-cmd --get-active-zones || true
systemctl is-active firewalld || true

echo "=== install.sh (SKIP_CONFIGURE; soft GNOME) ==="
# Minimal Stage A had DESKTOP=N — skip session-heavy fails where possible.
export SKIP_CONFIGURE=1
export SKIP_FOXCAGE=1
export SKIP_OLLAMA=1
# theme-setup.sh needs a GNOME session bus (none on a headless guest).
export SKIP_THEME=1
# Headless: no TTY prompts (git identity/hooks/GPG).
export GIT_SETUP_NONINTERACTIVE=1
# Throwaway identity so the guest exercises the identity path (git-setup.sh has no defaults).
export GIT_USER_NAME="${GIT_USER_NAME:-vmtest}" GIT_USER_EMAIL="${GIT_USER_EMAIL:-vmtest@example.com}"
INSTALL_LOG=/tmp/dotfiles-stageb-install.log
set +e
# No GNOME login: give install.sh a private session bus so dconf/gsettings
# writes (session setup, GNOME Console, privacy keys) land in the user db.
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]] && command -v dbus-run-session >/dev/null 2>&1; then
  dbus-run-session -- bash ./install.sh 2>&1 | tee "$INSTALL_LOG"
else
  bash ./install.sh 2>&1 | tee "$INSTALL_LOG"
fi
inst_rc=${PIPESTATUS[0]}
set -e
echo "install.sh exit=$inst_rc"
echo "DOTFILES_STAGEB_CONFIGURE=$cfg_rc"
echo "DOTFILES_STAGEB_INSTALL=$inst_rc"

# Remove NOPASSWD before RESULT so a later poweroff cannot leave it behind.
stageb_sudoers_rm
trap - EXIT

# PASS          = configure + install both OK.
# PASS_HEADLESS = install.sh failed ONLY on health checks that cannot pass in a
#                 headless VM (no GNOME session, no browser/zsh launch, no BT
#                 adapter or PipeWire audio session, no Proton API from CI nets).
#                 Any other failure is FAIL.
HEADLESS_OK='GNOME extensions enabled|Zen user\.js missing|zinit not bootstrapped|Proton API|^✗ t14s-selftest:( FAIL (bluetooth|pipewire))+ *$'
if (( cfg_rc == 0 && inst_rc == 0 )); then
  echo DOTFILES_STAGEB_RESULT=PASS
  exit 0
fi
if (( cfg_rc == 0 )); then
  sed -i 's/\x1b\[[0-9;]*m//g; s/\r$//' "$INSTALL_LOG"   # colours / CR break ^✗ matching
  reasons="$(sed -n '/^Installation finished with failures:/,$p' "$INSTALL_LOG" | grep '^  - ' || true)"
  other_reasons="$(grep -v 'Health check reported failures' <<<"$reasons" || true)"
  unexpected="$(grep '^✗' "$INSTALL_LOG" | grep -vE "$HEADLESS_OK" || true)"
  if [[ -n $reasons && -z $other_reasons && -z $unexpected ]]; then
    echo DOTFILES_STAGEB_RESULT=PASS_HEADLESS
    echo "NOTE: install.sh rc=$inst_rc only from headless-expected checks:"
    grep '^✗' "$INSTALL_LOG" | sed 's/^/  /'
    exit 0
  fi
  echo "Unexpected install.sh failures:"
  [[ -n $other_reasons ]] && printf '%s\n' "$other_reasons"
  [[ -n $unexpected ]] && printf '  %s\n' "$unexpected"
fi
echo DOTFILES_STAGEB_RESULT=FAIL
exit 1
