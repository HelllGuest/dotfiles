#!/usr/bin/env bash
# theme-setup.sh — GNOME default (Adwaita) desktop.
# Keeps a one-shot Orchis greeter scrub (old gdm-shell-theme hook / theme-sync /
# Orchis-Dark copy). No other third-party theme purge. --check validates Adwaita
# keys + absence of the Orchis hook only. Leaves other Shell extensions alone.
#
#   theme-setup.sh          reset theme keys; wipe Orchis leftovers
#   theme-setup.sh --check  exit 0 stock ok, 1 broken (reason on stdout),
#                           2 defaults not applied yet (check.sh)
# Opt out of install.sh: SKIP_THEME=1
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# Old setup (Orchis greeter): root-owned copy of the removed gdm-shell-theme.sh
# and its pacman hook. Overridable for tests only.
OLD_GDM_BIN="${THEME_OLD_GDM_BIN:-/usr/local/bin/gdm-shell-theme}"
OLD_GDM_HOOK="${THEME_OLD_GDM_HOOK:-/etc/pacman.d/hooks/95-gdm-shell-theme.hook}"

die() { echo "✗ $*" >&2; exit 1; }

gset_get() {
    gsettings get "$@" 2>/dev/null | tr -d "'"
}

# --check: 0 = GNOME defaults, 1 broken (Orchis hook), 2 not applied.
if [[ ${1:-} == --check ]]; then
    if [[ -e $OLD_GDM_HOOK || -e $OLD_GDM_BIN ]]; then
        echo "old Orchis GDM hook still installed ($OLD_GDM_HOOK)"
        exit 1
    fi
    gtk="$(gset_get org.gnome.desktop.interface gtk-theme || true)"
    icon="$(gset_get org.gnome.desktop.interface icon-theme || true)"
    cursor="$(gset_get org.gnome.desktop.interface cursor-theme || true)"
    case $gtk in
        Adwaita|Adwaita-dark) ;;
        '')
            # Headless / no session bus: not broken, just not applied yet.
            echo "could not read gtk-theme (no session gsettings?)"
            exit 2
            ;;
        *)
            echo "gtk-theme is '$gtk' (want Adwaita)"
            exit 2
            ;;
    esac
    [[ $icon == Adwaita ]] || { echo "icon-theme is '$icon' (want Adwaita)"; exit 2; }
    [[ $cursor == Adwaita ]] || { echo "cursor-theme is '$cursor' (want Adwaita)"; exit 2; }
    if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell.extensions.user-theme; then
        ut="$(gset_get org.gnome.shell.extensions.user-theme name || true)"
        [[ -z $ut ]] || { echo "user-theme name is '$ut' (want empty)"; exit 2; }
    fi
    exit 0
fi

# gsettings needs the session bus of a GNOME login.
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]; then
    die "no session D-Bus: cannot write theme keys — re-run from your GNOME login"
fi

# 1. Remove the previous Orchis theme setup (idempotent).
if [[ -e $OLD_GDM_BIN ]]; then
    echo "→ Restoring the stock GDM stylesheet (old Orchis greeter + pacman hook)..."
    sudo "$OLD_GDM_BIN" revert
elif [[ -e $OLD_GDM_HOOK ]]; then
    echo "→ Removing the orphaned old GDM theme pacman hook..."
    sudo rm -f "$OLD_GDM_HOOK"
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
for f in gtk.css gtk-dark.css assets; do
    dst="$CONFIG_HOME/gtk-4.0/$f"
    if [[ -L $dst && "$(readlink "$dst")" == */themes/Orchis-Dark/* ]]; then
        rm -f "$dst"
    fi
done
for p in orchis-theme tela-icon-theme bibata-cursor-theme-bin gnome-shell-extension-appindicator; do
    if pacman -Q "$p" >/dev/null 2>&1; then
        echo "○ replaced package still installed: $p (sudo pacman -Rns $p)"
    fi
done

# 2. Reset theme keys. Keep color-scheme / accent from user.conf.
echo "→ Resetting GTK/icon/cursor theme keys to defaults..."
for key in gtk-theme icon-theme cursor-theme cursor-size; do
    gsettings reset org.gnome.desktop.interface "$key" 2>/dev/null || true
done
if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell.extensions.user-theme; then
    gsettings reset org.gnome.shell.extensions.user-theme name 2>/dev/null \
        || gsettings set org.gnome.shell.extensions.user-theme name ''
fi

echo "✓ theme: GNOME defaults (Adwaita; other extensions left as-is)"
