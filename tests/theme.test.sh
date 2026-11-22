#!/usr/bin/env bash
# Theme: stock Adwaita (scripts/theme-setup.sh), old Orchis/Tela/Bibata gone,
# Full-pack UUIDs in extensions.txt, repo dconf leaves gtk-theme / blur trees alone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$ROOT/packages/$1"; }
TS="$ROOT/scripts/theme-setup.sh"
EXT="$ROOT/gnome/extensions.txt"

# --- old theme gone everywhere ------------------------------------------------
for p in orchis-theme tela-icon-theme bibata-cursor-theme-bin gnome-shell-extension-appindicator; do
  ! list pacman.txt | grep -qx "$p" && ! list aur.txt | grep -qx "$p" || fail "$p must be removed from the package lists"
done
for p in sassc imagemagick python-pillow; do
  ! list pacman.txt | grep -qx "$p" || fail "$p was Aura-only — remove from pacman.txt"
done
[[ ! -e $ROOT/scripts/gdm-shell-theme.sh ]] || fail "gdm-shell-theme.sh must be removed"
_old="$(grep -rlI -e 'Orchis' -e 'Tela-blue' -e 'Bibata' -e 'gdm-shell-theme' \
  "$ROOT/gnome" "$ROOT/stow" "$ROOT/scripts" "$ROOT/install.sh" "$ROOT/packages" 2>/dev/null \
  | grep -v '/scripts/theme-setup.sh$' || true)"
[[ -z $_old ]] || fail "old theme still referenced in: $_old"
! grep -q 'AURA_GLASS_COMMIT\|aura-glass.git\|install.sh --full' "$TS" \
  || fail "theme-setup.sh must not install Aura Glass"
grep -q 'Adwaita' "$TS" || fail "theme-setup.sh must apply Adwaita"

# --- Full pack is fetched + listed (not Aura-built) ---------------------------
grep -q 'install_ego_zip "blur-my-shell@aunetx"' "$ROOT/scripts/fetch-gnome-extensions.sh" \
  || fail "fetch-gnome-extensions must fetch Blur My Shell from EGO"
for u in blur-my-shell@aunetx custom-osd@neuromorph status-tray@keithvassallo.com \
         tiling-assistant@leleat-on-github hotedge@jonathan.jdoda.ca kiwimenu@kemma \
         copyous@boerdereinar.dev wiggly@mojarch restartto@tiagoporsch.github.io; do
  grep -qx "$u" "$EXT" || fail "extensions.txt must list $u"
done
! grep -qx 'aura-glass-blur@aura-glass.local' "$EXT" \
  || fail "extensions.txt must not list the Aura helper"

# --- repo dconf ---------------------------------------------------------------
U="$ROOT/gnome/dconf/user.conf"; G="$ROOT/stow/gdm/etc/dconf/db/gdm.d/00-login-screen"
for k in gtk-theme icon-theme cursor-theme cursor-size; do
  ! grep -q "^$k=" "$U" || fail "user.conf must not set $k (theme-setup / defaults own it)"
  ! grep -q "^$k=" "$G" || fail "GDM greeter must not set $k"
done
for s in user-theme blur-my-shell; do
  ! grep -q "^\[org/gnome/shell/extensions/$s" "$U" "$ROOT/gnome/dconf/extensions.conf" \
    || fail "repo dconf must not carry the $s tree"
done
_en="$(grep '^enabled-extensions=' "$U")"
[[ $_en != *aura-glass-blur@aura-glass.local* ]] \
  || fail "user.conf must not enable aura-glass-blur"
for u in user-theme@gnome-shell-extensions.gcampax.github.com \
         blur-my-shell@aunetx custom-osd@neuromorph status-tray@keithvassallo.com \
         tiling-assistant@leleat-on-github hotedge@jonathan.jdoda.ca kiwimenu@kemma \
         copyous@boerdereinar.dev wiggly@mojarch restartto@tiagoporsch.github.io; do
  [[ $_en == *"'$u'"* ]] || fail "user.conf enabled-extensions must keep $u on"
done
for u in appindicatorsupport@rgcjonas.gmail.com gnome-clipboard@b00f.github.io; do
  [[ $_en != *"'$u'"* ]] || fail "user.conf must not enable $u"
  ! grep -qx "$u" "$EXT" || fail "extensions.txt must not list $u"
done
grep -q 'run_step "Theme setup" bash scripts/theme-setup.sh' "$ROOT/install.sh" || fail "install.sh must run theme-setup.sh"

# backup-gsettings.sh keeps theme keys and look trees out of snapshots.
mkdir -p "$T/bbin"
cat >"$T/bbin/dconf" <<'EOF'
#!/bin/sh
cat <<'D'
[org/gnome/desktop/interface]
gtk-theme='Aura-Glass'
icon-theme='Colloid-Dark'
cursor-theme='Adwaita'
cursor-size=32
accent-color='blue'

[org/gnome/shell/extensions/blur-my-shell/panel]
blur=true

[org/gnome/shell/extensions/user-theme]
name='Aura-Glass'

[org/gnome/shell/extensions/blur-my-shell-notes]
kept=true
D
EOF
chmod +x "$T/bbin/dconf"
PATH="$T/bbin:$PATH" GSETTINGS_OUT="$T/snap.conf" bash "$ROOT/scripts/backup-gsettings.sh" >/dev/null \
  || fail "backup-gsettings failed"
grep -q "^accent-color='blue'" "$T/snap.conf" || fail "snapshot must keep accent-color"
grep -qE '^(gtk-theme|icon-theme|cursor-theme|cursor-size)=' "$T/snap.conf" && fail "snapshot must drop theme interface keys"
grep -q '^\[org/gnome/shell/extensions/\(blur-my-shell/panel\|user-theme\)\]' "$T/snap.conf" \
  && fail "snapshot must drop look trees: $(cat "$T/snap.conf")"
grep -q '^\[org/gnome/shell/extensions/blur-my-shell-notes\]' "$T/snap.conf" \
  || fail "only whole trees are dropped, not names that merely start alike"

# --- theme-setup.sh with stubs --------------------------------------------------
H="$T/home"; B="$T/bin"
mkdir -p "$B" "$H/.config/gtk-4.0" "$H/.config/systemd/user/default.target.wants" \
  "$H/.config/aura-glass" "$H/.themes/Aura-Glass" \
  "$H/.local/share/themes/Aura-Glass" \
  "$H/.local/share/themes/Orchis-Dark/gtk-4.0" "$H/.local/share/dotfiles" \
  "$H/.local/share/gnome-shell/extensions/aura-glass-blur@aura-glass.local" \
  "$H/.cache/aura-glass" "$H/.cache/dotfiles/aura-glass" \
  "$H/.local/share/icons/Colloid-Dark" \
  "$H/.local/share/flatpak/overrides" "$T/etc/dconf/db/gdm.d"
: >"$T/etc/dconf/db/gdm.d/90-aura-glass"
printf '%s\n' '[Context]' \
  'filesystems=xdg-run/pipewire-0:ro;xdg-config/gtk-3.0:ro;xdg-data/themes:ro;' \
  >"$H/.local/share/flatpak/overrides/global"
# Stub uninstall.sh: accept only -y --gdm (order-independent); never --extensions.
cat >"$H/.cache/dotfiles/aura-glass/uninstall.sh" <<EOF
#!/bin/bash
echo "uninstall \$*" >>"$T/uninstall.log"
ext=0; gdm=0; yes=0
for a in "\$@"; do
  case \$a in
    --extensions|--all|--assets|--full) ext=1 ;;
    --gdm) gdm=1 ;;
    -y|--yes) yes=1 ;;
  esac
done
[[ \$ext -eq 0 && \$gdm -eq 1 && \$yes -eq 1 ]] || { echo "bad flags: \$*" >&2; exit 2; }
exit 0
EOF
chmod +x "$H/.cache/dotfiles/aura-glass/uninstall.sh"
: >"$T/gsettings.log"
: >"$T/order.log"
cat >"$B/gsettings" <<EOF
#!/bin/bash
echo "gsettings \$*" >>"$T/gsettings.log"
case \$1 in
  get)
    case \$* in
      *gtk-theme*) echo "'\${GTK_THEME_GET-Adwaita}'" ;;
      *icon-theme*) echo "'\${ICON_THEME_GET-Adwaita}'" ;;
      *cursor-theme*) echo "'\${CURSOR_THEME_GET-Adwaita}'" ;;
      *user-theme*name*) echo "'\${USER_THEME_GET-}'" ;;
      *enabled-extensions*|*disabled-extensions*) echo "['aura-glass-blur@aura-glass.local', 'blur-my-shell@aunetx']" ;;
      *app-picker-layout*) echo "[{'io.github.DevWebeloper.AuraGlassSettings.desktop': <{'position': <0>}>}]" ;;
      *) echo "''" ;;
    esac
    exit 0
    ;;
  set)
    case \$* in
      *disabled-extensions*) echo set-disabled >>"$T/order.log" ;;
    esac
    exit 0
    ;;
  reset) exit 0 ;;
  list-schemas) echo org.gnome.shell.extensions.user-theme; exit 0 ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo.log"\nexec "$@"\n' "$T" >"$B/sudo"
printf '#!/bin/sh\nexit 1\n' >"$B/pacman"
printf '#!/bin/sh\nexit 0\n' >"$B/systemctl"
printf '#!/bin/sh\necho "gnome-extensions $*" >>"%s/ext.log"\n[ "$1" = disable ] && echo disable >>"%s/order.log"\nexit 0\n' "$T" "$T" >"$B/gnome-extensions"
printf '#!/bin/sh\necho "revert $*" >>"%s/old-gdm.log"\nrm -f "%s/old-hook" "$0"\n' "$T" "$T" >"$T/old-gdm"
chmod +x "$B/"* "$T/old-gdm"
: >"$T/old-hook"
printf '[Unit]\n' >"$H/.config/systemd/user/theme-sync.service"
ln -s ../theme-sync.service "$H/.config/systemd/user/default.target.wants/theme-sync.service"
: >"$H/.local/share/dotfiles/theme-setup.sh"
for f in gtk.css assets; do ln -s "$H/.local/share/themes/Orchis-Dark/gtk-4.0/$f" "$H/.config/gtk-4.0/$f"; done
echo 'mine' >"$H/.config/gtk-4.0/gtk-dark.css"
run_ts() { HOME="$H" XDG_CACHE_HOME="" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_RUNTIME_DIR="$T/none" \
  DBUS_SESSION_BUS_ADDRESS="${TS_BUS-unix:path=/fake}" THEME_OLD_GDM_BIN="$T/old-gdm" THEME_OLD_GDM_HOOK="$T/old-hook" \
  THEME_AURA_GDM_DCONF="$T/etc/dconf/db/gdm.d/90-aura-glass" \
  PATH="$B:$PATH" bash "$TS" "$@"; }

rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'old Orchis GDM hook'* ]] \
  || fail "--check must flag the old hook even before Adwaita (rc=$rc): $out"

if TS_BUS="" run_ts >"$T/out" 2>&1; then fail "no session bus must fail"; fi
grep -q 'no session D-Bus' "$T/out" || fail "no bus: must say why: $(cat "$T/out")"
[[ -e $T/old-hook && -d $H/.themes/Aura-Glass && -d $H/.config/aura-glass ]] \
  || fail "no bus: leftovers must be left untouched"
[[ ! -e $T/sudo.log && ! -s $T/gsettings.log ]] || fail "no bus: nothing may run (sudo/gsettings)"

: >"$T/gsettings.log"; : >"$T/order.log"; : >"$T/uninstall.log"
run_ts >"$T/out" 2>&1 || fail "theme-setup.sh failed: $(cat "$T/out")"
grep -qx "sudo $T/old-gdm revert" "$T/sudo.log" || fail "must revert the old Orchis greeter as root"
[[ ! -e $T/old-hook ]] || fail "old GDM pacman hook must be gone"
[[ ! -e $H/.config/systemd/user/theme-sync.service ]] || fail "theme-sync.service must be removed"
[[ ! -e $H/.local/share/dotfiles ]] || fail "the old sync copy must be removed"
[[ ! -e $H/.local/share/themes/Orchis-Dark ]] || fail "the Orchis user copy must be removed"
[[ ! -L $H/.config/gtk-4.0/gtk.css ]] || fail "links into Orchis must be removed"
[[ $(cat "$H/.config/gtk-4.0/gtk-dark.css") == mine ]] || fail "a real user gtk-dark.css must be kept"
[[ ! -d $H/.config/aura-glass ]] || fail "Aura Glass config dir must be removed"
[[ ! -d $H/.themes/Aura-Glass && ! -d $H/.local/share/themes/Aura-Glass ]] \
  || fail "Aura-Glass theme directories must be removed"
[[ ! -d $H/.local/share/gnome-shell/extensions/aura-glass-blur@aura-glass.local ]] \
  || fail "Aura helper extension must be removed"
grep -q 'uninstall -y --gdm' "$T/uninstall.log" \
  || fail "must run uninstall.sh -y --gdm: $(cat "$T/uninstall.log")"
! grep -qE -- '--extensions|--all|--assets|--full' "$T/uninstall.log" \
  || fail "uninstall must not remove extensions: $(cat "$T/uninstall.log")"
grep -qx "sudo rm -f $T/etc/dconf/db/gdm.d/90-aura-glass" "$T/sudo.log" \
  || fail "must remove orphaned Aura GDM dconf: $(cat "$T/sudo.log")"
[[ ! -e $T/etc/dconf/db/gdm.d/90-aura-glass ]] || fail "Aura GDM dconf must be gone"
_fp="$H/.local/share/flatpak/overrides/global"
[[ -f $_fp ]] || fail "Flatpak global override must remain when non-Aura entries exist"
grep -qx 'filesystems=xdg-run/pipewire-0:ro;' "$_fp" \
  || fail "must keep non-Aura Flatpak mounts with trailing ';': $(cat "$_fp")"
! grep -qE 'gtk-[34]|xdg-data/(icons|themes)' "$_fp" \
  || fail "Aura Flatpak mounts must be stripped: $(cat "$_fp")"
# disable before stripping disabled-extensions (disable alone would re-add the UUID).
[[ "$(cat "$T/order.log")" == $'disable\nset-disabled' ]] \
  || fail "gnome-extensions disable must run before stripping disabled-extensions: $(cat "$T/order.log")"
grep -q "gsettings reset org.gnome.desktop.interface gtk-theme" "$T/gsettings.log" \
  || fail "must reset gtk-theme: $(cat "$T/gsettings.log")"
grep -q "gsettings reset org.gnome.desktop.interface icon-theme" "$T/gsettings.log" \
  || fail "must reset icon-theme"
grep -qE "gsettings (reset|set) org.gnome.shell.extensions.user-theme name" "$T/gsettings.log" \
  || fail "must reset/clear user-theme name"
! grep -q "color-scheme\|accent-color" "$T/gsettings.log" \
  || fail "must not reset color-scheme/accent-color (user.conf owns them): $(cat "$T/gsettings.log")"
grep -q "disabled-extensions" "$T/gsettings.log" \
  || fail "must strip Aura helper from disabled-extensions"
[[ ! -d $H/.cache/aura-glass && ! -d $H/.cache/dotfiles/aura-glass ]] \
  || fail "Aura cache dirs must be removed"
[[ ! -d $H/.local/share/icons/Colloid-Dark ]] || fail "Colloid icons must be removed"
! grep -qiE 'aura-glass\.git|install\.sh --full|AURA_GLASS_COMMIT' "$T/out" \
  || fail "run must not install Aura Glass: $(cat "$T/out")"
run_ts --check >/dev/null || fail "--check must pass right after setup"

: >"$T/sudo.log"; : >"$T/gsettings.log"
run_ts >/dev/null 2>&1 || fail "theme-setup.sh must be re-runnable"
[[ ! -s $T/sudo.log ]] || fail "re-run must not revert again: $(cat "$T/sudo.log")"
grep -q "reset org.gnome.desktop.interface gtk-theme" "$T/gsettings.log" || fail "re-run must still reset gtk-theme"

# --check failures
rc=0; out="$(GTK_THEME_GET= run_ts --check)" || rc=$?
[[ $rc -eq 2 && $out == *'could not read gtk-theme'* ]] \
  || fail "--check empty gtk-theme must be not-applied (rc=2), not broken (rc=$rc): $out"
rc=0; out="$(GTK_THEME_GET=Aura-Glass run_ts --check)" || rc=$?
[[ $rc -eq 2 && $out == *Aura-Glass* ]] || fail "--check must report non-Adwaita gtk (rc=$rc): $out"
rc=0; out="$(ICON_THEME_GET=Colloid-Dark run_ts --check)" || rc=$?
[[ $rc -eq 2 && $out == *icon-theme* ]] || fail "--check must report non-Adwaita icons (rc=$rc): $out"
rc=0; out="$(USER_THEME_GET=Aura-Glass run_ts --check)" || rc=$?
[[ $rc -eq 2 && $out == *user-theme* ]] || fail "--check must report user-theme name (rc=$rc): $out"
mkdir -p "$H/.config/aura-glass"
rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'Aura Glass leftovers'* ]] || fail "--check must flag aura leftovers (rc=$rc): $out"
rm -rf "$H/.config/aura-glass"
mkdir -p "$H/.themes/Aura-Glass"
rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'Aura Glass leftovers'* ]] || fail "--check must flag theme dir (rc=$rc): $out"
rm -rf "$H/.themes/Aura-Glass"
mkdir -p "$H/.cache/dotfiles/aura-glass"
rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'Aura Glass leftovers'* ]] || fail "--check must flag Aura cache (rc=$rc): $out"
rm -rf "$H/.cache/dotfiles/aura-glass"
: >"$T/old-hook"
rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'old Orchis GDM hook'* ]] || fail "--check must flag the old hook (rc=$rc): $out"
: >"$T/old-hook"; : >"$T/sudo.log"
run_ts >/dev/null 2>&1 || fail "run with an orphaned old hook failed"
grep -qx "sudo rm -f $T/old-hook" "$T/sudo.log" && [[ ! -e $T/old-hook ]] \
  || fail "an orphaned old GDM hook must be removed as root: $(cat "$T/sudo.log")"
run_ts --check >/dev/null || fail "--check must pass once the orphaned hook is gone"

echo "PASS: theme.test.sh"
