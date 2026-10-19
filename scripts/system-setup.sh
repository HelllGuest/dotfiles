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
# * X1_ONLY files (cmdline, i915, X1 sleep/logind, fingerprint port rule) are
#   installed on ThinkPad X1 hardware only; other profiles (e.g. thinkpad-p15)
#   keep and edit their own. Elsewhere their old stow symlinks are removed, except
#   cmdline, which is materialized as a real file (UKIs need one to boot).
# * /etc/kernel/cmdline: rd.luks.name= is rewritten to the booted LUKS UUID;
#   skipped if that UUID cannot be confirmed. UKIs are rebuilt when cmdline or
#   modprobe.d changes (sbctl's mkinitcpio hook re-signs them).
# * Location files are owned by location-setup.sh / vpn-location-sync and skipped.
#
# Re-run after editing anything under stow/system/.
#
# Tests: SYSTEM_ROOT=<dir> installs under <dir> without sudo, ownership changes
# or reloads; PROC_CMDLINE overrides /proc/cmdline; SYSTEM_IS_X1=1|0 overrides
# the DMI hardware check. See tests/system-setup.test.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_ROOT="$REPO_ROOT/stow/system"
ROOT="${SYSTEM_ROOT:-}"
PROC_CMDLINE="${PROC_CMDLINE:-/proc/cmdline}"
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
)

# Tuned for the ThinkPad X1 Yoga Gen 5 (Comet Lake iGPU, its USB port layout).
X1_ONLY=(
    etc/kernel/cmdline
    etc/modprobe.d/i915.conf
    etc/systemd/logind.conf.d/thinkpad-x1.conf
    etc/systemd/sleep.conf.d/thinkpad-x1.conf
    etc/udev/rules.d/72-fingerprint-disable.rules
)

# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"
# A missing helper would read as "not X1" inside `if !` and silently skip files.
declare -F is_thinkpad_x1 >/dev/null || { echo "lib/dmi.sh: is_thinkpad_x1 missing" >&2; exit 1; }

if [ ! -d "$SRC_ROOT" ]; then
    echo "Missing system source: $SRC_ROOT" >&2
    exit 1
fi

is_x1_host() {
    case "${SYSTEM_IS_X1:-}" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    is_thinkpad_x1
}

# LUKS UUID that unlocked the running root, confirmed to exist as a block device.
booted_luks_uuid() {
    local uuid
    uuid="$(grep -oE 'rd\.luks\.name=[0-9a-fA-F-]{36}=' "$PROC_CMDLINE" | head -1 | cut -d= -f2 || true)"
    [ -n "$uuid" ] && [ -e "$ROOT/dev/disk/by-uuid/$uuid" ] && printf '%s' "$uuid"
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

# Non-X1 host: drop X1-only stow symlinks; keep a stowed cmdline as a real copy.
retire_x1_file() {
    local rel="$1" dest="$ROOT/$1" target
    if [ "$rel" = "etc/kernel/cmdline" ]; then
        if [ -L "$dest" ] && [[ "$(readlink "$dest")" == */stow/system/* ]]; then
            target="$(readlink -f "$dest")"
            if [ -f "$target" ]; then
                cp "$target" "$tmp"
                "${SUDO[@]}" rm -f "$dest"
                "${SUDO[@]}" install -m 0644 "${OWNER[@]}" "$tmp" "$dest"
                echo "Materialized stow symlink /$rel as a real file (non-X1: content kept)."
            else
                echo "WARN: /$rel is a dangling stow symlink; fix before rebuilding UKIs." >&2
            fi
        fi
        return
    fi
    unlink_stowed "$rel"
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

changed=()
while IFS= read -r -d '' src; do
    rel="${src#"$SRC_ROOT"/}"
    dest="$ROOT/$rel"
    if [[ " ${LOCATION_OWNED[*]} " == *" $rel "* ]]; then
        continue
    fi

    if [[ " ${X1_ONLY[*]} " == *" $rel "* ]] && ! is_x1_host; then
        echo "Skipping /$rel: ThinkPad X1 only."
        retire_x1_file "$rel"
        continue
    fi

    cp "$src" "$tmp"
    if [ "$rel" = "etc/kernel/cmdline" ]; then
        uuid="$(booted_luks_uuid || true)"
        if [ -z "$uuid" ]; then
            echo "Skipping /$rel: booted LUKS UUID not found in $PROC_CMDLINE (never install a wrong rd.luks.name)." >&2
            continue
        fi
        sed -i -E "s/rd\.luks\.name=[^= ]+=/rd.luks.name=${uuid}=/" "$tmp"
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
if [[ "$changed_list" == *" etc/kernel/cmdline "* || "$changed_list" == *" etc/modprobe.d/"* ]]; then
    echo "Rebuilding UKIs (cmdline / modprobe.d changed)..."
    sudo mkinitcpio -P
fi
echo "Reboot to apply kernel cmdline, sleep and logind changes."
