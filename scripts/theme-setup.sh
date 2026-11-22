#!/usr/bin/env bash
# theme-setup.sh — GNOME default (Adwaita) desktop. Does not install Aura Glass.
# Purges Aura Glass caches, Colloid icons, helper extension, and GTK overrides.
# Leaves other GNOME Shell extensions alone. Still removes leftover Orchis
# greeter hooks once.
#
#   theme-setup.sh          reset theme keys; wipe Aura leftovers
#   theme-setup.sh --check  exit 0 stock ok, 1 broken (reason on stdout),
#                           2 defaults not applied yet (check.sh)
# Opt out of install.sh: SKIP_THEME=1
set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# Old setup (Orchis greeter): root-owned copy of the removed gdm-shell-theme.sh
# and its pacman hook. Overridable for tests only.
OLD_GDM_BIN="${THEME_OLD_GDM_BIN:-/usr/local/bin/gdm-shell-theme}"
OLD_GDM_HOOK="${THEME_OLD_GDM_HOOK:-/etc/pacman.d/hooks/95-gdm-shell-theme.hook}"
AURA_HELPER="aura-glass-blur@aura-glass.local"

die() { echo "✗ $*" >&2; exit 1; }

gset_get() {
    gsettings get "$@" 2>/dev/null | tr -d "'"
}

aura_paths_present() {
    [[ -d $CONFIG_HOME/aura-glass ]] \
        || [[ -d $HOME/.themes/Aura-Glass || -d $DATA_HOME/themes/Aura-Glass ]] \
        || [[ -d $DATA_HOME/gnome-shell/extensions/$AURA_HELPER ]] \
        || [[ -d $CACHE_HOME/aura-glass || -d $CACHE_HOME/dotfiles/aura-glass ]] \
        || [[ -d $DATA_HOME/icons/Colloid || -d $DATA_HOME/icons/Colloid-Dark || -d $DATA_HOME/icons/Colloid-Light ]] \
        || compgen -G "$CONFIG_HOME/gtk-4.0/gtk.css.backup.*" >/dev/null 2>&1 \
        || compgen -G "$DATA_HOME/applications/*AuraGlass*" >/dev/null 2>&1
}

# --check: 0 = GNOME defaults + no Aura leftovers, 1 broken, 2 not applied.
if [[ ${1:-} == --check ]]; then
    if [[ -e $OLD_GDM_HOOK || -e $OLD_GDM_BIN ]]; then
        echo "old Orchis GDM hook still installed ($OLD_GDM_HOOK)"
        exit 1
    fi
    if aura_paths_present; then
        echo "Aura Glass leftovers still present — re-run theme-setup.sh"
        exit 1
    fi
    gtk="$(gset_get org.gnome.desktop.interface gtk-theme || true)"
    icon="$(gset_get org.gnome.desktop.interface icon-theme || true)"
    cursor="$(gset_get org.gnome.desktop.interface cursor-theme || true)"
    case $gtk in
        Adwaita|Adwaita-dark) ;;
        '')
            echo "could not read gtk-theme (no session gsettings?)"
            exit 1
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
# Aura Glass user units (if any survived uninstall).
rm -f "$unit_dir"/aura-glass-*.service \
    "$unit_dir"/default.target.wants/aura-glass-*.service \
    "$unit_dir"/gnome-session.target.wants/aura-glass-*.service 2>/dev/null || true
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

# 2. Purge Aura Glass completely (caches, icons, helper, GTK backups, desktop entry).
echo "→ Removing Aura Glass completely..."
rm -rf "$CONFIG_HOME/aura-glass" \
    "$HOME/.themes/Aura-Glass" \
    "$DATA_HOME/themes/Aura-Glass" \
    "$DATA_HOME/gnome-shell/extensions/$AURA_HELPER" \
    "$CACHE_HOME/aura-glass" \
    "$CACHE_HOME/dotfiles/aura-glass" \
    "$DATA_HOME/icons/Colloid" \
    "$DATA_HOME/icons/Colloid-Dark" \
    "$DATA_HOME/icons/Colloid-Light"
rm -f "$CONFIG_HOME"/gtk-4.0/gtk.css.backup.* \
    "$DATA_HOME"/applications/io.github.DevWebeloper.AuraGlassSettings.desktop \
    "$DATA_HOME"/applications/*AuraGlass*.desktop 2>/dev/null || true
# Drop Aura-written GTK overrides only (leave unrelated user gtk.css alone).
for f in "$CONFIG_HOME/gtk-3.0/gtk.css" "$CONFIG_HOME/gtk-4.0/gtk.css" "$CONFIG_HOME/gtk-4.0/gtk-dark.css"; do
    if [[ -f $f ]] && grep -qiE 'aura-glass|Aura Glass|Aura-Glass' "$f" 2>/dev/null; then
        rm -f "$f"
    fi
done
if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable "$AURA_HELPER" 2>/dev/null || true
fi
python3 - "$AURA_HELPER" <<'PY'
import ast, subprocess, sys

uuid = sys.argv[1]
for key in ("enabled-extensions", "disabled-extensions"):
    try:
        raw = subprocess.check_output(
            ["gsettings", "get", "org.gnome.shell", key], text=True
        ).strip()
    except subprocess.CalledProcessError:
        continue
    s = raw.split(" ", 1)[-1] if raw.startswith("@as") else raw
    lst = [x for x in ast.literal_eval(s) if x != uuid]
    gv = "[" + ", ".join(repr(x) for x in lst) + "]"
    subprocess.check_call(["gsettings", "set", "org.gnome.shell", key, gv])

# Drop only Aura settings tiles from the app picker; keep the rest of the grid.
try:
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    drop = ("AuraGlass", "aura-glass")
    settings = Gio.Settings.new("org.gnome.shell")
    layout = settings.get_value("app-picker-layout")
    pages = []
    changed = False
    for i in range(layout.n_children()):
        page = layout.get_child_value(i)
        builder = GLib.VariantBuilder.new(GLib.VariantType("a{sv}"))
        for j in range(page.n_children()):
            entry = page.get_child_value(j)
            key = entry.get_child_value(0).unpack()
            if any(s in key for s in drop):
                changed = True
                continue
            builder.add_value(entry)
        pages.append(builder.end())
    if changed:
        settings.set_value(
            "app-picker-layout",
            GLib.Variant.new_array(GLib.VariantType("a{sv}"), pages),
        )
except Exception:
    # No PyGObject, no session bus (tests), or unexpected layout shape: skip.
    pass
PY

# 3. GNOME schema defaults for theme / pointer / accent / color-scheme.
echo "→ Resetting GNOME theme keys to defaults..."
for key in gtk-theme icon-theme cursor-theme cursor-size color-scheme accent-color; do
    gsettings reset org.gnome.desktop.interface "$key" 2>/dev/null || true
done
if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell.extensions.user-theme; then
    gsettings reset org.gnome.shell.extensions.user-theme name 2>/dev/null \
        || gsettings set org.gnome.shell.extensions.user-theme name ''
fi

echo "✓ theme: GNOME defaults (Aura Glass removed; other extensions left as-is)"
