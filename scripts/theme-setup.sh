#!/usr/bin/env bash
# theme-setup.sh — Aura Glass: frosted-glass GNOME Shell + GTK4/libadwaita + GTK3
# theme with real blur (its own patched Blur My Shell), Colloid icons, the Full
# extension pack and a blurred GDM login screen.
#   https://github.com/DevWebeloper/aura-glass (MIT), pinned to one commit.
#
# Aura Glass's own installer does the work; this script fetches it at the pin,
# checks the commit, removes the previous Orchis/Tela/Bibata setup once, and
# runs it non-interactively. Aura Glass owns the theme, icon, cursor,
# user-theme and blur-my-shell keys: gnome/dconf/*.conf do not set them and
# scripts/backup-gsettings.sh drops them from snapshots.
#   theme-setup.sh          install / re-apply at the pin. The first install
#                           picks the look (flags below); later runs pass only
#                           -y, so choices made in the Aura Glass settings app
#                           (accent, extension pack, icons…) are kept.
#   theme-setup.sh --check  exit 0 verified, 1 broken (reason on stdout),
#                           2 not set up (check.sh)
#   SKIP_AURA_GDM=1         leave the login screen stock (--no-gdm; Aura
#                           Glass remembers it: turn GDM back on in its app)
# Upgrade: bump AURA_GLASS_VERSION + AURA_GLASS_COMMIT together (the tag's
# commit: git ls-remote <repo> 'refs/tags/<tag>^{}'). The settings app's own
# Install button moves the checkout off the pin; check.sh then fails and the
# next run puts it back.
set -euo pipefail

AURA_GLASS_REPO="https://github.com/DevWebeloper/aura-glass.git"
AURA_GLASS_VERSION="v0.4.4"
AURA_GLASS_COMMIT="ccd94dff4a2aedede145f6a6eb04ea1177919bd3"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SRC="$CACHE_HOME/dotfiles/aura-glass"
# Old setup (Orchis greeter): root-owned copy of the removed gdm-shell-theme.sh
# and its pacman hook. Overridable for tests only.
OLD_GDM_BIN="${THEME_OLD_GDM_BIN:-/usr/local/bin/gdm-shell-theme}"
OLD_GDM_HOOK="${THEME_OLD_GDM_HOOK:-/etc/pacman.d/hooks/95-gdm-shell-theme.hook}"

# First install: accent matches gnome/dconf/user.conf; no daily GitHub release
# check (the pin is the version); --full = all 7 optional extensions + icons +
# pointer + OSD. Aura Glass remembers these in ~/.config/aura-glass.
if [[ -d $CONFIG_HOME/aura-glass ]]; then
    AURA_FLAGS=(-y)
    [[ ${SKIP_AURA_GDM:-0} != 1 ]] || AURA_FLAGS+=(--no-gdm)
else
    AURA_FLAGS=(--full --accent blue --no-update-check -y)
    if [[ ${SKIP_AURA_GDM:-0} == 1 ]]; then AURA_FLAGS+=(--no-gdm); else AURA_FLAGS+=(--gdm); fi
fi

die() { echo "✗ $*" >&2; exit 1; }

at_pin() {
    [[ -f $SRC/install.sh ]] \
        && [[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" == "$AURA_GLASS_COMMIT" ]]
}

# --check: 0 = Aura Glass at the pin passes its own --verify, 1 = broken, 2 = not set up.
if [[ ${1:-} == --check ]]; then
    if [[ -e $OLD_GDM_HOOK || -e $OLD_GDM_BIN ]]; then
        echo "old Orchis GDM hook still installed ($OLD_GDM_HOOK)"
        exit 1
    fi
    [[ -d $CONFIG_HOME/aura-glass ]] || exit 2
    if ! at_pin; then
        echo "source checkout missing or not at $AURA_GLASS_VERSION ($SRC)"
        exit 1
    fi
    if ! (cd "$SRC" && bash ./install.sh --verify) >/dev/null 2>&1; then
        echo "Aura Glass --verify failed (bash $SRC/install.sh --verify)"
        exit 1
    fi
    exit 0
fi

# Aura Glass writes gsettings: it needs the session bus of a GNOME login.
# Checked before anything is removed, so a run from SSH or a TTY changes nothing.
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]; then
    die "no session D-Bus: Aura Glass cannot write the theme keys — re-run from your GNOME login"
fi

# 1. Source at the pinned commit (GitHub serves a full SHA directly).
echo "→ Aura Glass $AURA_GLASS_VERSION source (${AURA_GLASS_COMMIT:0:12})..."
mkdir -p "$SRC"
[[ -d $SRC/.git ]] || git -C "$SRC" init -q
git -C "$SRC" remote remove origin 2>/dev/null || true
git -C "$SRC" remote add origin "$AURA_GLASS_REPO"
git -C "$SRC" fetch -q --depth 1 origin "$AURA_GLASS_COMMIT" \
    || die "could not fetch aura-glass $AURA_GLASS_COMMIT"
git -C "$SRC" checkout -q --force --detach FETCH_HEAD
at_pin || die "aura-glass checkout is not at $AURA_GLASS_COMMIT — refusing to run it"

# 2. Remove the previous theme setup (idempotent; nothing left on a fresh host).
if [[ -e $OLD_GDM_BIN ]]; then
    echo "→ Restoring the stock GDM stylesheet (old Orchis greeter + pacman hook)..."
    sudo "$OLD_GDM_BIN" revert
fi
unit_dir="$CONFIG_HOME/systemd/user"
if [[ -e $unit_dir/theme-sync.service || -L $unit_dir/default.target.wants/theme-sync.service ]]; then
    echo "→ Removing theme-sync.service (Orchis user copy refresher)..."
    rm -f "$unit_dir/theme-sync.service" "$unit_dir/default.target.wants/theme-sync.service"
    systemctl --user daemon-reload 2>/dev/null || true
fi
rm -f "$DATA_HOME/dotfiles/theme-setup.sh"
rmdir "$DATA_HOME/dotfiles" 2>/dev/null || true
rm -rf "$DATA_HOME/themes/Orchis-Dark"
# Old libadwaita links into the Orchis copy; a real file of the user's stays
# (Aura Glass backs it up before writing its own).
for f in gtk.css gtk-dark.css assets; do
    dst="$CONFIG_HOME/gtk-4.0/$f"
    if [[ -L $dst && "$(readlink "$dst")" == */themes/Orchis-Dark/* ]]; then
        rm -f "$dst"
    fi
done
for p in orchis-theme tela-icon-theme bibata-cursor-theme-bin; do
    if pacman -Q "$p" >/dev/null 2>&1; then
        echo "○ old theme package still installed: $p (sudo pacman -Rns $p)"
    fi
done

# 3. Install, or re-apply with the remembered choices.
echo "→ Running Aura Glass installer: ${AURA_FLAGS[*]}"
(cd "$SRC" && bash ./install.sh "${AURA_FLAGS[@]}")

echo "✓ theme: Aura Glass $AURA_GLASS_VERSION (log out and back in: extensions load at login)"
