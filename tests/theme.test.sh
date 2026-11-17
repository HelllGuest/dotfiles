#!/usr/bin/env bash
# Theme: Orchis-Dark + Tela-blue-dark + Bibata-Modern-Ice in the session,
# libadwaita apps, Flatpaks and the GDM login screen (gresource rebuild).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$ROOT/packages/$1"; }

# --- packages + names agree everywhere --------------------------------------
for p in orchis-theme python-gobject gnome-tweaks extension-manager; do
  list pacman.txt | grep -qx "$p" || fail "pacman.txt must include $p"
done
for p in tela-icon-theme bibata-cursor-theme-bin; do
  list aur.txt | grep -qx "$p" || fail "aur.txt must include $p"
done
U="$ROOT/gnome/dconf/user.conf"; G="$ROOT/stow/gdm/etc/dconf/db/gdm.d/00-login-screen"
for kv in "gtk-theme='Orchis-Dark'" "icon-theme='Tela-blue-dark'" "cursor-theme='Bibata-Modern-Ice'"; do
  grep -qx "$kv" "$U" || fail "user.conf must set $kv"
  grep -qx "$kv" "$G" || fail "GDM greeter must set $kv"
done
grep -qx "name='Orchis-Dark'" "$U" || fail "user.conf must set the User Themes shell theme"
grep -q "'user-theme@gnome-shell-extensions.gcampax.github.com'" "$U" || fail "user-theme extension must be enabled"
grep -qx 'user-theme@gnome-shell-extensions.gcampax.github.com' "$ROOT/gnome/extensions.txt" \
  || fail "extensions.txt must list user-theme"
for v in 'GTK_THEME_NAME="Orchis-Dark"' 'ICON_THEME="Tela-blue-dark"' 'CURSOR_THEME="Bibata-Modern-Ice"'; do
  grep -qx "$v" "$ROOT/scripts/theme-setup.sh" || fail "theme-setup.sh must use $v"
done
grep -q 'run_step "Theme setup" bash scripts/theme-setup.sh' "$ROOT/install.sh" || fail "install.sh must run theme-setup.sh"

# --- theme-setup.sh with a fake /usr/share + stub flatpak --------------------
S="$T/share"
mkdir -p "$S/themes/Orchis-Dark/gtk-4.0/assets" "$S/themes/Orchis-Dark/gnome-shell" \
  "$S/icons/Tela-blue-dark" "$S/icons/Bibata-Modern-Ice/cursors" "$T/bin" "$T/home/.config/gtk-4.0"
echo '/* orchis gtk4 */' >"$S/themes/Orchis-Dark/gtk-4.0/gtk.css"
echo '/* orchis gtk4 dark */' >"$S/themes/Orchis-Dark/gtk-4.0/gtk-dark.css"
echo 'mine' >"$T/home/.config/gtk-4.0/gtk.css"          # pre-existing user file
printf '#!/bin/sh\necho "$*" >>"%s/flatpak.log"\n' "$T" >"$T/bin/flatpak"
mkdir -p "$S/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com"
# gsettings stub: records sets, reports a prior extension list.
cat >"$T/bin/gsettings" <<EOF
#!/bin/sh
echo "\$*" >>"$T/gsettings.log"
[ "\$1 \$2 \$3" = "get org.gnome.shell enabled-extensions" ] && echo "['a@b']"
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' >"$T/bin/systemctl"
chmod +x "$T/bin/"*
mkdir -p "$T/core"
for c in bash sed grep cat cp mv rm mkdir ln readlink date dirname mktemp sha256sum cut install; do ln -s "$(command -v "$c")" "$T/core/$c"; done
run_ts() { HOME="$T/home" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_RUNTIME_DIR="$T/none" \
  DBUS_SESSION_BUS_ADDRESS="${TS_BUS-unix:path=/fake}" THEME_SYS_SHARE="$S" SKIP_GDM_SHELL_THEME=1 \
  PATH="$T/bin:$T/core" bash "$ROOT/scripts/theme-setup.sh" "$@"; }
run_ts >"$T/out" 2>&1 || fail "theme-setup.sh failed: $(cat "$T/out")"
[[ "$(readlink "$T/home/.config/gtk-4.0/gtk.css")" == "$T/home/.local/share/themes/Orchis-Dark/gtk-4.0/gtk.css" ]] \
  || fail "gtk-4.0/gtk.css must link to the user theme copy (visible inside Flatpaks)"
[[ -L "$T/home/.config/gtk-4.0/assets" && -L "$T/home/.config/gtk-4.0/gtk-dark.css" ]] || fail "gtk-dark.css + assets must be linked"
baks=("$T/home/.config/gtk-4.0/"gtk.css.bak.*)
[[ -e ${baks[0]} ]] || fail "an existing user gtk.css must be backed up, not lost"
grep -q '/\* orchis gtk4 \*/' "$T/home/.local/share/themes/Orchis-Dark/gtk-4.0/gtk.css" || fail "theme must be copied for Flatpaks"
grep -q -- '--filesystem=xdg-data/themes:ro' "$T/flatpak.log" && grep -q -- '--filesystem=xdg-config/gtk-4.0:ro' "$T/flatpak.log" \
  || fail "Flatpak override must expose the theme + GTK4 CSS: $(cat "$T/flatpak.log")"
grep -q -- '--unset-env=GTK_THEME' "$T/flatpak.log" && ! grep -q -- '--env=GTK_THEME' "$T/flatpak.log" \
  || fail "Flatpaks must not get a forced GTK_THEME (double-styles libadwaita): $(cat "$T/flatpak.log")"
# Session keys go through dconf (no running Shell needed); extension appended once.
grep -qxF "set org.gnome.shell enabled-extensions ['a@b', 'user-theme@gnome-shell-extensions.gcampax.github.com']" "$T/gsettings.log" \
  || fail "user-theme must be appended to enabled-extensions: $(cat "$T/gsettings.log")"
grep -qx 'set org.gnome.desktop.interface cursor-theme Bibata-Modern-Ice' "$T/gsettings.log" || fail "cursor key must be set"
grep -qx 'set org.gnome.shell.extensions.user-theme name Orchis-Dark' "$T/gsettings.log" || fail "shell theme name must be set"
# Login-time refresh of the user copy, enabled without a user bus.
u="$T/home/.config/systemd/user"
sb="$T/home/.local/share/dotfiles/theme-setup.sh"
grep -qx "ExecStart=/usr/bin/bash $sb --sync" "$u/theme-sync.service" \
  || fail "theme-sync.service must run its own copy (not the checkout) with --sync"
cmp -s "$sb" "$ROOT/scripts/theme-setup.sh" && [[ -x $sb ]] || fail "sync copy must match theme-setup.sh"
[[ "$(readlink "$u/default.target.wants/theme-sync.service")" == ../theme-sync.service ]] || fail "theme-sync.service must be enabled"
run_ts --check || fail "--check must pass right after setup"
echo '/* orchis gtk4 v2 */' >"$S/themes/Orchis-Dark/gtk-4.0/gtk.css"     # package upgrade
if run_ts --check; then fail "--check must notice a changed system theme"; fi
run_ts --sync >/dev/null || fail "--sync failed"
grep -q 'v2' "$T/home/.local/share/themes/Orchis-Dark/gtk-4.0/gtk.css" || fail "--sync must refresh the user copy"
run_ts --check || fail "--check must pass after --sync"
# No session bus: theme files still placed, keys reported as a failure (exit 1).
: >"$T/gsettings.log"
if TS_BUS="" run_ts >"$T/out" 2>&1; then fail "no session bus must be a recorded failure"; fi
grep -q 'no session D-Bus' "$T/out" && [[ ! -s $T/gsettings.log ]] || fail "no bus: must not write keys, must say why: $(cat "$T/out")"
run_ts >/dev/null 2>&1 || fail "theme-setup.sh must be re-runnable"
baks=("$T/home/.config/gtk-4.0/"gtk.css.bak.*)
[[ ${#baks[@]} -eq 1 ]] || fail "re-run must not back up our own symlink"
rm -rf "$S/icons/Bibata-Modern-Ice"
if run_ts >"$T/out" 2>&1; then fail "missing cursor theme must fail, not skip"; fi
grep -q 'Bibata-Modern-Ice' "$T/out" || fail "failure must name what is missing: $(cat "$T/out")"

# --- gdm-shell-theme.sh on a fake root ----------------------------------------
command -v glib-compile-resources >/dev/null && python3 -c 'import gi' 2>/dev/null \
  || { echo "SKIP: glib-compile-resources / python-gobject missing (gdm-shell-theme)"; echo "PASS: theme.test.sh"; exit 0; }
R="$T/root"; mkdir -p "$R/usr/share/gnome-shell" "$T/stock" "$R/usr/share/themes/Orchis-Dark/gnome-shell/assets"
mkstock() { # $1 = version tag inside the css
  for f in gnome-shell-dark.css gnome-shell-light.css gnome-shell-high-contrast.css pad-osd.css; do
    echo "/* stock $1 $f */" >"$T/stock/$f"
  done
  printf '<gresources><gresource prefix="/org/gnome/shell/theme">%s</gresource></gresources>' \
    "$(for f in "$T"/stock/*; do printf '<file>%s</file>' "${f##*/}"; done)" >"$T/stock.xml"
  glib-compile-resources --sourcedir="$T/stock" --target="$R/usr/share/gnome-shell/gnome-shell-theme.gresource" "$T/stock.xml"
}
mkstock v1
cp "$R/usr/share/gnome-shell/gnome-shell-theme.gresource" "$T/stock-v1.gresource"
echo '/* orchis shell */' >"$R/usr/share/themes/Orchis-Dark/gnome-shell/gnome-shell.css"
echo '<svg/>' >"$R/usr/share/themes/Orchis-Dark/gnome-shell/assets/toggle-on.svg"
command -v dbus-run-session >/dev/null && command -v setsid >/dev/null \
  || { echo "SKIP: dbus-run-session/setsid missing (gdm-shell-theme trial)"; echo "PASS: theme.test.sh"; exit 0; }
# Stub GNOME Shell for the headless trial; mode file: good | broken | silent
# (the trial runs it under env -i, so no env vars reach it).
echo good >"$T/stub-mode"
cat >"$T/fake-shell" <<EOF
#!/bin/bash
res="\${G_RESOURCE_OVERLAYS#*=}"
case "\$(cat "$T/stub-mode")" in
  good)   echo "GLib-GIO-Message: Opened file '\$res/gnome-shell-dark.css' as a resource overlay" ;;
  broken) echo "GLib-GIO-Message: Opened file '\$res/gnome-shell-dark.css' as a resource overlay"
          echo "St-WARNING **: Error parsing stylesheet 'resource:///org/gnome/shell/theme/gnome-shell-dark.css'" ;;
  silent) : ;;
esac
exec sleep 60
EOF
chmod +x "$T/fake-shell"
gst() { GDM_THEME_ROOT="$R" GDM_THEME_SHELL="$T/fake-shell" bash "$ROOT/scripts/gdm-shell-theme.sh" "$@"; }
cat_res() { python3 -I -c 'import sys
from gi.repository import Gio
print(Gio.Resource.load(sys.argv[1]).lookup_data(sys.argv[2],0).get_data().decode().strip())' "$R/usr/share/gnome-shell/gnome-shell-theme.gresource" "/org/gnome/shell/theme/$1"; }
gst apply >/dev/null || fail "gdm-shell-theme apply failed"
[[ $(cat_res gnome-shell-dark.css) == '/* orchis shell */' ]] || fail "GDM dark stylesheet must be the theme's"
[[ $(cat_res gnome-shell-light.css) == '/* stock v1 gnome-shell-light.css */' ]] || fail "light stylesheet must stay stock (greeter uses dark)"
[[ $(cat_res gnome-shell-high-contrast.css) == '/* stock v1 gnome-shell-high-contrast.css */' ]] || fail "high-contrast must stay stock"
[[ $(cat_res assets/toggle-on.svg) == '<svg/>' ]] || fail "theme assets must be bundled"
[[ $(gst status | head -1) == 'themed: Orchis-Dark' ]] || fail "status must report the theme"
gst apply >/dev/null || fail "re-apply failed"
cmp -s "$R/usr/local/share/gdm-shell-theme/gnome-shell-theme.gresource.orig" "$T/stock-v1.gresource" \
  || fail "re-apply must keep the pristine stock copy (not save our own build)"
mkstock v2                                          # gnome-shell upgrade replaced it
gst apply >/dev/null || fail "apply after upgrade failed"
[[ $(cat_res gnome-shell-high-contrast.css) == '/* stock v2 gnome-shell-high-contrast.css */' ]] \
  || fail "after a gnome-shell upgrade the new stock file must become the base"
gst revert >/dev/null || fail "revert failed"
[[ $(cat_res gnome-shell-dark.css) == '/* stock v2 gnome-shell-dark.css */' ]] || fail "revert must restore stock"
[[ $(gst status | head -1) == stock ]] || fail "status after revert must be stock"
# Headless trial: a stylesheet GNOME Shell rejects, or never loads, is not installed.
touch "$T/trial-start"
for mode in broken silent; do
  echo "$mode" >"$T/stub-mode"
  if gst apply >"$T/out" 2>&1; then fail "trial ($mode) must refuse the stylesheet"; fi
  [[ $(cat_res gnome-shell-dark.css) == '/* stock v2 gnome-shell-dark.css */' ]] || fail "refused trial ($mode) must leave the file untouched"
  grep -q 'login screen left unchanged' "$T/out" || fail "trial ($mode) must say why: $(cat "$T/out")"
done
echo good >"$T/stub-mode"
pgrep -f "$T/fake-shell" >/dev/null && fail "trial must stop every process it started"
for d in "${TMPDIR:-/tmp}"/tmp.*; do   # trial homes are mktemp -d dirs with run/ + home/
  [[ -d $d/run && -d $d/home && $d -nt $T/trial-start ]] && fail "trial must remove its throwaway home ($d)"
done
# The trial's bus activates nothing (gvfs/portal FUSE mounts leaked in the VM)
# and anything still mounted under its temp dir is detached before removal.
grep -q 'dbus-run-session --config-file="$t/bus.conf"' "$ROOT/scripts/gdm-shell-theme.sh" \
  || fail "trial must use a bus config without service activation"
! grep -q '<servicedir' "$ROOT/scripts/gdm-shell-theme.sh" || fail "trial bus must not list service dirs"
grep -q 'findmnt -rn -o TARGET' "$ROOT/scripts/gdm-shell-theme.sh" || fail "trial must unmount leftovers before rm"
# compat_css: greeter selectors the theme lacks get stock *sizing* only
# (GNOME 51 next/a11y icons rendered huge under Orchis); theme rules untouched.
cblk="$(awk '/^compat_css\(\) \{$/{f=1} f; f&&/^}$/{exit}' "$ROOT/scripts/gdm-shell-theme.sh")"
[[ -n $cblk ]] || fail "compat_css not found"
printf '%s\n' '.login-dialog-button.a11y-button StIcon { icon-size: 1em; color: red; padding: 4px; border-radius: 99px; }' \
  '.login-dialog .user-icon, .panel { icon-size: 160px; background: blue; }' \
  '.login-dialog-button.next-button StIcon { icon-size: 1em; }' '.panel { height: 2em; }' >"$T/stock.css"
printf '%s\n' '/* theme */' '.login-dialog-button.next-button StIcon { icon-size: 3em; color: green; }' >"$T/theme.css"
out="$(bash -c "$cblk"'
compat_css "$1" "$2"' _ "$T/stock.css" "$T/theme.css")"
head -2 <<<"$out" | grep -q 'icon-size: 3em; color: green' || fail "theme CSS must come first, unchanged: $out"
grep -q '\.login-dialog-button\.a11y-button StIcon' <<<"$out" || fail "missing greeter selector must get stock sizing: $out"
grep -q 'color: red\|background: blue' <<<"$out" && fail "only sizing may be copied (theme colours win): $out"
[[ $(grep -c 'next-button' <<<"$out") -eq 1 ]] || fail "selectors the theme styles must not be duplicated: $out"
grep -q '^\.panel' <<<"$(sed -n '3,$p' <<<"$out")" && fail "only login/unlock/a11y selectors are filled in: $out"
grep -q 'icon-size: 160px' <<<"$out" || fail "user-icon sizing must be copied: $out"
grep -q 'padding: 4px' <<<"$out" && grep -q 'border-radius: 99px' <<<"$out" || fail "spacing/radius must be copied: $out"

# A damaged stock file is never saved as the pristine copy.
rm -rf "$R/usr/local/share/gdm-shell-theme"
head -c 512 /dev/urandom >"$R/usr/share/gnome-shell/gnome-shell-theme.gresource"
if gst apply >"$T/out" 2>&1; then fail "damaged stock gresource must be refused"; fi
[[ ! -e $R/usr/local/share/gdm-shell-theme/gnome-shell-theme.gresource.orig ]] || fail "damaged file must not become the pristine copy"
grep -q 'damaged or modified' "$T/out" || fail "must explain the damaged stock file: $(cat "$T/out")"
# pacman reports altered non-backup files as warnings on stderr: both streams read.
grep -qF 'pacman -Qkk gnome-shell 2>&1 | grep -qF' "$ROOT/scripts/gdm-shell-theme.sh" \
  || fail "stock_ok must read pacman -Qkk stderr (warnings) too"
mkstock v2
# install: root-owned copy + pacman hook naming the theme's own package.
mkdir -p "$T/ibin"
cat >"$T/ibin/sudo" <<'EOF'
#!/bin/bash
args=(); skip=0
for a in "$@"; do
  if ((skip)); then skip=0; continue; fi
  case $a in -o|-g) skip=1 ;; *) args+=("$a") ;; esac
done
exec "${args[@]}"
EOF
printf '#!/bin/sh\n[ "$1" = -Qqo ] && echo orchis-theme\n' >"$T/ibin/pacman"
chmod +x "$T/ibin/"*
mkdir -p "$R/usr/share/themes/Orchis-Dark/gnome-shell"
echo '/* orchis shell */' >"$R/usr/share/themes/Orchis-Dark/gnome-shell/gnome-shell.css"
PATH="$T/ibin:$PATH" gst install >"$T/out" 2>&1 || fail "install failed: $(cat "$T/out")"
h="$R/etc/pacman.d/hooks/95-gdm-shell-theme.hook"
grep -qx 'Target = gnome-shell' "$h" && grep -qx 'Target = orchis-theme' "$h" || fail "hook must target gnome-shell + the theme package"
grep -qx 'Exec = /usr/bin/env GDM_SHELL_THEME=Orchis-Dark /usr/local/bin/gdm-shell-theme apply' "$h" \
  || fail "hook must exec the root-owned copy: $(grep Exec "$h")"
[[ -x $R/usr/local/bin/gdm-shell-theme ]] || fail "install must place the root-owned copy"
[[ $(cat_res gnome-shell-dark.css) == '/* orchis shell */' ]] || fail "install must apply"
gst revert >/dev/null
[[ ! -e $h && ! -e $R/usr/local/bin/gdm-shell-theme ]] || fail "revert must remove hook + copy"
rm -rf "$R/usr/share/themes/Orchis-Dark"
if gst apply >/dev/null 2>&1; then fail "apply without the theme must fail"; fi
[[ $(cat_res gnome-shell-dark.css) == '/* stock v2 gnome-shell-dark.css */' ]] || fail "failed apply must leave the file untouched"
# The root pacman hook must run the root-owned copy, never the user's checkout.
grep -q 'install -D -m 0755 -o root -g root "$self" "$BIN"' "$ROOT/scripts/gdm-shell-theme.sh" \
  || fail "hook target must be a root-owned copy"

echo "PASS: theme.test.sh"
