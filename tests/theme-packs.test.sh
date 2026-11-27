#!/usr/bin/env bash
# theme-packs.test.sh — offline unit tests for desktop/scripts/theme-packs.sh (CLI + zenity GUI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/desktop/scripts/theme-packs.sh"
DESK="$ROOT/stow/applications/.local/share/applications/dotfiles-themes.desktop"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "$SCRIPT" ]] || fail "theme-packs.sh must be executable"
bash -n "$SCRIPT" || fail "bash -n theme-packs.sh"
[[ -f "$DESK" ]] || fail "missing dotfiles-themes.desktop"
grep -q 'desktop/scripts/theme-packs.sh --gui' "$DESK" \
    || fail "dotfiles-themes.desktop must launch theme-packs.sh --gui"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESK" 2>&1 | grep -v ' hint: ' | grep -q . \
        && fail "desktop-file-validate dotfiles-themes.desktop failed"
fi

# CLI help, list, and invalid args
help_out="$("$SCRIPT" --help)"
grep -q -- '--install PACK' <<<"$help_out" || fail "--help must document --install"
list_out="$("$SCRIPT" --list)"
for _p in mactahoe kayozxo-tahoe whitesur colloid graphite fluent flat-remix material-gnome modular-adwaita modular-gruvbox gse-gdm gdm-settings; do
    grep -q "^${_p} " <<<"$list_out" || fail "--list missing pack: $_p"
done
unset _p help_out list_out
rc=0; "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown flag must exit 2 (got $rc)"
rc=0; "$SCRIPT" --install nonexistent >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown pack must exit 2 (got $rc)"
rc=0; "$SCRIPT" --color neon >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "invalid color must exit 2 (got $rc)"

# Isolated fake environment + stubbed external tools
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
H="$T/home"
B="$T/bin"
LOG="$T/cmd.log"
CACHE="$H/.local/share/dotfiles/theme-packs"
mkdir -p "$H/.local/share/icons" "$H/.local/share/themes" "$H/.config/gtk-4.0" "$B"
: >"$LOG"

# Stub build-tool deps (sassc, glib-compile-resources, magick, zip, unzip, dconf, glib-compile-schemas)
for _dep in sassc glib-compile-resources magick zip unzip dconf glib-compile-schemas; do
    printf '#!/bin/sh\nexit 0\n' >"$B/$_dep"
done
printf '#!/bin/sh\necho "make \$*" >>"%s"\nexit 0\n' "$LOG" >"$B/make"
unset _dep

# Stub git: handles pinned init/remote/fetch/checkout/rev-parse and creates fake upstream repos
cat >"$B/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >>"$LOG"
dest=""
if [[ \${1:-} == -C ]]; then
    dest="\$2"
    shift 2
fi
case "\${1:-}" in
    init)
        mkdir -p "\$dest/.git"
        exit 0
        ;;
    remote)
        exit 0
        ;;
    rev-parse)
        if [[ -f "\$dest/.git/FAKE_HEAD" ]]; then
            cat "\$dest/.git/FAKE_HEAD"
            exit 0
        fi
        exit 1
        ;;
    checkout)
        if [[ -f "\$dest/.git/FAKE_FETCH_HEAD" ]]; then
            cp "\$dest/.git/FAKE_FETCH_HEAD" "\$dest/.git/FAKE_HEAD"
        fi
        exit 0
        ;;
    fetch)
        pin="\${@: -1}"
        mkdir -p "\$dest/.git"
        if [[ \${FAKE_GIT_BAD_HEAD:-0} == 1 ]]; then
            printf '0000000000000000000000000000000000000000\n' >"\$dest/.git/FAKE_FETCH_HEAD"
        else
            printf '%s\n' "\$pin" >"\$dest/.git/FAKE_FETCH_HEAD"
        fi
        ;;
    *)
        exit 0
        ;;
esac
if [[ \${1:-} == fetch ]]; then
    case "\$dest" in
        *MacTahoe-gtk-theme|*WhiteSur-gtk-theme)
            printf '#!/bin/sh\necho "gtk-install \$(basename "\$PWD") \$*" >>"%s"\n' "$LOG" >"\$dest/install.sh"
            printf '#!/bin/sh\necho "gtk-tweaks \$(basename "\$PWD") \$*" >>"%s"\n' "$LOG" >"\$dest/tweaks.sh"
            chmod +x "\$dest/install.sh" "\$dest/tweaks.sh"
            ;;
        *GNOME-macOS-Tahoe)
            cat >"\$dest/install.sh" <<'KT'
#!/usr/bin/env bash
for a in "\$@"; do
    case "\$a" in
        -d|-l|-la|-u) ;;
        *) echo "GNOME-macOS-Tahoe unexpected flag: \$a" >&2; exit 2 ;;
    esac
done
echo "kayozxo-tahoe \$*" >>"$LOG"
if [[ " \$* " != *" -u "* ]]; then
    mkdir -p "\$HOME/.local/share/themes/Tahoe-Dark"
fi
KT
            chmod +x "\$dest/install.sh"
            ;;
        *flat-remix-gnome)
            mkdir -p "\$dest/themes/Flat-Remix-Dark"
            printf 'all:\ninstall:\nuninstall:\n' >"\$dest/Makefile"
            ;;
        *flat-remix-gtk)
            mkdir -p "\$dest/Flat-Remix-GTK-Blue-Dark"
            ;;
        *flat-remix)
            mkdir -p "\$dest/Flat-Remix-Blue-Dark"
            ;;
        *Fluent-gtk-theme)
            # Fluent uses -u (not -r) for uninstall
            cat >"\$dest/install.sh" <<'FL'
#!/usr/bin/env bash
for a in "\$@"; do
    [[ \$a == -r ]] && { echo "Fluent-gtk-theme does not accept -r" >&2; exit 2; }
done
echo "gtk-install \$(basename "\$PWD") \$*" >>"$LOG"
FL
            chmod +x "\$dest/install.sh"
            ;;
        *Colloid-gtk-theme|*Graphite-gtk-theme|*material-gnome-theme)
            printf '#!/bin/sh\necho "gtk-install \$(basename "\$PWD") \$*" >>"%s"\n' "$LOG" >"\$dest/install.sh"
            chmod +x "\$dest/install.sh"
            ;;
        *Fluent-icon-theme)
            # Fluent-icon-theme has no -r/-u flag
            mkdir -p "\$dest/cursors"
            cat >"\$dest/install.sh" <<'FI'
#!/usr/bin/env bash
for a in "\$@"; do
    [[ \$a == -r || \$a == -u ]] && { echo "Fluent-icon-theme does not accept \$a" >&2; exit 2; }
done
echo "icon-install \$(basename "\$PWD") \$*" >>"$LOG"
FI
            printf '#!/bin/sh\necho "cursor-install \$(basename "\$(dirname "\$PWD")") \$*" >>"%s"\n' "$LOG" >"\$dest/cursors/install.sh"
            chmod +x "\$dest/install.sh" "\$dest/cursors/install.sh"
            ;;
        *MacTahoe-icon-theme|*Colloid-icon-theme)
            mkdir -p "\$dest/cursors"
            cat >"\$dest/install.sh" <<'IC'
#!/usr/bin/env bash
echo "icon-install \$(basename "\$PWD") \$*" >>"$LOG"
mkdir -p "\$HOME/.local/share/icons/\$(basename "\$PWD" -icon-theme)-dark"
IC
            printf '#!/bin/sh\necho "cursor-install \$(basename "\$(dirname "\$PWD")") \$*" >>"%s"\n' "$LOG" >"\$dest/cursors/install.sh"
            chmod +x "\$dest/install.sh" "\$dest/cursors/install.sh"
            ;;
        *WhiteSur-cursors)
            # WhiteSur-cursors has no -r flag
            cat >"\$dest/install.sh" <<'WC'
#!/usr/bin/env bash
for a in "\$@"; do
    [[ \$a == -r || \$a == -u ]] && { echo "WhiteSur-cursors does not accept \$a" >&2; exit 2; }
done
echo "asset-install \$(basename "\$PWD") \$*" >>"$LOG"
mkdir -p "\$HOME/.local/share/icons/WhiteSur-cursors"
WC
            chmod +x "\$dest/install.sh"
            ;;
        *WhiteSur-icon-theme|*MoreWaita|*material-bibata-cursor)
            printf '#!/bin/sh\necho "asset-install \$(basename "\$PWD") \$*" >>"%s"\n' "$LOG" >"\$dest/install.sh"
            chmod +x "\$dest/install.sh"
            ;;
        *gruvbox-plus-icon-pack)
            mkdir -p "\$dest/Gruvbox-Plus-Dark" "\$dest/Gruvbox-Plus-Light"
            ;;
        *Marble-shell-theme)
            printf '# stub\n' >"\$dest/install.py"
            ;;
        *gse-gdm-extension)
            printf '#!/bin/sh\necho "gse-install \$*" >>"%s"\n' "$LOG" >"\$dest/install.sh"
            printf '#!/bin/sh\necho "gse-uninstall \$*" >>"%s"\n' "$LOG" >"\$dest/uninstall.sh"
            chmod +x "\$dest/install.sh" "\$dest/uninstall.sh"
            ;;
    esac
fi
exit 0
EOF

cat >"$B/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >>"$LOG"
exec "\$@"
EOF

cat >"$B/python3" <<EOF
#!/usr/bin/env bash
echo "python3 \$*" >>"$LOG"
exit 0
EOF

cat >"$B/pacman" <<EOF
#!/usr/bin/env bash
echo "pacman \$*" >>"$LOG"
[[ \$1 == -Q ]] && exit 1
exit 0
EOF

cat >"$B/flatpak" <<EOF
#!/usr/bin/env bash
echo "flatpak \$*" >>"$LOG"
exit 0
EOF

cat >"$B/gsettings" <<EOF
#!/usr/bin/env bash
case \$1 in
    list-schemas) echo "org.gnome.shell.extensions.user-theme"; exit 0 ;;
    get) echo "'Adwaita'"; exit 0 ;;
    *) echo "gsettings \$*" >>"$LOG"; exit 0 ;;
esac
EOF

cat >"$B/zenity" <<'ZN'
#!/usr/bin/env bash
mode=""
for a in "$@"; do
    case $a in
        --checklist) mode=checklist ;;
        --radiolist) mode=radiolist ;;
        --info) exit 0 ;;
    esac
done
if [[ $mode == radiolist ]]; then
    q="$(head -1 "$ZN_QUEUE")"; sed -i 1d "$ZN_QUEUE"
    [[ -z $q || $q == quit || $q == CANCEL ]] && exit 1
    printf '%s\n' "$q"
    exit 0
fi
if [[ $mode == checklist ]]; then
    if [[ -n ${ZN_EXTRAS_FILE:-} && -s $ZN_EXTRAS_FILE ]]; then
        line="$(head -1 "$ZN_EXTRAS_FILE")"; sed -i 1d "$ZN_EXTRAS_FILE"
        [[ $line != NONE ]] && printf '%s\n' $line
    fi
    exit 0
fi
exit 0
ZN
chmod +x "$B/"*

# Fake repo copy so theme-setup.sh restore is recorded without touching host
FAKE_REPO="$T/repo"
mkdir -p "$FAKE_REPO/desktop/scripts" "$FAKE_REPO/provision/lib"
cp "$SCRIPT" "$FAKE_REPO/desktop/scripts/theme-packs.sh"
cp "$ROOT/provision/lib/ui-menu.sh" "$FAKE_REPO/provision/lib/ui-menu.sh"
printf '#!/bin/sh\necho "theme-setup-adwaita" >>"%s"\n' "$LOG" >"$FAKE_REPO/desktop/scripts/theme-setup.sh"
chmod +x "$FAKE_REPO/desktop/scripts/theme-setup.sh"

run_tp() {
    HOME="$H" XDG_DATA_HOME="$H/.local/share" XDG_CONFIG_HOME="$H/.config" \
        THEME_PACKS_DIR="$CACHE" DBUS_SESSION_BUS_ADDRESS="unix:path=/fake" \
        PATH="$B:$PATH" bash "$FAKE_REPO/desktop/scripts/theme-packs.sh" "$@"
}

# 0) Missing sassc fails fast BEFORE cloning
NO_SASSC="$T/no-sassc"
mkdir -p "$NO_SASSC"
for _cmd in bash env mkdir rm mktemp dirname basename cat grep sed printf date tr git; do
    _p="$(command -v "$_cmd" 2>/dev/null || true)"
    [[ -n $_p ]] && ln -sf "$_p" "$NO_SASSC/$_cmd"
done
rc=0
err_out="$(HOME="$H" XDG_DATA_HOME="$H/.local/share" XDG_CONFIG_HOME="$H/.config" \
    THEME_PACKS_DIR="$CACHE" PATH="$NO_SASSC" \
    bash "$FAKE_REPO/desktop/scripts/theme-packs.sh" --install mactahoe 2>&1)" || rc=$?
[[ $rc -ne 0 && $err_out == *"missing required command 'sassc'"* && ! -d "$CACHE" ]] \
    || fail "missing sassc must fail before cloning (rc=$rc out=$err_out)"
unset _cmd _p err_out

# 1) --dry-run mutates nothing and logs no real commands
dry_out="$(run_tp --dry-run --install mactahoe --gdm --firefox --flatpak)"
grep -qE '^\[dry-run\] git fetch --depth=1 https://github\.com/vinceliuice/MacTahoe-gtk-theme\.git [0-9a-f]{40} ' <<<"$dry_out" \
    || fail "--dry-run must preview pinned MacTahoe fetch"
grep -q 'GDM note (GNOME 51)' <<<"$dry_out" \
    || fail "--gdm must print GNOME 51 gresource warning"
[[ ! -s "$LOG" && ! -d "$CACHE" ]] || fail "--dry-run must not run commands or create cache"

# 1b) Non-TTY privileged GDM / gse-gdm / modular pacman / --uninstall all must fail closed without -y or -n
rc=0; run_tp --install mactahoe --gdm </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-TTY --install --gdm without -y must fail closed"
rc=0; run_tp --install gse-gdm </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-TTY --install gse-gdm without -y must fail closed"
rc=0; run_tp --install modular-adwaita </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-TTY --install modular-adwaita (needs pacman) without -y must fail closed"
rc=0; run_tp --uninstall all </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "non-TTY --uninstall all without -y must fail closed"
! grep -q 'sudo\|git fetch\|git clone' "$LOG" || fail "failed confirmation gates must not fetch or run sudo"

# 2) Install & uninstall MacTahoe with --gdm --firefox --flatpak; keep real user gtk.css
printf '/* user custom */\n' >"$H/.config/gtk-4.0/gtk.css"
mkdir -p "$H/.local/share/themes/MacTahoe-Dark/gtk-4.0"
: >"$H/.local/share/themes/MacTahoe-Dark/gtk-4.0/gtk-dark.css"
ln -sfn "$H/.local/share/themes/MacTahoe-Dark/gtk-4.0/gtk-dark.css" "$H/.config/gtk-4.0/gtk-dark.css"
mkdir -p "$H/.local/share/themes/OtherTheme/gtk-4.0/assets"
ln -sfn "$H/.local/share/themes/OtherTheme/gtk-4.0/assets" "$H/.config/gtk-4.0/assets"

: >"$LOG"
run_tp --install mactahoe --gdm --firefox --flatpak -y >/dev/null
[[ -f "$CACHE/.installed/mactahoe" ]] || fail "mactahoe state file must be written"
grep -q 'gtk-install MacTahoe-gtk-theme -c dark -l' "$LOG" || fail "mactahoe must install GTK/Libadwaita"
grep -q 'gtk-tweaks MacTahoe-gtk-theme -F' "$LOG" || fail "mactahoe --flatpak must invoke tweaks.sh -F"
grep -q 'gtk-tweaks MacTahoe-gtk-theme -f' "$LOG" || fail "mactahoe --firefox must invoke tweaks.sh -f"
grep -q 'sudo bash ./tweaks.sh -g' "$LOG" || fail "mactahoe --gdm must invoke sudo tweaks.sh -g"
grep -q 'icon-install MacTahoe-icon-theme' "$LOG" || fail "mactahoe must install icons"
grep -q 'cursor-install MacTahoe-icon-theme' "$LOG" || fail "mactahoe must install cursors"
grep -q 'gsettings set org.gnome.desktop.interface gtk-theme MacTahoe-Dark' "$LOG" || fail "mactahoe must set gtk-theme"
status_out="$(run_tp --status)"
grep -q 'Installed packs:  mactahoe' <<<"$status_out" || fail "--status must report mactahoe (got: $status_out)"

# Re-installing without --gdm/--firefox/--flatpak must preserve previously recorded 1 flags
run_tp --install mactahoe --color light >/dev/null
grep -qx 'gdm=1' "$CACHE/.installed/mactahoe" && grep -qx 'firefox=1' "$CACHE/.installed/mactahoe" && grep -qx 'flatpak=1' "$CACHE/.installed/mactahoe" \
    || fail "re-install without --gdm/--firefox/--flatpak must preserve recorded 1 flags"

: >"$LOG"
run_tp --uninstall mactahoe -y >/dev/null
[[ ! -e "$CACHE/.installed/mactahoe" && ! -d "$CACHE/mactahoe" ]] || fail "uninstall must remove state and cache"
grep -q 'gtk-install MacTahoe-gtk-theme -r' "$LOG" || fail "mactahoe uninstall must run install.sh -r"
grep -q 'sudo bash ./tweaks.sh -g -r' "$LOG" || fail "mactahoe uninstall must revert recorded GDM"
grep -q 'gtk-tweaks MacTahoe-gtk-theme -f -r' "$LOG" || fail "mactahoe uninstall must revert recorded Firefox"
grep -q 'gtk-tweaks MacTahoe-gtk-theme -F -r' "$LOG" || fail "mactahoe uninstall must revert recorded Flatpak"
grep -q 'theme-setup-adwaita' "$LOG" || fail "uninstalling last pack must restore stock Adwaita"
[[ -f "$H/.config/gtk-4.0/gtk.css" && $(cat "$H/.config/gtk-4.0/gtk.css") == '/* user custom */' ]] \
    || fail "uninstall must preserve real user gtk-4.0/gtk.css"
[[ ! -L "$H/.config/gtk-4.0/gtk-dark.css" ]] \
    || fail "uninstall must remove MacTahoe gtk-4.0 symlink"
[[ -L "$H/.config/gtk-4.0/assets" ]] \
    || fail "uninstall must preserve other theme gtk-4.0 symlink"
rm -f "$H/.config/gtk-4.0/gtk.css" "$H/.config/gtk-4.0/assets"

# 3) Fluent GDM uninstall must use -u -g (stub rejects -r); Colloid ignores --gdm in state
: >"$LOG"
run_tp --install fluent --gdm -y >/dev/null
run_tp --uninstall fluent -y >/dev/null
grep -q 'gtk-install Fluent-gtk-theme -u' "$LOG" || fail "fluent uninstall must use -u"
grep -q 'sudo bash ./install.sh -u -g' "$LOG" || fail "fluent GDM uninstall must use -u -g"

: >"$LOG"
run_tp --install colloid --gdm >/dev/null
grep -qx 'gdm=0' "$CACHE/.installed/colloid" || fail "colloid state must record gdm=0 when GDM unsupported"

# 4) Shared-asset preservation: colloid + graphite share Colloid-icon-theme
run_tp --install graphite >/dev/null
[[ -d "$H/.local/share/icons/Colloid-dark" ]] || fail "Colloid icons must be installed"
run_tp --uninstall colloid >/dev/null
[[ -d "$H/.local/share/icons/Colloid-dark" ]] || fail "uninstalling colloid while graphite installed must keep Colloid icons"
run_tp --uninstall graphite >/dev/null
[[ ! -d "$H/.local/share/icons/Colloid-dark" ]] || fail "uninstalling last Colloid-icon user must remove Colloid icons"

# 4b) Shared MacTahoe icons + theme-name collision guard (mactahoe + kayozxo-tahoe)
mkdir -p "$H/.local/share/themes/MacTahoe-Dark/gtk-4.0"
: >"$H/.local/share/themes/MacTahoe-Dark/gtk-4.0/gtk.css"
ln -sfn "$H/.local/share/themes/MacTahoe-Dark/gtk-4.0/gtk.css" "$H/.config/gtk-4.0/gtk.css"
: >"$LOG"
run_tp --install mactahoe >/dev/null
run_tp --install kayozxo-tahoe >/dev/null
grep -q 'gsettings set org.gnome.desktop.interface gtk-theme Tahoe-Dark' "$LOG" \
    || fail "kayozxo-tahoe must not collide with MacTahoe-Dark when detecting theme dir"
run_tp --uninstall kayozxo-tahoe >/dev/null
[[ -d "$H/.local/share/icons/MacTahoe-dark" ]] \
    || fail "uninstalling kayozxo-tahoe while mactahoe installed must keep MacTahoe icons"
[[ -L "$H/.config/gtk-4.0/gtk.css" ]] \
    || fail "uninstalling kayozxo-tahoe must keep MacTahoe gtk-4.0 symlink"
run_tp --uninstall mactahoe >/dev/null
[[ ! -d "$H/.local/share/icons/MacTahoe-dark" && ! -L "$H/.config/gtk-4.0/gtk.css" ]] \
    || fail "uninstalling last MacTahoe user must clean icons and gtk-4.0 symlink"

# 4c) flat-remix without --gdm must NOT invoke sudo; with --gdm MUST run sudo make install/uninstall
: >"$LOG"
run_tp --install flat-remix >/dev/null
! grep -q 'sudo make' "$LOG" || fail "flat-remix without --gdm must not invoke sudo make"
[[ -d "$H/.local/share/themes/Flat-Remix-Dark" && -d "$H/.local/share/themes/Flat-Remix-GTK-Blue-Dark" ]] \
    || fail "flat-remix user install must copy shell and root-level GTK themes"
run_tp --uninstall flat-remix >/dev/null
! grep -q 'sudo make uninstall' "$LOG" || fail "flat-remix uninstall without GDM must not invoke sudo make uninstall"

: >"$LOG"
run_tp --install flat-remix --gdm -y >/dev/null
grep -q 'sudo make install' "$LOG" || fail "flat-remix --gdm must run sudo make install"
run_tp --uninstall flat-remix -y >/dev/null
grep -q 'sudo make uninstall' "$LOG" || fail "flat-remix --gdm uninstall must run sudo make uninstall"

# 5) Install + uninstall remaining packs (incl. kayozxo-tahoe + flat-remix)
for _p in kayozxo-tahoe flat-remix whitesur material-gnome modular-adwaita modular-gruvbox gse-gdm gdm-settings; do
    : >"$LOG"
    run_tp --install "$_p" -y >/dev/null || fail "install failed for $_p"
    [[ -f "$CACHE/.installed/$_p" ]] || fail "state missing after install $_p"
done
[[ -d "$H/.local/share/themes/Flat-Remix-GTK-Blue-Dark" && -d "$H/.local/share/icons/Flat-Remix-Blue-Dark" ]] \
    || fail "flat-remix must install GTK and icon dirs"
[[ -d "$H/.local/share/icons/MacTahoe-dark" ]] || fail "kayozxo-tahoe must install MacTahoe icons"
[[ -d "$H/.local/share/icons/Gruvbox-Plus-Dark" ]] || fail "modular-gruvbox must install Gruvbox-Plus-Dark icons"
[[ -d "$H/.local/share/icons/WhiteSur-cursors" ]] || fail "WhiteSur-cursors must be installed"
grep -q 'flatpak install -y flathub io.github.realmazharhussain.GdmSettings' "$LOG" || fail "gdm-settings must install Flatpak"

: >"$LOG"
run_tp --uninstall all -y >/dev/null
for _p in kayozxo-tahoe flat-remix whitesur material-gnome modular-adwaita modular-gruvbox gse-gdm gdm-settings; do
    [[ ! -e "$CACHE/.installed/$_p" ]] || fail "--uninstall all left state for $_p"
done
[[ ! -d "$H/.local/share/themes/Flat-Remix-GTK-Blue-Dark" && ! -d "$H/.local/share/icons/Flat-Remix-Blue-Dark" ]] \
    || fail "--uninstall all must remove Flat-Remix GTK and icons"
grep -q 'kayozxo-tahoe -u' "$LOG" || fail "kayozxo-tahoe uninstall must pass -u"
[[ ! -d "$H/.local/share/icons/Gruvbox-Plus-Dark" ]] || fail "--uninstall all must remove Gruvbox-Plus-Dark"
[[ ! -d "$H/.local/share/icons/WhiteSur-cursors" ]] || fail "--uninstall all must remove WhiteSur-cursors"
grep -q 'gse-uninstall' "$LOG" || fail "--uninstall all must uninstall gse-gdm"
grep -q 'flatpak uninstall -y io.github.realmazharhussain.GdmSettings' "$LOG" || fail "--uninstall all must remove gdm-settings"
grep -q 'theme-setup-adwaita' "$LOG" || fail "--uninstall all must restore Adwaita"

# 6) Zenity GUI flow: no-display fail, OPT_GDM bleed guard, gdm submenu, adwaita reset, cancel
rc=0
DISPLAY='' WAYLAND_DISPLAY='' run_tp --gui </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "--gui without DISPLAY/WAYLAND_DISPLAY must fail"

: >"$LOG"
# Install whitesur (no GDM), then install mactahoe (with GDM), then uninstall whitesur (must NOT revert GDM),
# then GDM submenu (install+uninstall gse-gdm), adwaita reset, then uninstall mactahoe (MUST revert GDM), quit.
printf 'install\nwhitesur\ndark\ninstall\nmactahoe\ndark\nuninstall\nwhitesur\ngdm\ninstall-gse\ngdm\nuninstall-gse\nadwaita\nuninstall\nmactahoe\nstatus\nquit\n' >"$T/zqueue"
printf 'NONE\nGDM\n' >"$T/zextras"
WAYLAND_DISPLAY=wayland-0 ZN_QUEUE="$T/zqueue" ZN_EXTRAS_FILE="$T/zextras" run_tp --gui </dev/null >/dev/null
[[ ! -s "$T/zqueue" ]] || fail "GUI menu did not consume all queued actions"
[[ ! -e "$CACHE/.installed/whitesur" && ! -e "$CACHE/.installed/mactahoe" && ! -e "$CACHE/.installed/gse-gdm" ]] \
    || fail "GUI uninstalls must remove state files"
! grep -q 'gtk-tweaks WhiteSur-gtk-theme -g -r' "$LOG" \
    || fail "GUI OPT_GDM bleed: whitesur had gdm=0 and must NOT revert GDM"
grep -q 'gtk-tweaks MacTahoe-gtk-theme -g -r' "$LOG" \
    || fail "mactahoe had gdm=1 and must revert GDM"
grep -q 'gse-install' "$LOG" && grep -q 'gse-uninstall' "$LOG" \
    || fail "GUI gdm submenu must install and uninstall gse-gdm"
grep -q 'theme-setup-adwaita' "$LOG" || fail "GUI adwaita action must run theme-setup.sh"

# 10) Every upstream GitHub repo URL in theme-packs.sh must be 40-hex commit-pinned,
# and commit pin mismatch must fail closed.
python3 - "$SCRIPT" <<'PY' || fail "theme-packs.sh has unpinned GitHub repo URL"
import re, sys
from pathlib import Path
t = Path(sys.argv[1]).read_text()
urls = sorted(set(re.findall(r'https://github\.com/[^\s"]+\.git', t)))
pins = dict(re.findall(r'\["([^"]+)"\]="([0-9a-f]{40})"', t))
var_urls = dict(re.findall(r'^(URL_[A-Z_]+)="([^"]+)"', t, re.M))
resolved = {var_urls.get(k[1:], k) if k.startswith("$") else k: v for k, v in pins.items()}
missing = [u for u in urls if u not in resolved]
assert not missing, f"unpinned URLs: {missing}"
PY
rc=0
FAKE_GIT_BAD_HEAD=1 run_tp --install fluent -y >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "commit pin mismatch must fail closed"

# 11) Real git (not stubbed) exercises clone_or_update against a local file:// repo
if command -v git >/dev/null 2>&1; then
    _rsrc="$T/real-git-src"
    _rdst="$T/real-git-dst"
    git init -q "$_rsrc"
    git -C "$_rsrc" config user.email "test@example.com"
    git -C "$_rsrc" config user.name "Test"
    printf 'ok\n' >"$_rsrc/marker"
    git -C "$_rsrc" add marker
    git -C "$_rsrc" commit -q -m "init"
    _pin="$(git -C "$_rsrc" rev-parse HEAD)"
    _clone_fn="$(awk '/^clone_or_update\(\)/{f=1} f{print} f&&/^}$/{exit}' "$SCRIPT")"
    bash -euo pipefail -c "
      DRY_RUN=0
      need_cmd() { command -v \"\$1\" >/dev/null 2>&1; }
      declare -A REPO_PINS=([\"file://$_rsrc\"]=\"$_pin\")
      $_clone_fn
      clone_or_update \"file://$_rsrc\" \"$_rdst\"
      [[ \$(git -C \"$_rdst\" rev-parse HEAD) == \"$_pin\" && -f \"$_rdst/marker\" ]]
    " || fail "clone_or_update failed with real git against file:// repo"
    unset -v _rsrc _rdst _pin _clone_fn
fi

echo "PASS: theme-packs.test.sh"
