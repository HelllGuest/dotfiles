#!/usr/bin/env bash
# system-setup.sh — install stow/system/ into / as root-owned regular files.
#
# Not stowed: /etc symlinks into $HOME dangle at early boot (ufw.service starts
# before /home is mounted, finds no before.rules, and leaves a half-loaded
# firewall that drops reply traffic) and let the repo owner edit root config.
# Same reason as zram-setup.sh and gdm-setup.sh.
#
# * Removes leftover stow symlinks (files or folded directories) first.
# * Backs up a differing existing file to /var/backups/dotfiles-system/<stamp>/.
# * Parent dirs of managed files are made root-owned and world-readable
#   (a 700 dir from a umask-077 copy hides e.g. environment.d from the session).
# * Kernel cmdline is owned by the installer / machine profile (P15 / T14s), not
#   this tree. UKIs are rebuilt when a managed modprobe.d file changes.
# * On AMD Radeon hosts, 99-wayland.conf gets LIBVA_DRIVER_NAME=radeonsi.
# * Location files are owned by location-setup.sh / vpn-location-sync and skipped.
#
# Re-run after editing anything under stow/system/.
#
# Tests: SYSTEM_ROOT=<dir> installs under <dir> without sudo, ownership changes
# or reloads; SYSTEM_IS_AMDGPU=1|0 overrides the AMD GPU check.
# See tests/system-setup.test.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="$REPO_ROOT/stow/system"
ROOT="${SYSTEM_ROOT:-}"
BACKUP_DIR="$ROOT/var/backups/dotfiles-system/$(date +%Y%m%d%H%M%S)"

if [ -n "$ROOT" ]; then
    SUDO=()
    OWNER=()
else
    SUDO=(sudo)
    OWNER=(-o root -g root)
fi

# Installed by scripts/location-setup.sh; /etc/geolocation is rewritten at runtime.
LOCATION_OWNED=(
    etc/geolocation
    etc/geoclue/conf.d/99-static-dubai.conf
    etc/NetworkManager/dispatcher.d/99-vpn-location
    etc/polkit-1/rules.d/50-vpn-location-sync.rules
    etc/polkit-1/rules.d/50-kali-lan-host-prep.rules
)

# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"
declare -F is_thinkpad_t14s >/dev/null || { echo "lib/dmi.sh: is_thinkpad_t14s missing" >&2; exit 1; }

if [ ! -d "$SRC_ROOT" ]; then
    echo "Missing system source: $SRC_ROOT" >&2
    exit 1
fi

is_amdgpu_host() {
    case "${SYSTEM_IS_AMDGPU:-}" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    is_thinkpad_t14s || [ -d /sys/module/amdgpu ]
}

# Remove stow symlinks on the path to $1 (the file itself or a folded parent dir).
unlink_stowed() {
    local rel="$1" path="$ROOT" part
    local IFS=/
    for part in $rel; do
        path="$path/$part"
        if [ -L "$path" ] && [[ "$(readlink "$path")" == */stow/system/* ]]; then
            echo "Removing stow symlink $path"
            "${SUDO[@]}" rm -f "$path"
            return
        fi
    done
}

# Make every parent dir of $1 root-owned and traversable; never loosen go-w.
fix_parents() {
    local dir
    dir="$(dirname "$1")"
    while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
        [ -z "$ROOT" ] && "${SUDO[@]}" chown root:root "$ROOT/$dir"
        "${SUDO[@]}" chmod u+rwx,go+rx,go-w "$ROOT/$dir"
        dir="$(dirname "$dir")"
    done
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Renamed drop-ins: remove the old path when it is ours (stow symlink, or a copy
# carrying both our C and Rust tuning lines), or both files apply.
# 99-x86-64-v3.conf sorted before pacman's rust.conf, which then reset RUSTFLAGS.
RETIRED=(
    etc/makepkg.conf.d/99-x86-64-v3.conf
)
for rel in "${RETIRED[@]}"; do
    old="$ROOT/$rel"
    if [ -L "$old" ] || { [ -f "$old" ] && grep -qF -- '-march=x86-64-v3' "$old" \
        && grep -qF -- '-C target-cpu=x86-64-v3' "$old"; }; then
        echo "Removing retired /$rel"
        "${SUDO[@]}" rm -f "$old"
    fi
done

changed=()
while IFS= read -r -d '' src; do
    rel="${src#"$SRC_ROOT"/}"
    dest="$ROOT/$rel"
    if [[ " ${LOCATION_OWNED[*]} " == *" $rel "* ]]; then
        continue
    fi

    cp "$src" "$tmp"
    if [ "$rel" = "etc/environment.d/99-wayland.conf" ] && is_amdgpu_host; then
        sed -i -e 's/^# Wayland + VA-API defaults.*/# Wayland + VA-API defaults for GNOME Shell 51 on AMD Radeon (radeonsi)/' \
               -e 's/^LIBVA_DRIVER_NAME=.*/LIBVA_DRIVER_NAME=radeonsi/' "$tmp"
    fi

    mode=0644
    [ -x "$src" ] && mode=0755

    unlink_stowed "$rel"
    if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$tmp" "$dest"; then
        [ -z "$ROOT" ] && "${SUDO[@]}" chown root:root "$dest"
        "${SUDO[@]}" chmod "$mode" "$dest"
        fix_parents "$rel"
        continue
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        "${SUDO[@]}" install -d -m 0700 "$BACKUP_DIR/$(dirname "$rel")"
        "${SUDO[@]}" cp -P "$dest" "$BACKUP_DIR/$rel"
        echo "Backed up /$rel -> $BACKUP_DIR/$rel"
    fi
    "${SUDO[@]}" install -D -m "$mode" "${OWNER[@]}" "$tmp" "$dest"
    fix_parents "$rel"
    echo "Installed /$rel"
    changed+=("$rel")
done < <(find "$SRC_ROOT" -type f -print0 | sort -z)

if [ ${#changed[@]} -eq 0 ]; then
    echo "System files already match stow/system/."
    exit 0
fi
[ -n "$ROOT" ] && exit 0

sudo systemctl daemon-reload || true

changed_list=" ${changed[*]} "
if [[ "$changed_list" == *" etc/udev/rules.d/"* ]]; then
    sudo udevadm control --reload || true
fi
# ufw status, not systemctl: after a failed boot-time start (dangling stowed
# before.rules) the unit is 'failed' but half-loaded rules are still live.
if [[ "$changed_list" == *" etc/ufw/before.rules "* ]] && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
    sudo ufw reload || echo "ufw reload failed — check: sudo ufw status verbose" >&2
fi
if [[ "$changed_list" == *" etc/modprobe.d/"* ]]; then
    echo "Rebuilding UKIs (modprobe.d changed)..."
    sudo mkinitcpio -P
fi
if [[ "$changed_list" == *" etc/systemd/system/virbr0-up.service "* ]]; then
    echo "Enabling virbr0-up.service (libvirt NAT bridge)..."
    sudo systemctl enable --now virbr0-up.service \
      || echo "WARN: virbr0-up enable/start failed (libvirtd may be inactive)." >&2
fi
echo "Reboot to apply sleep and logind changes."
