# 80-install-completeness.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Every listed package/Flatpak/extension installed; dock and shortcuts valid.

echo "--- Install completeness ---"
# Everything the lists promise must be present: a missing package, an empty
# dock slot or a shortcut that runs nothing is a failure, not a quiet skip.
# shellcheck source=lib/pkg-lists.sh
source "$REPO_ROOT/scripts/lib/pkg-lists.sh"
_report_missing() {  # LABEL HINT < names
    local _m
    _m="$(missing_pkgs | tr '\n' ' ')"
    if [ -n "$_m" ]; then
        check_fail "$1 not installed: $_m— $2"
    else
        echo "✓ all $1 installed"
    fi
}
# Process substitution, not a pipe: check_fail must count in this shell.
_report_missing "pacman.txt packages" "re-run ./install.sh" < <(pacman_targets)
_report_missing "aur.txt packages" "bash scripts/install-aur.sh" < <(list_entries "$REPO_ROOT/packages/aur.txt")
if command -v flatpak >/dev/null 2>&1; then
    _fp="$(flatpak list --app --columns=application 2>/dev/null)"
    _m=""
    while IFS= read -r _a; do
        grep -qx "$_a" <<<"$_fp" || _m+="$_a "
    done < <(list_entries "$REPO_ROOT/packages/flatpak.txt")
    if [ -n "$_m" ]; then
        check_fail "flatpaks not installed: $_m— bash scripts/install-flatpaks.sh"
    else
        echo "✓ all flatpak.txt apps installed"
    fi
else
    check_fail "flatpak missing — sudo pacman -S flatpak"
fi
_app_dirs=("$HOME/.local/share/applications" /usr/share/applications
    /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications")
_has_desktop() { local _d; for _d in "${_app_dirs[@]}"; do [ -f "$_d/$1" ] && return 0; done; return 1; }
if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell; then
    _m=""
    for _f in $(gsettings get org.gnome.shell favorite-apps | tr -d "[],'"); do
        _has_desktop "$_f" || _m+="$_f "
    done
    if [ -z "$_m" ]; then
        echo "✓ every dock favorite has an app"
    else
        check_fail "dock favorites with no installed app (empty icon): $_m"
    fi
    _kb=org.gnome.settings-daemon.plugins.media-keys
    for _p in $(gsettings get "$_kb" custom-keybindings | tr -d "[],'" | sed 's/^@as//'); do
        _cmd="$(gsettings get "$_kb.custom-keybinding:$_p" command | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')"
        _name="$(gsettings get "$_kb.custom-keybinding:$_p" name)"
        _bin="${_cmd%% *}"
        if [ -z "$_cmd" ]; then
            check_fail "shortcut $_name runs nothing (empty command)"
        elif ! command -v "$_bin" >/dev/null 2>&1; then
            check_fail "shortcut $_name: '$_bin' not installed"
        fi
    done
    # bash -c '… | wl-copy' style shortcuts depend on wl-clipboard.
    command -v wl-copy >/dev/null 2>&1 || check_fail "wl-clipboard missing (clipboard shortcut) — sudo pacman -S wl-clipboard"
    _m=""
    while IFS= read -r _u; do
        [ -d "$HOME/.local/share/gnome-shell/extensions/$_u" ] \
            || [ -d "/usr/share/gnome-shell/extensions/$_u" ] || _m+="$_u "
    done < <(list_entries "$REPO_ROOT/gnome/extensions.txt")
    if [ -z "$_m" ]; then
        echo "✓ all gnome/extensions.txt extensions installed"
    else
        check_fail "GNOME extensions not installed: $_m— bash scripts/install-aur.sh / install-extensions.sh"
    fi
fi
unset _fp _m _a _f _p _kb _cmd _name _bin _u _app_dirs
