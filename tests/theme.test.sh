#!/usr/bin/env bash
# Theme: Aura Glass from a pinned commit (scripts/theme-setup.sh), the old
# Orchis/Tela/Bibata setup removed, and the repo's dconf leaving Aura Glass's
# keys alone. git, sudo and the Aura Glass installer are stubs: no network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$ROOT/packages/$1"; }
TS="$ROOT/scripts/theme-setup.sh"

# --- old theme gone everywhere ------------------------------------------------
for p in orchis-theme tela-icon-theme bibata-cursor-theme-bin gnome-shell-extension-appindicator; do
  ! list pacman.txt | grep -qx "$p" && ! list aur.txt | grep -qx "$p" || fail "$p must be removed from the package lists"
done
[[ ! -e $ROOT/scripts/gdm-shell-theme.sh ]] || fail "gdm-shell-theme.sh must be removed (Aura Glass themes GDM)"
_old="$(grep -rlI -e 'Orchis' -e 'Tela-blue' -e 'Bibata' -e 'gdm-shell-theme' \
  "$ROOT/gnome" "$ROOT/stow" "$ROOT/scripts" "$ROOT/install.sh" "$ROOT/packages" 2>/dev/null \
  | grep -v '/scripts/theme-setup.sh$' || true)"
[[ -z $_old ]] || fail "old theme still referenced in: $_old"
# Aura Glass's build/runtime dependencies are pacman packages.
for p in sassc gettext libxml2 unzip python-gobject python-cairo libadwaita libgda6 imagemagick python-pillow; do
  list pacman.txt | grep -qx "$p" || fail "pacman.txt must include $p (Aura Glass dependency)"
done

# --- repo dconf does not fight Aura Glass ---------------------------------------
U="$ROOT/gnome/dconf/user.conf"; G="$ROOT/stow/gdm/etc/dconf/db/gdm.d/00-login-screen"
for k in gtk-theme icon-theme cursor-theme cursor-size; do
  ! grep -q "^$k=" "$U" || fail "user.conf must not set $k (Aura Glass owns it)"
  ! grep -q "^$k=" "$G" || fail "GDM greeter must not set $k (Aura Glass's 90-aura-glass owns it)"
done
for s in user-theme blur-my-shell; do
  ! grep -q "^\[org/gnome/shell/extensions/$s" "$U" "$ROOT/gnome/dconf/extensions.conf" \
    || fail "repo dconf must not carry the $s tree (Aura Glass writes it)"
done
_en="$(grep '^enabled-extensions=' "$U")"
for u in user-theme@gnome-shell-extensions.gcampax.github.com aura-glass-blur@aura-glass.local \
         blur-my-shell@aunetx custom-osd@neuromorph status-tray@keithvassallo.com \
         tiling-assistant@leleat-on-github hotedge@jonathan.jdoda.ca kiwimenu@kemma \
         copyous@boerdereinar.dev wiggly@mojarch restartto@tiagoporsch.github.io; do
  [[ $_en == *"'$u'"* ]] || fail "user.conf enabled-extensions must keep Aura Glass's $u on (a restore would disable it)"
done
for u in appindicatorsupport@rgcjonas.gmail.com gnome-clipboard@b00f.github.io; do
  [[ $_en != *"'$u'"* ]] || fail "user.conf must not enable $u (replaced by the Full pack)"
  ! grep -qx "$u" "$ROOT/gnome/extensions.txt" || fail "extensions.txt must not list $u"
done
! grep -qx 'blur-my-shell@aunetx' "$ROOT/gnome/extensions.txt" \
  || fail "extensions.txt must not list Blur My Shell (Aura Glass builds its own)"
grep -q 'run_step "Theme setup" bash scripts/theme-setup.sh' "$ROOT/install.sh" || fail "install.sh must run theme-setup.sh"

# backup-gsettings.sh keeps the Aura Glass keys and trees out of snapshots.
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
grep -qE '^(gtk-theme|icon-theme|cursor-theme|cursor-size)=' "$T/snap.conf" && fail "snapshot must drop Aura Glass interface keys"
grep -q '^\[org/gnome/shell/extensions/\(blur-my-shell/panel\|user-theme\)\]' "$T/snap.conf" \
  && fail "snapshot must drop Aura Glass trees: $(cat "$T/snap.conf")"
grep -q '^\[org/gnome/shell/extensions/blur-my-shell-notes\]' "$T/snap.conf" \
  || fail "only whole trees are dropped, not names that merely start alike"

# --- theme-setup.sh with stubs --------------------------------------------------
PIN="$(sed -n 's/^AURA_GLASS_COMMIT="\([0-9a-f]\{40\}\)"$/\1/p' "$TS")"
[[ -n $PIN ]] || fail "theme-setup.sh must pin a full 40-hex AURA_GLASS_COMMIT"
H="$T/home"; B="$T/bin"
mkdir -p "$B" "$H/.config/gtk-4.0" "$H/.config/systemd/user/default.target.wants" \
  "$H/.local/share/themes/Orchis-Dark/gtk-4.0" "$H/.local/share/dotfiles"
# git stub: a checkout of FETCH_HEAD becomes a fake aura-glass tree at $GIT_HEAD.
cat >"$B/git" <<EOF
#!/bin/bash
[ "\$1" = -C ] && { d=\$2; shift 2; }
echo "git \$*" >>"$T/git.log"
case \$1 in
  init) mkdir -p "\$d/.git" ;;
  fetch) [ "\${GIT_FETCH_FAIL:-0}" = 1 ] && exit 1; : ;;
  checkout) cat >"\$d/install.sh" <<'A'
echo "aura \$*" >>"$T/aura.log"
[ "\$1" = --verify ] && exit "\${AURA_VERIFY_RC:-0}"
mkdir -p "\$HOME/.config/aura-glass"
A
            ;;
  rev-parse) echo "\${GIT_HEAD:-$PIN}" ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo.log"\nexec "$@"\n' "$T" >"$B/sudo"
printf '#!/bin/sh\nexit 1\n' >"$B/pacman"
printf '#!/bin/sh\nexit 0\n' >"$B/systemctl"
# Old Orchis greeter: the root-owned copy whose revert removes the hook.
printf '#!/bin/sh\necho "revert $*" >>"%s/old-gdm.log"\nrm -f "%s/old-hook" "$0"\n' "$T" "$T" >"$T/old-gdm"
chmod +x "$B/"* "$T/old-gdm"
: >"$T/old-hook"
# Old user-side leftovers: theme-sync unit, sync copy, Orchis copy and links; a real user file.
printf '[Unit]\n' >"$H/.config/systemd/user/theme-sync.service"
ln -s ../theme-sync.service "$H/.config/systemd/user/default.target.wants/theme-sync.service"
: >"$H/.local/share/dotfiles/theme-setup.sh"
for f in gtk.css assets; do ln -s "$H/.local/share/themes/Orchis-Dark/gtk-4.0/$f" "$H/.config/gtk-4.0/$f"; done
echo 'mine' >"$H/.config/gtk-4.0/gtk-dark.css"
run_ts() { HOME="$H" XDG_CACHE_HOME="" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_RUNTIME_DIR="$T/none" \
  DBUS_SESSION_BUS_ADDRESS="${TS_BUS-unix:path=/fake}" THEME_OLD_GDM_BIN="$T/old-gdm" THEME_OLD_GDM_HOOK="$T/old-hook" \
  PATH="$B:$PATH" bash "$TS" "$@"; }

rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'old Orchis GDM hook'* ]] \
  || fail "--check must flag the old hook even before Aura Glass is set up (rc=$rc): $out"
# No session bus: refused before anything old is removed (SSH / TTY run).
if TS_BUS="" run_ts >"$T/out" 2>&1; then fail "no session bus must fail"; fi
grep -q 'no session D-Bus' "$T/out" || fail "no bus: must say why: $(cat "$T/out")"
[[ -e $T/old-hook && -x $T/old-gdm && -e $H/.config/systemd/user/theme-sync.service \
   && -d $H/.local/share/themes/Orchis-Dark && -L $H/.config/gtk-4.0/gtk.css ]] \
  || fail "no bus: the old theme must be left untouched"
[[ ! -e $T/sudo.log && ! -e $T/git.log ]] || fail "no bus: nothing may run (sudo/git)"
run_ts >"$T/out" 2>&1 || fail "theme-setup.sh failed: $(cat "$T/out")"
grep -qx "git fetch -q --depth 1 origin $PIN" "$T/git.log" || fail "must fetch exactly the pinned commit: $(cat "$T/git.log")"
grep -qx "aura --full --accent blue --no-update-check -y --gdm" "$T/aura.log" \
  || fail "first install must run Aura Glass with the Full pack + GDM: $(cat "$T/aura.log")"
grep -qx "sudo $T/old-gdm revert" "$T/sudo.log" || fail "must revert the old Orchis greeter as root"
[[ ! -e $T/old-hook ]] || fail "old GDM pacman hook must be gone"
[[ ! -e $H/.config/systemd/user/theme-sync.service && ! -L $H/.config/systemd/user/default.target.wants/theme-sync.service ]] \
  || fail "theme-sync.service and its enable link must be removed"
[[ ! -e $H/.local/share/dotfiles ]] || fail "the old sync copy (and its empty dir) must be removed"
[[ ! -e $H/.local/share/themes/Orchis-Dark ]] || fail "the Orchis user copy must be removed"
[[ ! -L $H/.config/gtk-4.0/gtk.css && ! -L $H/.config/gtk-4.0/assets ]] || fail "links into Orchis must be removed"
[[ $(cat "$H/.config/gtk-4.0/gtk-dark.css") == mine ]] || fail "a real user gtk-dark.css must be kept"
run_ts --check >/dev/null || fail "--check must pass right after setup"

# Re-run: nothing old left, so no second revert; installer runs again.
: >"$T/sudo.log"; : >"$T/aura.log"
run_ts >/dev/null 2>&1 || fail "theme-setup.sh must be re-runnable"
[[ ! -s $T/sudo.log ]] || fail "re-run must not revert again: $(cat "$T/sudo.log")"
grep -qx 'aura -y' "$T/aura.log" \
  || fail "re-run must keep the settings app's choices (only -y): $(cat "$T/aura.log")"
: >"$T/aura.log"
SKIP_AURA_GDM=1 run_ts >/dev/null 2>&1 || fail "SKIP_AURA_GDM=1 run failed"
grep -qx "aura -y --no-gdm" "$T/aura.log" || fail "SKIP_AURA_GDM=1 must pass --no-gdm: $(cat "$T/aura.log")"

# --check failures: verify fails, checkout off the pin, old hook back.
rc=0; out="$(AURA_VERIFY_RC=1 run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'--verify failed'* ]] || fail "--check must report a failed --verify (rc=$rc): $out"
rc=0; out="$(GIT_HEAD=deadbeef run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'not at'* ]] || fail "--check must flag a checkout off the pin (rc=$rc): $out"
: >"$T/old-hook"
rc=0; out="$(run_ts --check)" || rc=$?
[[ $rc -eq 1 && $out == *'old Orchis GDM hook'* ]] || fail "--check must flag the old hook (rc=$rc): $out"
rm -f "$T/old-hook"

# First install with SKIP_AURA_GDM=1: --no-gdm only (not --gdm as well).
mv "$H/.config/aura-glass" "$T/aura-conf"; : >"$T/aura.log"
SKIP_AURA_GDM=1 run_ts >/dev/null 2>&1 || fail "first install with SKIP_AURA_GDM=1 failed"
grep -qx "aura --full --accent blue --no-update-check -y --no-gdm" "$T/aura.log" \
  || fail "first install with SKIP_AURA_GDM=1 must pass only --no-gdm: $(cat "$T/aura.log")"

# Refusals: a checkout off the pin, a failed fetch — the installer never runs.
for c in "GIT_HEAD=deadbeef" "GIT_FETCH_FAIL=1"; do
  : >"$T/aura.log"
  if env "$c" bash -c "$(declare -f run_ts); H='$H' B='$B' T='$T' TS='$TS'; run_ts" >"$T/out" 2>&1; then
    fail "$c must make theme-setup.sh fail"
  fi
  [[ ! -s $T/aura.log ]] || fail "$c: the Aura Glass installer must not run: $(cat "$T/aura.log")"
done

echo "PASS: theme.test.sh"
