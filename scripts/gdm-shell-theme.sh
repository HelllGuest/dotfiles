#!/usr/bin/env bash
# gdm-shell-theme.sh — use a GNOME Shell theme (default Orchis-Dark) on the GDM
# login screen by rebuilding gnome-shell-theme.gresource.
#
#   bash scripts/gdm-shell-theme.sh install   # root-owned copy + pacman hook, then apply
#   sudo gdm-shell-theme apply                # (re)build from the pristine stock file
#   sudo gdm-shell-theme revert               # stock login screen, hook removed
#   gdm-shell-theme status
#
# The user session gets its shell theme from the User Themes extension; this
# only matters where no extension runs (GDM greeter). Before anything is
# installed, a headless GNOME Shell in GDM mode loads the new stylesheet (as an
# unprivileged user when run as root); a parse error or a stylesheet that never
# loads keeps the current login screen. A gnome-shell upgrade overwrites the
# gresource: the pacman hook saves that new stock file as the pristine copy and
# re-applies (with the same check). Only the dark stylesheet (the greeter's,
# color-scheme prefer-dark) is themed; light and high-contrast stay stock.
# Login broken anyway? Ctrl+Alt+F3, log in, then
# `sudo gdm-shell-theme revert && sudo systemctl restart gdm`.
set -euo pipefail

THEME="${GDM_SHELL_THEME:-Orchis-Dark}"
ROOT="${GDM_THEME_ROOT:-}"            # tests: fake filesystem root
GR="$ROOT/usr/share/gnome-shell/gnome-shell-theme.gresource"
STATE="$ROOT/usr/local/share/gdm-shell-theme"
ORIG="$STATE/gnome-shell-theme.gresource.orig"
BIN="$ROOT/usr/local/bin/gdm-shell-theme"
HOOK="$ROOT/etc/pacman.d/hooks/95-gdm-shell-theme.hook"
PREFIX=/org/gnome/shell/theme
MARK=gdm-shell-theme.marker           # present only in gresources we built
SHELL_BIN="${GDM_THEME_SHELL:-gnome-shell}"   # tests: stub for the headless trial
WORK=""
trap 'if [[ -n $WORK ]]; then rm -rf -- "$WORK"; fi' EXIT

die() { echo "gdm-shell-theme: $*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 || -n $ROOT ]] || die "run as root (sudo)"; }

# list_res FILE: resource paths below $PREFIX, one per line (Gio, no glib2-devel).
list_res() {
    python3 -I - "$1" "$PREFIX/" <<'PY'
import sys
from gi.repository import Gio
r = Gio.Resource.load(sys.argv[1])
def walk(p):
    for c in r.enumerate_children(p, 0):
        if c.endswith("/"):
            yield from walk(p + c)
        else:
            yield p + c
print("\n".join(walk(sys.argv[2])))
PY
}

# extract FILE DIR: every resource below $PREFIX into DIR (relative paths).
extract() {
    python3 -I - "$1" "$PREFIX/" "$2" <<'PY'
import os, sys
from gi.repository import Gio
r = Gio.Resource.load(sys.argv[1])
prefix, out = sys.argv[2], sys.argv[3]
def walk(p):
    for c in r.enumerate_children(p, 0):
        if c.endswith("/"):
            yield from walk(p + c)
        else:
            yield p + c
for path in walk(prefix):
    dest = os.path.join(out, path[len(prefix):])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(r.lookup_data(path, 0).get_data())
PY
}

is_ours() { list_res "$1" | grep -qx "$PREFIX/$MARK"; }

# stock_ok FILE: a readable gresource with the stylesheets GDM loads, and (on
# the real system) unmodified per pacman — never save someone else's edit as
# the "pristine" copy.
stock_ok() {
    local res
    res="$(list_res "$1" 2>/dev/null)" || return 1
    grep -qx "$PREFIX/gnome-shell-dark.css" <<<"$res" || return 1
    if [[ -z $ROOT ]] && command -v pacman >/dev/null; then
        ! pacman -Qkk gnome-shell 2>/dev/null | grep -qF "${GR#"$ROOT"}"
    fi
}

# trial RESDIR: run GNOME Shell headless in GDM mode on a private bus with
# RESDIR overlaid on the theme resources; succeed only if it opened the dark
# stylesheet and reported no CSS error.
trial() {
    local res=$1 t log i
    t="$(mktemp -d)"
    mkdir -p "$t/home" "$t/run"
    chmod 700 "$t/run"
    local -a as_user=()
    if [[ $EUID -eq 0 ]]; then
        # Never run a compositor as root: use nobody with a throwaway home.
        chown -R nobody: "$t"
        chmod 711 "$t"
        chmod 711 "${res%/*}"   # nobody must reach $res inside root's 0700 temp dir
        chmod -R a+rX "$res"
        as_user=(runuser -u nobody --)
    fi
    log="$t/shell.log"
    # Own session/process group: every child (dbus-daemon, shell helpers) is
    # stopped and reaped before the throwaway home is removed.
    setsid "${as_user[@]}" env -i PATH=/usr/bin:/bin HOME="$t/home" XDG_RUNTIME_DIR="$t/run" \
        XDG_CONFIG_HOME="$t/home/.config" GSETTINGS_BACKEND=memory \
        G_RESOURCE_OVERLAYS="$PREFIX=$res" \
        timeout -s INT 30 dbus-run-session -- "$SHELL_BIN" --headless \
        --virtual-monitor 1280x800 --mode=gdm >"$log" 2>&1 &
    local pid=$!
    # Stylesheet load is logged within ~1 s; give it time to finish parsing.
    for ((i = 0; i < 40; i++)); do
        grep -q "Opened file '$res/gnome-shell-dark.css' as a resource overlay" "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    sleep 3
    kill -INT -- "-$pid" 2>/dev/null || true
    for ((i = 0; i < 50; i++)); do
        pgrep -g "$pid" >/dev/null || break
        sleep 0.2
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    local ok=0
    if ! grep -q "Opened file '$res/gnome-shell-dark.css' as a resource overlay" "$log"; then
        echo "gdm-shell-theme: trial inconclusive (headless GNOME Shell never loaded the stylesheet):" >&2
        tail -5 "$log" >&2
        ok=1
    elif grep -E 'Error parsing stylesheet|Theme parsing error|parsing error:' "$log" >&2; then
        ok=1
    fi
    rm -rf -- "$t"
    return "$ok"
}

cmd_apply() {
    need_root
    local src="$ROOT/usr/share/themes/$THEME/gnome-shell"
    [[ -f $src/gnome-shell.css ]] || die "$THEME shell theme missing ($src) — install its package first"
    [[ -f $GR ]] || die "missing $GR (gnome-shell not installed?)"
    command -v glib-compile-resources >/dev/null || die "glib-compile-resources missing (sudo pacman -S glib2-devel)"
    install -d -m 0755 "$STATE"
    if ! is_ours "$GR"; then
        # Stock file (fresh install or gnome-shell upgrade): the new pristine copy.
        stock_ok "$GR" || die "$GR is damaged or modified outside pacman — sudo pacman -S gnome-shell, then re-run"
        install -m 0644 "$GR" "$ORIG"
    fi
    [[ -f $ORIG ]] || die "no pristine copy at $ORIG and $GR is already themed — sudo pacman -S gnome-shell"

    WORK="$(mktemp -d)"
    local work="$WORK"
    extract "$ORIG" "$work/res"
    # Theme CSS replaces the dark stylesheet, which the greeter loads; its
    # assets/ and helper SVGs sit next to it. Light + high-contrast stay stock.
    local stock_light
    stock_light="$(cat "$work/res/gnome-shell-light.css")"
    cp -r "$src/." "$work/res/"
    rm -f -- "$work/res/gnome-shell.css"
    cp "$src/gnome-shell.css" "$work/res/gnome-shell-dark.css"
    printf '%s\n' "$stock_light" >"$work/res/gnome-shell-light.css"
    if [[ -f $src/assets/dash-placeholder.svg && ! -f $work/res/dash-placeholder.svg ]]; then
        cp "$src/assets/dash-placeholder.svg" "$work/res/"
    fi
    printf '%s\n' "$THEME" >"$work/res/$MARK"

    if [[ ${GDM_THEME_TRIAL:-1} != 0 ]]; then
        echo "→ Checking the stylesheet in a headless GNOME Shell (GDM mode)..."
        trial "$work/res" || die "$THEME stylesheet failed the GNOME Shell check — login screen left unchanged"
    fi

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<gresources><gresource prefix=\"$PREFIX\">"
        (cd "$work/res" && find . -type f -printf '%P\n' | LC_ALL=C sort) \
            | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's|.*|<file>&</file>|'
        echo '</gresource></gresources>'
    } >"$work/theme.xml"
    glib-compile-resources --sourcedir="$work/res" --target="$work/new.gresource" "$work/theme.xml"

    # Sanity: the greeter must still find every stylesheet it loads.
    local res
    res="$(list_res "$work/new.gresource")"
    for f in gnome-shell-dark.css gnome-shell-light.css gnome-shell-high-contrast.css pad-osd.css "$MARK"; do
        grep -qx "$PREFIX/$f" <<<"$res" || die "built gresource lacks $f — not installed"
    done
    install -m 0644 "$work/new.gresource" "$GR.new"
    mv -f "$GR.new" "$GR"
    echo "✓ GDM shell theme: $THEME (takes effect at the next login screen)"
}

cmd_revert() {
    need_root
    if [[ -f $ORIG ]] && is_ours "$GR"; then
        install -m 0644 "$ORIG" "$GR.new"
        mv -f "$GR.new" "$GR"
    fi
    rm -f "$HOOK" "$BIN"
    rm -rf "$STATE"
    echo "✓ GDM shell theme reverted to stock"
}

cmd_install() {
    # Root-owned copy: the pacman hook runs as root and must never execute a
    # file the user can edit (the repo checkout).
    local self
    self="$(readlink -f "${BASH_SOURCE[0]}")"
    sudo install -D -m 0755 -o root -g root "$self" "$BIN"
    # Re-theme when the package shipping the theme is upgraded, too.
    local theme_pkg
    theme_pkg="$(pacman -Qqo "$ROOT/usr/share/themes/$THEME" 2>/dev/null | head -1)"
    theme_pkg="${theme_pkg:-orchis-theme}"
    local tmp
    tmp="$(mktemp)"
    cat >"$tmp" <<EOF
# Installed by dotfiles scripts/gdm-shell-theme.sh — re-theme the GDM login
# screen after gnome-shell (or the theme) replaces gnome-shell-theme.gresource.
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = gnome-shell
Target = $theme_pkg

[Action]
Description = Applying GDM shell theme ($THEME)...
When = PostTransaction
Exec = /usr/bin/env GDM_SHELL_THEME=$THEME /usr/local/bin/gdm-shell-theme apply
EOF
    sudo install -D -m 0644 -o root -g root "$tmp" "$HOOK"
    rm -f "$tmp"
    sudo env GDM_SHELL_THEME="$THEME" "$BIN" apply
}

cmd_status() {
    if [[ -f $GR ]] && is_ours "$GR"; then
        echo "themed: $(python3 -I -c 'import sys
from gi.repository import Gio
r=Gio.Resource.load(sys.argv[1]); print(r.lookup_data(sys.argv[2],0).get_data().decode().strip())' \
            "$GR" "$PREFIX/$MARK")"
    else
        echo "stock"
    fi
    [[ -f $HOOK ]] && echo "pacman hook: $HOOK" || echo "pacman hook: none"
}

case "${1:-}" in
    apply) cmd_apply ;;
    revert) cmd_revert ;;
    install) cmd_install ;;
    status) cmd_status ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
