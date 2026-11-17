#!/usr/bin/env bash
# theme-setup.sh — Orchis-Dark (GTK3 + GTK4/libadwaita + Shell), Tela-blue-dark
# icons, Bibata-Modern-Ice cursor, everywhere: session, libadwaita apps
# (Files, Text Editor, Settings…), Flatpak apps, and the GDM login screen.
#
# Packages: orchis-theme (pacman.txt), tela-icon-theme + bibata-cursor-theme-bin
# (aur.txt). The gsettings keys live in gnome/dconf/user.conf (session) and
# stow/gdm/etc/dconf/db/gdm.d/00-login-screen (greeter); this script places the
# files those keys need and re-asserts them.
#   SKIP_GDM_SHELL_THEME=1  keep the stock GDM shell stylesheet
#   theme-setup.sh --sync   only refresh the user theme copy if the system
#                           theme changed (run at login by theme-sync.service)
#   theme-setup.sh --check  exit 0 in sync, 1 stale, 2 not set up (check.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GTK_THEME_NAME="Orchis-Dark"
ICON_THEME="Tela-blue-dark"
CURSOR_THEME="Bibata-Modern-Ice"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SYS_SHARE="${THEME_SYS_SHARE:-/usr/share}"   # tests: fake /usr/share

die() { echo "✗ $*" >&2; exit 1; }

USER_THEME="$DATA_HOME/themes/$GTK_THEME_NAME"
STAMP="$USER_THEME/.dotfiles-theme-sync"
# theme_signature: content hash of the system theme's main stylesheets, so an
# orchis-theme upgrade (package mtimes are build times) is always noticed.
theme_signature() {
    local f
    for f in gtk-3.0/gtk.css gtk-4.0/gtk.css gnome-shell/gnome-shell.css; do
        if [[ -f $SYS_SHARE/themes/$GTK_THEME_NAME/$f ]]; then
            cat "$SYS_SHARE/themes/$GTK_THEME_NAME/$f"
        fi
    done | sha256sum | cut -d' ' -f1
}
# copy_user_theme: Flatpak sandboxes cannot see /usr/share/themes but can read
# ~/.local/share/themes; that copy also shadows the system theme on the host,
# so it must follow every upgrade (theme-sync.service checks at each login).
copy_user_theme() {
    mkdir -p "$DATA_HOME/themes"
    rm -rf "$USER_THEME.new"
    cp -r "$SYS_SHARE/themes/$GTK_THEME_NAME" "$USER_THEME.new"
    theme_signature >"$USER_THEME.new/.dotfiles-theme-sync"
    rm -rf "$USER_THEME"
    mv "$USER_THEME.new" "$USER_THEME"
}

# --check: 0 = user copy matches the system theme, 1 = stale, 2 = not set up.
if [[ ${1:-} == --check ]]; then
    [[ -d $SYS_SHARE/themes/$GTK_THEME_NAME && -f $STAMP ]] || exit 2
    [[ "$(cat "$STAMP")" == "$(theme_signature)" ]]
    exit
fi

if [[ ${1:-} == --sync ]]; then
    [[ -d $SYS_SHARE/themes/$GTK_THEME_NAME ]] || die "system theme $GTK_THEME_NAME missing"
    if [[ "$(cat "$STAMP" 2>/dev/null)" != "$(theme_signature)" ]]; then
        copy_user_theme
        echo "✓ refreshed $USER_THEME from $SYS_SHARE/themes/$GTK_THEME_NAME"
    fi
    exit 0
fi

for d in "themes/$GTK_THEME_NAME/gtk-4.0" "themes/$GTK_THEME_NAME/gnome-shell" \
         "icons/$ICON_THEME" "icons/$CURSOR_THEME/cursors"; do
    [[ -d $SYS_SHARE/$d ]] || die "missing $SYS_SHARE/$d — install orchis-theme (pacman), tela-icon-theme and bibata-cursor-theme-bin (bash scripts/install-aur.sh)"
done

# 1. User copy of the theme (Flatpak apps), kept current by theme-sync.service.
echo "→ Copying $GTK_THEME_NAME to $DATA_HOME/themes (Flatpak apps)..."
copy_user_theme
unit_dir="$CONFIG_HOME/systemd/user"
mkdir -p "$unit_dir/default.target.wants"
# The unit runs a copy of this script (--sync needs nothing from the repo), so
# moving or deleting the dotfiles checkout cannot break the login-time refresh.
sync_bin="$DATA_HOME/dotfiles/theme-setup.sh"
mkdir -p "${sync_bin%/*}"
install -m 0755 "$0" "$sync_bin"
cat >"$unit_dir/theme-sync.service" <<EOF
# Installed by dotfiles scripts/theme-setup.sh: refresh the user copy of
# $GTK_THEME_NAME after an orchis-theme upgrade (Flatpak + libadwaita apps).
[Unit]
Description=Refresh user copy of the $GTK_THEME_NAME theme

[Service]
Type=oneshot
ExecStart=/usr/bin/bash $sync_bin --sync

[Install]
WantedBy=default.target
EOF
# Enable without needing a user bus (headless / SSH runs).
ln -sfn ../theme-sync.service "$unit_dir/default.target.wants/theme-sync.service"
systemctl --user daemon-reload 2>/dev/null || true

# 2. libadwaita apps ignore gtk-theme; they load ~/.config/gtk-4.0/gtk.css.
#    Point it at the user copy (resolves on the host and inside Flatpaks).
echo "→ Linking libadwaita (GTK4) overrides in $CONFIG_HOME/gtk-4.0..."
mkdir -p "$CONFIG_HOME/gtk-4.0"
for f in gtk.css gtk-dark.css assets; do
    dst="$CONFIG_HOME/gtk-4.0/$f"
    want="$DATA_HOME/themes/$GTK_THEME_NAME/gtk-4.0/$f"
    [[ -e $want ]] || continue
    if [[ -e $dst || -L $dst ]] && [[ "$(readlink "$dst" 2>/dev/null)" != "$want" ]]; then
        bak="$dst.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dst" "$bak"
        echo "  backed up existing $dst → $bak"
    fi
    ln -sfn "$want" "$dst"
done

# 3. Flatpak apps: read the theme copy + GTK4 override. GTK3 apps pick the
#    theme by name from the settings portal; libadwaita apps get the
#    ~/.config/gtk-4.0 CSS. No GTK_THEME env: forcing it loads Orchis as the
#    base theme under libadwaita on top of that CSS (double-styled apps).
#    Host /usr/share/icons is already visible to Flatpaks (icons + cursor).
if command -v flatpak >/dev/null 2>&1; then
    echo "→ Flatpak overrides (theme, GTK4 CSS)..."
    flatpak override --user \
        --filesystem=xdg-data/themes:ro \
        --filesystem=xdg-config/gtk-4.0:ro \
        --filesystem=xdg-config/gtk-3.0:ro \
        --unset-env=GTK_THEME
else
    die "flatpak missing — Flatpak apps cannot be themed (sudo pacman -S flatpak)"
fi

# 4. Session keys (also in gnome/dconf/user.conf; re-asserted for reruns).
#    Written through dconf, so no running GNOME Shell is needed; the Shell
#    picks the changes up live or at next login.
ext=user-theme@gnome-shell-extensions.gcampax.github.com
[[ -d $SYS_SHARE/gnome-shell/extensions/$ext || -d $DATA_HOME/gnome-shell/extensions/$ext ]] \
    || die "$ext missing (gnome-shell-extensions package) — shell theme not applied"
THEME_FAILED=""
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]; then
    # Recorded, not fatal: the GDM part below still runs.
    THEME_FAILED="no session D-Bus: gsettings cannot persist the theme keys — re-run from your GNOME login"
    echo "✗ $THEME_FAILED" >&2
else
    echo "→ Session theme keys..."
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME"
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface accent-color blue
    enabled="$(gsettings get org.gnome.shell enabled-extensions)"
    if [[ $enabled != *"'$ext'"* ]]; then
        if [[ $enabled == "@as []" || $enabled == "[]" ]]; then
            enabled="['$ext']"
        else
            enabled="${enabled%]}, '$ext']"
        fi
        gsettings set org.gnome.shell enabled-extensions "$enabled"
    fi
    gsettings set org.gnome.shell.extensions.user-theme name "$GTK_THEME_NAME"
fi

# 5. GDM login screen: full shell stylesheet (gresource) + pacman hook.
if [[ "${SKIP_GDM_SHELL_THEME:-0}" != 1 ]]; then
    GDM_SHELL_THEME="$GTK_THEME_NAME" bash "$REPO_ROOT/scripts/gdm-shell-theme.sh" install
fi

[[ -z $THEME_FAILED ]] || exit 1
echo "✓ theme: $GTK_THEME_NAME · icons $ICON_THEME · cursor $CURSOR_THEME (log out/in for the shell + cursor everywhere)"
