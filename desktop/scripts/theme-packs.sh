#!/usr/bin/env bash
# theme-packs.sh — opt-in GNOME theme pack manager (install / uninstall / GUI / TUI / CLI).
#
# Supports MacTahoe, WhiteSur, Colloid, Graphite, Fluent, Material-Gnome,
# GNOME 51-safe modular stacks (Adwaita/Gruvbox), and standalone GDM tools
# (gse-gdm-extension, gdm-settings). Uses provision/lib/ui-menu.sh for GUI
# (zenity), TUI (dialog/whiptail), and plain fallback.
#
# Default dotfiles theme stays stock Adwaita; uninstalling reverts to Adwaita
# via desktop/scripts/theme-setup.sh when no other pack remains installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "error: run as your desktop user, not root (sudo is invoked only for opt-in GDM/pacman steps)" >&2
    exit 1
fi

# shellcheck source=../../provision/lib/ui-menu.sh
source "$REPO_ROOT/provision/lib/ui-menu.sh"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_PACKS_DIR="${THEME_PACKS_DIR:-$DATA_HOME/dotfiles/theme-packs}"
STATE_DIR="$THEME_PACKS_DIR/.installed"
ICONS_DIR="$DATA_HOME/icons"
THEMES_DIR="$DATA_HOME/themes"
LEGACY_THEMES_DIR="$HOME/.themes"

URL_WHITESUR_CURSORS="https://github.com/vinceliuice/WhiteSur-cursors.git"
URL_MACTAHOE_ICONS="https://github.com/vinceliuice/MacTahoe-icon-theme.git"
URL_COLLOID_ICONS="https://github.com/vinceliuice/Colloid-icon-theme.git"
URL_MOREWAITA="https://github.com/somepaulo/MoreWaita.git"
URL_MARBLE_SHELL="https://github.com/imarkoff/Marble-shell-theme.git"

# Pinned 40-hex upstream commits (refuses drift / floating tips before any install/sudo).
declare -A REPO_PINS=(
    ["https://github.com/SakibShahariar/material-gnome-theme.git"]="92c64afd547b0706f39ea58675a5bb5e6464f6d9"
    ["https://github.com/SylEleuth/gruvbox-plus-icon-pack.git"]="208d72b9ca9629896c6d20e398c4da1cdb19da46"
    ["https://github.com/daniruiz/flat-remix-gnome.git"]="b43c544b54ede3b663cb4bd8062b8da87b0203bb"
    ["https://github.com/daniruiz/flat-remix-gtk.git"]="919494f4f4ede88e2efb45cd48b98db7cc23f6ee"
    ["https://github.com/daniruiz/flat-remix.git"]="d9d882860c3284c255898eabf7ba6135960ad38a"
    ["$URL_MARBLE_SHELL"]="df788bc3d9d2147bcdeaedb907b90ced64f0ad48"
    ["https://github.com/kayozxo/GNOME-macOS-Tahoe.git"]="6eb17c244fdefb02e81e77128ac5f1be1bb162ee"
    ["https://github.com/pratap-panabaka/gse-gdm-extension.git"]="02b5c9e1a7469fc8c7fa4f77e0457d5208dd18c8"
    ["$URL_MOREWAITA"]="fb37f62eceaa9b07d0ad6dfa719ebf38ed6d7921"
    ["https://github.com/vinceliuice/Colloid-gtk-theme.git"]="fe11342f37f124f1b29d44cf33e9a06053f4bba2"
    ["$URL_COLLOID_ICONS"]="ceac6608ecd0e40025cbc2ebbd32bf0e0f4ebc6a"
    ["https://github.com/vinceliuice/Fluent-gtk-theme.git"]="7a49a464b0188c340101c52965c18190b1c694cf"
    ["https://github.com/vinceliuice/Fluent-icon-theme.git"]="c8a244f571ef8fb47812bdc9dbce76546cedce69"
    ["https://github.com/vinceliuice/Graphite-gtk-theme.git"]="364173f47407164948788e4abb5e2eb46600f71a"
    ["https://github.com/vinceliuice/MacTahoe-gtk-theme.git"]="1e45e19f510edb8cde18fa84d6cd5319f60b086b"
    ["$URL_MACTAHOE_ICONS"]="839848b9a8a38a92a6936e30c4abe35cc6f2546d"
    ["$URL_WHITESUR_CURSORS"]="e190baf618ed95ee217d2fd45589bd309b37672b"
    ["https://github.com/vinceliuice/WhiteSur-gtk-theme.git"]="d5782652d412137e26fb8ff55b55a5572e4c6995"
    ["https://github.com/vinceliuice/WhiteSur-icon-theme.git"]="73d8040da51a9ed74e47c7366e7e9ff437601a5c"
)

# Pinned Material-Bibata prebuilt cursor releases (upstream git repo has source only; releases ship Xcursor + GNOME 51 SVG).
BIBATA_VERSION="v1.5.0"
BIBATA_URL_DARK="https://github.com/SakibShahariar/material-bibata-cursor/releases/download/${BIBATA_VERSION}/bibata-material-dark-${BIBATA_VERSION}.tar.gz"
BIBATA_SHA256_DARK="8a0cfddd60787c65a078ce494b5708c1d68f3e576118fde0701949edb40cba04"
BIBATA_URL_LIGHT="https://github.com/SakibShahariar/material-bibata-cursor/releases/download/${BIBATA_VERSION}/bibata-material-light-${BIBATA_VERSION}.tar.gz"
BIBATA_SHA256_LIGHT="db8e41025be52abd211de6485cb12b411058f7de811216bc0f495c7b04a1364b"

ALL_PACKS=(
    mactahoe
    kayozxo-tahoe
    whitesur
    colloid
    graphite
    fluent
    flat-remix
    material-gnome
    modular-adwaita
    modular-gruvbox
    gse-gdm
    gdm-settings
)

UI_REQ="${THEME_UI:-}"
ACTION=""
TARGET_PACK=""
OPT_GDM=0
OPT_FIREFOX=0
OPT_FLATPAK=0
OPT_COLOR="dark"
DRY_RUN=0
ASSUME_YES=0
IN_GUI=0

usage() {
    cat <<'EOF'
Usage: bash desktop/scripts/theme-packs.sh [OPTIONS]

Interactive GUI/TUI/CLI manager to install or uninstall complete GNOME theme
packs (GTK3/GTK4/Libadwaita, Shell, Icons, Cursors, and opt-in GDM/Firefox/Flatpak).

Actions (omit for interactive menu):
  --install PACK    Install and apply PACK
  --uninstall PACK  Uninstall PACK (or 'all' to remove every installed pack)
  --list            List available theme packs and exit
  --status          Show installed packs and active GNOME theme gsettings

Options:
  --gui, --zenity   Force zenity GUI dialogs (requires DISPLAY/WAYLAND_DISPLAY)
  --tui             Force terminal TUI (dialog/whiptail)
  --plain           Force plain terminal prompts
  --color dark|light  Theme color variant (default: dark)
  --gdm             Opt-in: also apply/revert GDM login screen theme (uses sudo)
  --firefox         Opt-in: also apply/revert matching Firefox theme (MacTahoe/WhiteSur)
  --flatpak         Opt-in: also apply/revert Flatpak theme override
  -n, --dry-run     Preview commands without modifying files or cloning repos
  -y, --yes         Skip interactive confirmations
  -h, --help        Show this help and exit

Environment:
  THEME_UI=gui|tui|dialog|whiptail|plain
  THEME_PACKS_DIR=...  Cache/state dir (default: ~/.local/share/dotfiles/theme-packs)
  COLLOID_TWEAKS=...   Extra --tweaks value for Colloid (e.g. gruvbox, nord, black)
EOF
}

list_packs() {
    cat <<'EOF'
mactahoe         MacTahoe macOS suite (GTK/Libadwaita, Shell, Icons, Cursors; opt-in GDM/Firefox/Flatpak)
kayozxo-tahoe    GNOME-macOS-Tahoe (kayozxo GTK/Libadwaita -la, Shell, MacTahoe Icons, WhiteSur Cursors)
whitesur         WhiteSur macOS suite (GTK/Libadwaita, Shell, Icons, Cursors; opt-in GDM/Firefox/Flatpak)
colloid          Colloid flat/Material suite (GTK/Libadwaita, Shell 48-0 bucket, Icons, Cursors; no native GDM)
graphite         Graphite flat monochrome suite (GTK/Libadwaita, Shell 48-0 bucket, Colloid-grey Icons/Cursors; opt-in GDM)
fluent           Fluent rounded suite (GTK/Libadwaita, Shell, Icons, Cursors; no native GDM)
flat-remix       Flat Remix suite (GNOME Shell ~49, Flat-Remix GTK/Icons, WhiteSur Cursors; opt-in GDM uses sudo)
material-gnome   Material You / Material 3 suite (GTK/Libadwaita, Shell, MoreWaita Icons, Material-Bibata Cursors)
modular-adwaita  GNOME 51-safe HIG stack (Marble Shell, adw-gtk3, MoreWaita Icons, WhiteSur Cursors; opt-in GDM)
modular-gruvbox  GNOME 51-safe Gruvbox stack (Marble Shell, adw-gtk3, Gruvbox-Plus Icons, WhiteSur Cursors; opt-in GDM)
gse-gdm          Standalone GDM tool: gse-gdm-extension (GNOME 42-51 safe, no gresource rebuild; prefer on GNOME 51)
gdm-settings     Standalone GDM tool: Login Manager Settings Flatpak (io.github.realmazharhussain.GdmSettings)
EOF
}

valid_pack() {
    local p
    for p in "${ALL_PACKS[@]}"; do
        [[ $p == "$1" ]] && return 0
    done
    return 1
}

while (($#)); do
    case "$1" in
        --gui|--zenity) UI_REQ="gui" ;;
        --tui) UI_REQ="tui" ;;
        --plain) UI_REQ="plain" ;;
        --list) list_packs; exit 0 ;;
        --status) ACTION="status" ;;
        --install)
            [[ $# -ge 2 ]] || { echo "theme-packs.sh: --install requires a pack name (try --list)" >&2; exit 2; }
            ACTION="install"; TARGET_PACK="$2"; shift
            ;;
        --install=*) ACTION="install"; TARGET_PACK="${1#--install=}" ;;
        --uninstall)
            [[ $# -ge 2 ]] || { echo "theme-packs.sh: --uninstall requires a pack name or 'all'" >&2; exit 2; }
            ACTION="uninstall"; TARGET_PACK="$2"; shift
            ;;
        --uninstall=*) ACTION="uninstall"; TARGET_PACK="${1#--uninstall=}" ;;
        --color)
            [[ $# -ge 2 ]] || { echo "theme-packs.sh: --color requires dark or light" >&2; exit 2; }
            OPT_COLOR="$2"; shift
            ;;
        --color=*) OPT_COLOR="${1#--color=}" ;;
        --gdm) OPT_GDM=1 ;;
        --firefox) OPT_FIREFOX=1 ;;
        --flatpak) OPT_FLATPAK=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "theme-packs.sh: unknown option '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

case "$OPT_COLOR" in
    dark|light) ;;
    *) echo "theme-packs.sh: invalid --color '$OPT_COLOR' (use dark or light)" >&2; exit 2 ;;
esac

if [[ $ACTION == install ]]; then
    valid_pack "$TARGET_PACK" || { echo "theme-packs.sh: unknown pack '$TARGET_PACK' (try --list)" >&2; exit 2; }
elif [[ $ACTION == uninstall && $TARGET_PACK != all ]]; then
    valid_pack "$TARGET_PACK" || { echo "theme-packs.sh: unknown pack '$TARGET_PACK' (try --list)" >&2; exit 2; }
fi

act() {
    if (( DRY_RUN )); then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

act_in() {
    local dir=$1; shift
    if (( DRY_RUN )); then
        printf '[dry-run] (cd %s && %s)\n' "$dir" "$*"
        return 0
    fi
    (cd "$dir" && "$@")
}

need_cmd() {
    local cmd=$1 pkg=${2:-$1}
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    if command -v pacman >/dev/null 2>&1; then
        confirm_action "privileged install of $pkg via pacman (required for $cmd)" || return 1
        act sudo pacman -S --needed --noconfirm "$pkg" || return 1
        if (( DRY_RUN )) || command -v "$cmd" >/dev/null 2>&1; then
            return 0
        fi
    fi
    echo "error: missing required command '$cmd' (install: sudo pacman -S $pkg)" >&2
    return 1
}

have_session_bus() {
    [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} || -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]]
}

gset_get() {
    gsettings get "$@" 2>/dev/null | tr -d "'" || true
}

apply_gsettings() {
    local gtk=${1:-} shell=${2:-} icons=${3:-} cursor=${4:-}
    if ! command -v gsettings >/dev/null 2>&1; then
        echo "○ gsettings not found — apply themes manually in GNOME Tweaks"
        return 0
    fi
    if ! have_session_bus; then
        echo "○ no session D-Bus — skipped gsettings apply (re-run inside GNOME session)"
        return 0
    fi
    local scheme="prefer-dark"
    [[ $OPT_COLOR == light ]] && scheme="default"
    act gsettings set org.gnome.desktop.interface color-scheme "$scheme"
    if [[ -n $gtk ]]; then act gsettings set org.gnome.desktop.interface gtk-theme "$gtk"; fi
    if [[ -n $icons ]]; then act gsettings set org.gnome.desktop.interface icon-theme "$icons"; fi
    if [[ -n $cursor ]]; then act gsettings set org.gnome.desktop.interface cursor-theme "$cursor"; fi
    if [[ -n $shell ]]; then
        if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell.extensions.user-theme; then
            act gsettings set org.gnome.shell.extensions.user-theme name "$shell"
        else
            echo "○ user-theme extension schema not active — enable User Themes for Shell theme '$shell'"
        fi
    fi
}

detect_dir_name() {
    local pattern=$1; shift
    local base d
    shopt -s nullglob
    for base in "$@"; do
        for d in "$base"/$pattern; do
            if [[ -d $d ]]; then
                shopt -u nullglob
                basename "$d"
                return 0
            fi
        done
    done
    shopt -u nullglob
    return 1
}

clone_or_update() {
    local url=$1 dest=$2
    local pin="${REPO_PINS[$url]:-}"
    need_cmd git git || return 1
    if [[ ! $pin =~ ^[0-9a-f]{40}$ ]]; then
        echo "error: refusing unpinned upstream repo: $url" >&2
        return 1
    fi
    if (( DRY_RUN )); then
        printf '[dry-run] git fetch --depth=1 %s %s && checkout --detach (%s)\n' "$url" "$pin" "$dest"
        return 0
    fi
    mkdir -p "$dest"
    if [[ ! -d $dest/.git ]]; then
        git -C "$dest" init -q
        git -C "$dest" remote add origin "$url"
    else
        git -C "$dest" remote set-url origin "$url"
    fi
    local cur=""
    cur="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
    if [[ $cur != "$pin" ]]; then
        echo "→ Fetching $(basename "$dest") @ ${pin:0:12}..."
        git -C "$dest" fetch --depth=1 origin "$pin"
        git -C "$dest" checkout -q --detach FETCH_HEAD
    fi
    cur="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
    if [[ $cur != "$pin" ]]; then
        echo "error: commit pin mismatch for $url (got ${cur:-none}, want $pin)" >&2
        return 1
    fi
}

warn_gdm_gresource() {
    echo "⚠ GDM note (GNOME 51): patching gnome-shell-theme.gresource can be overwritten by gnome-shell pacman upgrades."
    echo "  Re-run with --gdm after upgrades, or use standalone 'gse-gdm' / 'gdm-settings' instead."
}

warn_upstream_sudo() {
    local dir=$1
    echo "⚠ Running pinned upstream script under sudo from: $dir"
    echo "  Review the checkout before authenticating sudo."
}

confirm_action() {
    local desc=$1 ans
    if (( DRY_RUN || ASSUME_YES || IN_GUI )); then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        echo "error: non-interactive $desc requires --yes (-y) or --dry-run (-n)" >&2
        return 1
    fi
    read -r -p "Proceed with $desc? [y/N] " ans
    case "$ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) echo "Aborted."; return 1 ;;
    esac
}

record_state() {
    local pack=$1 eff_gdm=$2 eff_ff=$3 eff_fp=$4
    if [[ $(state_val "$pack" gdm || echo 0) == 1 ]]; then eff_gdm=1; fi
    if [[ $(state_val "$pack" firefox || echo 0) == 1 ]]; then eff_ff=1; fi
    if [[ $(state_val "$pack" flatpak || echo 0) == 1 ]]; then eff_fp=1; fi
    if (( DRY_RUN )); then
        printf '[dry-run] write state %s/%s (color=%s gdm=%d firefox=%d flatpak=%d)\n' \
            "$STATE_DIR" "$pack" "$OPT_COLOR" "$eff_gdm" "$eff_ff" "$eff_fp"
        return 0
    fi
    mkdir -p "$STATE_DIR"
    cat >"$STATE_DIR/$pack" <<EOF
pack=$pack
color=$OPT_COLOR
gdm=$eff_gdm
firefox=$eff_ff
flatpak=$eff_fp
installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

state_val() {
    local pack=$1 key=$2 f="$STATE_DIR/$1"
    [[ -f $f ]] || return 1
    sed -n "s/^${key}=//p" "$f" | head -1
}

pack_installed() {
    [[ -f "$STATE_DIR/$1" ]]
}

any_other_pack_uses() {
    local needle=$1 skip=$2 p
    for p in "${ALL_PACKS[@]}"; do
        [[ $p == "$skip" ]] && continue
        pack_installed "$p" || continue
        case "$needle:$p" in
            whitesur-cursors:whitesur|whitesur-cursors:kayozxo-tahoe|whitesur-cursors:flat-remix|whitesur-cursors:modular-adwaita|whitesur-cursors:modular-gruvbox) return 0 ;;
            mactahoe-icons:mactahoe|mactahoe-icons:kayozxo-tahoe) return 0 ;;
            colloid-icons:colloid|colloid-icons:graphite) return 0 ;;
            morewaita:material-gnome|morewaita:modular-adwaita) return 0 ;;
            marble:modular-adwaita|marble:modular-gruvbox) return 0 ;;
        esac
    done
    return 1
}

any_desktop_pack_installed() {
    local p
    for p in mactahoe kayozxo-tahoe whitesur colloid graphite fluent flat-remix material-gnome modular-adwaita modular-gruvbox; do
        pack_installed "$p" && return 0
    done
    return 1
}

# Remove ~/.config/gtk-4.0 symlinks ONLY when they point to this pack (or are
# dangling links under a managed theme dir). Never delete real user files or
# another installed pack's active symlinks.
remove_gtk4_overrides() {
    local pattern=$1 f tgt
    for f in "$CONFIG_HOME/gtk-4.0/gtk.css" "$CONFIG_HOME/gtk-4.0/gtk-dark.css" "$CONFIG_HOME/gtk-4.0/colors.css" "$CONFIG_HOME/gtk-4.0/assets"; do
        [[ -L $f ]] || continue
        tgt="$(readlink -m "$f" 2>/dev/null || readlink "$f" 2>/dev/null || true)"
        if [[ $tgt == *"$pattern"* ]] \
            || { [[ ! -e $f ]] && [[ $tgt == "$THEMES_DIR/"* || $tgt == "$LEGACY_THEMES_DIR/"* || $tgt == "$THEME_PACKS_DIR/"* ]]; }; then
            act rm -f -- "$f"
        fi
    done
}

install_vinceliuice_cursors() {
    local repo_dir=$1
    if [[ -f $repo_dir/cursors/install.sh ]]; then
        act_in "$repo_dir/cursors" bash ./install.sh
    fi
}

install_adw_gtk_pkg() {
    if command -v pacman >/dev/null 2>&1; then
        if ! pacman -Q adw-gtk-theme >/dev/null 2>&1; then
            confirm_action "privileged install of adw-gtk-theme via pacman" || return 1
            act sudo pacman -S --needed --noconfirm adw-gtk-theme
        fi
    else
        echo "○ pacman not found — ensure adw-gtk3 is installed for GTK3 parity"
    fi
}

install_pack() {
    local pack=$1
    local color_cap="Dark"
    [[ $OPT_COLOR == light ]] && color_cap="Light"
    local eff_gdm=0 eff_ff=0 eff_fp=0

    if (( OPT_GDM )) && [[ $pack != colloid && $pack != fluent && $pack != material-gnome && $pack != kayozxo-tahoe ]]; then
        confirm_action "privileged GDM install for $pack" || return 1
    elif [[ $pack == gse-gdm ]]; then
        confirm_action "privileged install of gse-gdm-extension" || return 1
    fi

    echo "=== Installing theme pack: $pack (color=$OPT_COLOR gdm=$OPT_GDM firefox=$OPT_FIREFOX flatpak=$OPT_FLATPAK) ==="

    case "$pack" in
        mactahoe)
            need_cmd git git || return 1
            need_cmd sassc sassc || return 1
            if (( OPT_GDM )); then need_cmd glib-compile-resources glib2 || return 1; fi
            local gtk_dir="$THEME_PACKS_DIR/mactahoe/MacTahoe-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/MacTahoe-icon-theme"
            clone_or_update "https://github.com/vinceliuice/MacTahoe-gtk-theme.git" "$gtk_dir"
            clone_or_update "$URL_MACTAHOE_ICONS" "$icon_dir"
            act_in "$gtk_dir" bash ./install.sh -c "$OPT_COLOR" -l
            if (( OPT_FLATPAK )); then
                act_in "$gtk_dir" bash ./tweaks.sh -F
                eff_fp=1
            fi
            if (( OPT_FIREFOX )); then
                act_in "$gtk_dir" bash ./tweaks.sh -f
                eff_ff=1
            fi
            if (( OPT_GDM )); then
                warn_gdm_gresource
                warn_upstream_sudo "$gtk_dir"
                act_in "$gtk_dir" sudo bash ./tweaks.sh -g -c "$OPT_COLOR"
                eff_gdm=1
            fi
            act_in "$icon_dir" bash ./install.sh
            install_vinceliuice_cursors "$icon_dir"
            local gtk_name icon_name cur_name
            gtk_name="$(detect_dir_name "MacTahoe-${color_cap}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "MacTahoe-${color_cap}")"
            icon_name="$(detect_dir_name "MacTahoe-${OPT_COLOR}*" "$ICONS_DIR" "$HOME/.icons" || echo "MacTahoe-${OPT_COLOR}")"
            cur_name="$(detect_dir_name "MacTahoe*cursors*" "$ICONS_DIR" "$HOME/.icons" || echo "MacTahoe-cursors")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "$cur_name"
            ;;

        kayozxo-tahoe)
            need_cmd git git || return 1
            need_cmd sass dart-sass || return 1
            local theme_dir="$THEME_PACKS_DIR/kayozxo-tahoe/GNOME-macOS-Tahoe"
            local icon_dir="$THEME_PACKS_DIR/shared/MacTahoe-icon-theme"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            clone_or_update "https://github.com/kayozxo/GNOME-macOS-Tahoe.git" "$theme_dir"
            clone_or_update "$URL_MACTAHOE_ICONS" "$icon_dir"
            clone_or_update "$URL_WHITESUR_CURSORS" "$cur_dir"
            local mode_flag="-d"
            [[ $OPT_COLOR == light ]] && mode_flag="-l"
            act_in "$theme_dir" bash ./install.sh "$mode_flag" -la
            if (( OPT_GDM )); then
                echo "○ GNOME-macOS-Tahoe configures GDM interactively — run $theme_dir/install.sh or use '--install gse-gdm'."
            fi
            act_in "$icon_dir" bash ./install.sh
            act_in "$cur_dir" bash ./install.sh
            local gtk_name="" icon_name base d bn
            shopt -s nullglob
            for base in "$THEMES_DIR" "$LEGACY_THEMES_DIR"; do
                for d in "$base"/*Tahoe*"${color_cap}"*; do
                    [[ -d $d ]] || continue
                    bn="$(basename "$d")"
                    [[ $bn == MacTahoe* ]] && continue
                    gtk_name="$bn"
                    break 2
                done
            done
            shopt -u nullglob
            [[ -n $gtk_name ]] || gtk_name="Tahoe-${color_cap}"
            icon_name="$(detect_dir_name "MacTahoe-${OPT_COLOR}*" "$ICONS_DIR" "$HOME/.icons" || echo "MacTahoe-${OPT_COLOR}")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "WhiteSur-cursors"
            ;;

        whitesur)
            need_cmd git git || return 1
            need_cmd sassc sassc || return 1
            if (( OPT_GDM )); then need_cmd glib-compile-resources glib2 || return 1; fi
            local gtk_dir="$THEME_PACKS_DIR/whitesur/WhiteSur-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/whitesur/WhiteSur-icon-theme"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            clone_or_update "https://github.com/vinceliuice/WhiteSur-gtk-theme.git" "$gtk_dir"
            clone_or_update "https://github.com/vinceliuice/WhiteSur-icon-theme.git" "$icon_dir"
            clone_or_update "$URL_WHITESUR_CURSORS" "$cur_dir"
            act_in "$gtk_dir" bash ./install.sh -c "$OPT_COLOR" -l
            if (( OPT_FLATPAK )); then
                act_in "$gtk_dir" bash ./tweaks.sh -F
                eff_fp=1
            fi
            if (( OPT_FIREFOX )); then
                act_in "$gtk_dir" bash ./tweaks.sh -f
                eff_ff=1
            fi
            if (( OPT_GDM )); then
                warn_gdm_gresource
                warn_upstream_sudo "$gtk_dir"
                act_in "$gtk_dir" sudo bash ./tweaks.sh -g -c "$OPT_COLOR"
                eff_gdm=1
            fi
            act_in "$icon_dir" bash ./install.sh
            act_in "$cur_dir" bash ./install.sh
            local gtk_name icon_name cur_name
            gtk_name="$(detect_dir_name "WhiteSur-${color_cap}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "WhiteSur-${color_cap}")"
            icon_name="$(detect_dir_name "WhiteSur-${OPT_COLOR}*" "$ICONS_DIR" "$HOME/.icons" || echo "WhiteSur-${OPT_COLOR}")"
            cur_name="$(detect_dir_name "WhiteSur-cursors*" "$ICONS_DIR" "$HOME/.icons" || echo "WhiteSur-cursors")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "$cur_name"
            ;;

        colloid)
            need_cmd git git || return 1
            need_cmd sassc sassc || return 1
            local gtk_dir="$THEME_PACKS_DIR/colloid/Colloid-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/Colloid-icon-theme"
            clone_or_update "https://github.com/vinceliuice/Colloid-gtk-theme.git" "$gtk_dir"
            clone_or_update "$URL_COLLOID_ICONS" "$icon_dir"
            local args=(-c "$OPT_COLOR" -l)
            if [[ -n ${COLLOID_TWEAKS:-} ]]; then
                args+=(--tweaks "$COLLOID_TWEAKS")
            fi
            act_in "$gtk_dir" bash ./install.sh "${args[@]}"
            if (( OPT_GDM )); then
                echo "○ Colloid has no built-in GDM patcher — use '--install gse-gdm' or '--install gdm-settings' for GDM."
            fi
            act_in "$icon_dir" bash ./install.sh
            install_vinceliuice_cursors "$icon_dir"
            local gtk_name icon_name cur_name
            gtk_name="$(detect_dir_name "Colloid-${color_cap}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Colloid-${color_cap}")"
            icon_name="$(detect_dir_name "Colloid-${color_cap}*" "$ICONS_DIR" "$HOME/.icons" || echo "Colloid-${color_cap}")"
            cur_name="$(detect_dir_name "Colloid*cursors*" "$ICONS_DIR" "$HOME/.icons" || echo "Colloid-dark-cursors")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "$cur_name"
            ;;

        graphite)
            need_cmd git git || return 1
            need_cmd sassc sassc || return 1
            if (( OPT_GDM )); then need_cmd glib-compile-resources glib2 || return 1; fi
            local gtk_dir="$THEME_PACKS_DIR/graphite/Graphite-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/Colloid-icon-theme"
            clone_or_update "https://github.com/vinceliuice/Graphite-gtk-theme.git" "$gtk_dir"
            clone_or_update "$URL_COLLOID_ICONS" "$icon_dir"
            act_in "$gtk_dir" bash ./install.sh -c "$OPT_COLOR" -l
            if (( OPT_GDM )); then
                warn_gdm_gresource
                warn_upstream_sudo "$gtk_dir"
                act_in "$gtk_dir" sudo bash ./install.sh -c "$OPT_COLOR" -g
                eff_gdm=1
            fi
            act_in "$icon_dir" bash ./install.sh -t grey
            install_vinceliuice_cursors "$icon_dir"
            local gtk_name icon_name cur_name
            gtk_name="$(detect_dir_name "Graphite-${color_cap}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Graphite-${color_cap}")"
            icon_name="$(detect_dir_name "Colloid-Grey-${color_cap}*" "$ICONS_DIR" "$HOME/.icons" || echo "Colloid-Grey-${color_cap}")"
            cur_name="$(detect_dir_name "Colloid*cursors*" "$ICONS_DIR" "$HOME/.icons" || echo "Colloid-dark-cursors")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "$cur_name"
            ;;

        fluent)
            need_cmd git git || return 1
            need_cmd sassc sassc || return 1
            local gtk_dir="$THEME_PACKS_DIR/fluent/Fluent-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/fluent/Fluent-icon-theme"
            clone_or_update "https://github.com/vinceliuice/Fluent-gtk-theme.git" "$gtk_dir"
            clone_or_update "https://github.com/vinceliuice/Fluent-icon-theme.git" "$icon_dir"
            act_in "$gtk_dir" bash ./install.sh -c "$OPT_COLOR" -l
            if (( OPT_GDM )); then
                echo "○ Fluent has no built-in GDM patcher — use '--install gse-gdm' or '--install gdm-settings' for GDM."
            fi
            act_in "$icon_dir" bash ./install.sh
            install_vinceliuice_cursors "$icon_dir"
            local gtk_name icon_name cur_name
            gtk_name="$(detect_dir_name "Fluent-${color_cap}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Fluent-${color_cap}")"
            icon_name="$(detect_dir_name "Fluent-${OPT_COLOR}*" "$ICONS_DIR" "$HOME/.icons" || echo "Fluent-${OPT_COLOR}")"
            cur_name="$(detect_dir_name "Fluent*cursors*" "$ICONS_DIR" "$HOME/.icons" || echo "Fluent-dark-cursors")"
            apply_gsettings "$gtk_name" "$gtk_name" "$icon_name" "$cur_name"
            ;;

        flat-remix)
            need_cmd git git || return 1
            if (( OPT_GDM )); then
                need_cmd make make || return 1
                need_cmd glib-compile-resources glib2 || return 1
                need_cmd convert imagemagick || return 1
            fi
            local shell_dir="$THEME_PACKS_DIR/flat-remix/flat-remix-gnome"
            local gtk_dir="$THEME_PACKS_DIR/flat-remix/flat-remix-gtk"
            local icon_dir="$THEME_PACKS_DIR/flat-remix/flat-remix"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            clone_or_update "https://github.com/daniruiz/flat-remix-gnome.git" "$shell_dir"
            clone_or_update "https://github.com/daniruiz/flat-remix-gtk.git" "$gtk_dir"
            clone_or_update "https://github.com/daniruiz/flat-remix.git" "$icon_dir"
            clone_or_update "$URL_WHITESUR_CURSORS" "$cur_dir"
            act mkdir -p "$THEMES_DIR" "$ICONS_DIR"
            if (( OPT_GDM )); then
                act_in "$shell_dir" make
                warn_gdm_gresource
                warn_upstream_sudo "$shell_dir"
                act_in "$shell_dir" sudo make install
                eff_gdm=1
            else
                shopt -s nullglob
                local sd
                for sd in "$shell_dir"/themes/Flat-Remix* "$shell_dir"/Flat-Remix-*; do
                    if [[ -d $sd ]]; then act cp -a "$sd" "$THEMES_DIR/"; fi
                done
                shopt -u nullglob
            fi
            shopt -s nullglob
            local d gtk_copied=0
            for d in "$gtk_dir"/themes/Flat-Remix-GTK-* "$gtk_dir"/Flat-Remix-GTK-*; do
                if [[ -d $d ]]; then
                    act cp -a "$d" "$THEMES_DIR/"
                    gtk_copied=1
                fi
            done
            if (( ! gtk_copied && ! DRY_RUN )); then
                echo "○ no Flat-Remix-GTK-* directories found in $gtk_dir"
            fi
            for d in "$icon_dir"/Flat-Remix-*; do
                if [[ -d $d ]]; then act cp -a "$d" "$ICONS_DIR/"; fi
            done
            shopt -u nullglob
            act_in "$cur_dir" bash ./install.sh
            local gtk_name="Flat-Remix-GTK-Blue-Dark" shell_name="Flat-Remix-Dark" icon_name="Flat-Remix-Blue-Dark"
            if [[ $OPT_COLOR == light ]]; then
                gtk_name="Flat-Remix-GTK-Blue-Light"
                shell_name="Flat-Remix-Light"
                icon_name="Flat-Remix-Blue-Light"
            fi
            apply_gsettings "$gtk_name" "$shell_name" "$icon_name" "WhiteSur-cursors"
            ;;

        material-gnome)
            need_cmd git git || return 1
            need_cmd curl curl || return 1
            need_cmd tar tar || return 1
            need_cmd sha256sum coreutils || return 1
            local theme_dir="$THEME_PACKS_DIR/material-gnome/material-gnome-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/MoreWaita"
            clone_or_update "https://github.com/SakibShahariar/material-gnome-theme.git" "$theme_dir"
            clone_or_update "$URL_MOREWAITA" "$icon_dir"
            local args=(--force)
            if (( OPT_FLATPAK )); then
                args+=(--flatpak)
                eff_fp=1
            fi
            act_in "$theme_dir" bash ./install.sh "${args[@]}"
            if (( OPT_GDM )); then
                echo "○ Material-Gnome has no built-in GDM patcher — use '--install gse-gdm' or '--install gdm-settings' for GDM."
            fi
            act_in "$icon_dir" bash ./install.sh
            local bibata_url="$BIBATA_URL_DARK" bibata_sha="$BIBATA_SHA256_DARK" bibata_want="Bibata-Material-Grey"
            if [[ $OPT_COLOR == light ]]; then
                bibata_url="$BIBATA_URL_LIGHT"
                bibata_sha="$BIBATA_SHA256_LIGHT"
                bibata_want="Bibata-Material-Grey-Light"
            fi
            local bibata_tgz="$THEME_PACKS_DIR/material-gnome/${bibata_url##*/}"
            act mkdir -p "$THEME_PACKS_DIR/material-gnome" "$ICONS_DIR"
            if (( DRY_RUN )); then
                printf '[dry-run] curl -fsSL %s -o %s (sha256=%s) && extract %s -> %s\n' \
                    "$bibata_url" "$bibata_tgz" "${bibata_sha:0:12}" "$bibata_want" "$ICONS_DIR"
            else
                if [[ ! -f $bibata_tgz ]] || ! printf '%s  %s\n' "$bibata_sha" "$bibata_tgz" | sha256sum -c --status; then
                    echo "→ Fetching $(basename "$bibata_url")..."
                    curl -fsSL "$bibata_url" -o "$bibata_tgz"
                    if ! printf '%s  %s\n' "$bibata_sha" "$bibata_tgz" | sha256sum -c --status; then
                        rm -f -- "$bibata_tgz"
                        echo "error: sha256 mismatch for $bibata_url (want $bibata_sha)" >&2
                        return 1
                    fi
                fi
                tar -xzf "$bibata_tgz" -C "$ICONS_DIR" --strip-components=1 --wildcards "*/${bibata_want}" \
                    || tar -xzf "$bibata_tgz" -C "$ICONS_DIR" --strip-components=1
            fi
            local gtk_name cur_name
            gtk_name="$(detect_dir_name "Material-Gnome*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Material-Gnome")"
            cur_name="$(detect_dir_name "Bibata-Material*" "$ICONS_DIR" "$HOME/.icons" || echo "$bibata_want")"
            apply_gsettings "$gtk_name" "$gtk_name" "MoreWaita" "$cur_name"
            ;;

        modular-adwaita)
            need_cmd git git || return 1
            need_cmd python3 python || return 1
            if (( OPT_GDM )); then need_cmd glib-compile-resources glib2 || return 1; fi
            install_adw_gtk_pkg || return 1
            local shell_dir="$THEME_PACKS_DIR/shared/Marble-shell-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/MoreWaita"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            clone_or_update "$URL_MARBLE_SHELL" "$shell_dir"
            clone_or_update "$URL_MOREWAITA" "$icon_dir"
            clone_or_update "$URL_WHITESUR_CURSORS" "$cur_dir"
            act_in "$shell_dir" python3 install.py --blue --filled --mode "$OPT_COLOR"
            if (( OPT_GDM )); then
                warn_gdm_gresource
                warn_upstream_sudo "$shell_dir"
                act_in "$shell_dir" sudo python3 install.py --blue --filled --mode "$OPT_COLOR" --gdm
                eff_gdm=1
            fi
            act_in "$icon_dir" bash ./install.sh
            act_in "$cur_dir" bash ./install.sh
            local gtk_name="adw-gtk3-dark" shell_name
            [[ $OPT_COLOR == light ]] && gtk_name="adw-gtk3"
            shell_name="$(detect_dir_name "Marble-blue-${OPT_COLOR}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Marble-blue-${OPT_COLOR}")"
            apply_gsettings "$gtk_name" "$shell_name" "MoreWaita" "WhiteSur-cursors"
            ;;

        modular-gruvbox)
            need_cmd git git || return 1
            need_cmd python3 python || return 1
            if (( OPT_GDM )); then need_cmd glib-compile-resources glib2 || return 1; fi
            install_adw_gtk_pkg || return 1
            local shell_dir="$THEME_PACKS_DIR/shared/Marble-shell-theme"
            local icon_dir="$THEME_PACKS_DIR/modular-gruvbox/gruvbox-plus-icon-pack"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            clone_or_update "$URL_MARBLE_SHELL" "$shell_dir"
            clone_or_update "https://github.com/SylEleuth/gruvbox-plus-icon-pack.git" "$icon_dir"
            clone_or_update "$URL_WHITESUR_CURSORS" "$cur_dir"
            act_in "$shell_dir" python3 install.py --yellow --filled --mode "$OPT_COLOR"
            if (( OPT_GDM )); then
                warn_gdm_gresource
                warn_upstream_sudo "$shell_dir"
                act_in "$shell_dir" sudo python3 install.py --yellow --filled --mode "$OPT_COLOR" --gdm
                eff_gdm=1
            fi
            act mkdir -p "$ICONS_DIR"
            if [[ -d $icon_dir/Gruvbox-Plus-Dark || $DRY_RUN -eq 1 ]]; then
                act cp -a "$icon_dir/Gruvbox-Plus-Dark" "$ICONS_DIR/"
            fi
            if [[ -d $icon_dir/Gruvbox-Plus-Light || $DRY_RUN -eq 1 ]]; then
                act cp -a "$icon_dir/Gruvbox-Plus-Light" "$ICONS_DIR/"
            fi
            act_in "$cur_dir" bash ./install.sh
            local gtk_name="adw-gtk3-dark" icon_name="Gruvbox-Plus-Dark" shell_name
            if [[ $OPT_COLOR == light ]]; then
                gtk_name="adw-gtk3"
                icon_name="Gruvbox-Plus-Light"
            fi
            shell_name="$(detect_dir_name "Marble-yellow-${OPT_COLOR}*" "$THEMES_DIR" "$LEGACY_THEMES_DIR" || echo "Marble-yellow-${OPT_COLOR}")"
            apply_gsettings "$gtk_name" "$shell_name" "$icon_name" "WhiteSur-cursors"
            ;;

        gse-gdm)
            need_cmd git git || return 1
            need_cmd dconf dconf || return 1
            need_cmd gnome-shell gnome-shell || return 1
            local gdm_dir="$THEME_PACKS_DIR/gse-gdm/gse-gdm-extension"
            clone_or_update "https://github.com/pratap-panabaka/gse-gdm-extension.git" "$gdm_dir"
            warn_upstream_sudo "$gdm_dir"
            act_in "$gdm_dir" sudo bash ./install.sh
            eff_gdm=1
            ;;

        gdm-settings)
            need_cmd flatpak flatpak || return 1
            act flatpak install -y flathub io.github.realmazharhussain.GdmSettings
            eff_gdm=1
            ;;
    esac

    record_state "$pack" "$eff_gdm" "$eff_ff" "$eff_fp"
    echo "✓ Installed theme pack: $pack"
}

uninstall_pack() {
    local pack=$1
    local had_gdm had_ff had_fp
    had_gdm="$(state_val "$pack" gdm || echo 0)"
    had_ff="$(state_val "$pack" firefox || echo 0)"
    had_fp="$(state_val "$pack" flatpak || echo 0)"
    if (( OPT_GDM )); then had_gdm=1; fi
    if (( OPT_FIREFOX )); then had_ff=1; fi
    if (( OPT_FLATPAK )); then had_fp=1; fi

    if [[ $pack == gse-gdm ]] || { (( had_gdm )) && [[ $pack != colloid && $pack != fluent && $pack != material-gnome && $pack != kayozxo-tahoe && $pack != gdm-settings ]]; }; then
        confirm_action "privileged GDM uninstall for $pack" || return 1
    fi

    echo "=== Uninstalling theme pack: $pack ==="

    case "$pack" in
        mactahoe)
            local gtk_dir="$THEME_PACKS_DIR/mactahoe/MacTahoe-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/MacTahoe-icon-theme"
            if [[ -f $gtk_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gtk_dir" bash ./install.sh -r
                if (( had_fp )); then act_in "$gtk_dir" bash ./tweaks.sh -F -r; fi
                if (( had_ff )); then act_in "$gtk_dir" bash ./tweaks.sh -f -r; fi
                if (( had_gdm )); then act_in "$gtk_dir" sudo bash ./tweaks.sh -g -r; fi
            fi
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/MacTahoe* "$LEGACY_THEMES_DIR"/MacTahoe*; do
                act rm -rf -- "$d"
            done
            if ! any_other_pack_uses mactahoe-icons "$pack"; then
                for d in "$ICONS_DIR"/MacTahoe* "$HOME/.icons"/MacTahoe*; do
                    act rm -rf -- "$d"
                done
                act rm -rf -- "$icon_dir"
            fi
            shopt -u nullglob
            remove_gtk4_overrides "MacTahoe"
            act rm -rf -- "$THEME_PACKS_DIR/mactahoe"
            ;;

        kayozxo-tahoe)
            local theme_dir="$THEME_PACKS_DIR/kayozxo-tahoe/GNOME-macOS-Tahoe"
            local icon_dir="$THEME_PACKS_DIR/shared/MacTahoe-icon-theme"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            # kayozxo -u wipes ~/.config/gtk-4.0/gtk.css unconditionally; only run it
            # when gtk.css is not a symlink owned by another theme (e.g. MacTahoe).
            local _kz_gtk4_other=0 _kz_tgt=""
            if [[ -L $CONFIG_HOME/gtk-4.0/gtk.css ]]; then
                _kz_tgt="$(readlink -m "$CONFIG_HOME/gtk-4.0/gtk.css" 2>/dev/null || true)"
                if [[ $_kz_tgt != */Tahoe-* ]]; then
                    _kz_gtk4_other=1
                fi
            fi
            if (( ! _kz_gtk4_other )) && [[ -f $theme_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$theme_dir" bash -c 'printf "y\n" | bash ./install.sh -u'
            fi
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/*Tahoe* "$LEGACY_THEMES_DIR"/*Tahoe*; do
                [[ $(basename "$d") == MacTahoe* ]] && continue
                act rm -rf -- "$d"
            done
            if ! any_other_pack_uses mactahoe-icons "$pack"; then
                for d in "$ICONS_DIR"/MacTahoe* "$HOME/.icons"/MacTahoe*; do
                    act rm -rf -- "$d"
                done
                act rm -rf -- "$icon_dir"
            fi
            if ! any_other_pack_uses whitesur-cursors "$pack"; then
                for d in "$ICONS_DIR"/WhiteSur-cursors* "$HOME/.icons"/WhiteSur-cursors*; do
                    act rm -rf -- "$d"
                done
                act rm -rf -- "$cur_dir"
            fi
            shopt -u nullglob
            remove_gtk4_overrides "/Tahoe-"
            act rm -rf -- "$THEME_PACKS_DIR/kayozxo-tahoe"
            ;;

        whitesur)
            local gtk_dir="$THEME_PACKS_DIR/whitesur/WhiteSur-gtk-theme"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            if [[ -f $gtk_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gtk_dir" bash ./install.sh -r
                if (( had_fp )); then act_in "$gtk_dir" bash ./tweaks.sh -F -r; fi
                if (( had_ff )); then act_in "$gtk_dir" bash ./tweaks.sh -f -r; fi
                if (( had_gdm )); then act_in "$gtk_dir" sudo bash ./tweaks.sh -g -r; fi
            fi
            if ! any_other_pack_uses whitesur-cursors "$pack"; then
                shopt -s nullglob
                local c
                for c in "$ICONS_DIR"/WhiteSur-cursors* "$HOME/.icons"/WhiteSur-cursors*; do
                    act rm -rf -- "$c"
                done
                shopt -u nullglob
                act rm -rf -- "$cur_dir"
            fi
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/WhiteSur* "$LEGACY_THEMES_DIR"/WhiteSur* "$ICONS_DIR"/WhiteSur-dark* "$ICONS_DIR"/WhiteSur-light* "$ICONS_DIR"/WhiteSur "$HOME/.icons"/WhiteSur-dark* "$HOME/.icons"/WhiteSur-light* "$HOME/.icons"/WhiteSur; do
                act rm -rf -- "$d"
            done
            shopt -u nullglob
            remove_gtk4_overrides "WhiteSur"
            act rm -rf -- "$THEME_PACKS_DIR/whitesur"
            ;;

        colloid)
            local gtk_dir="$THEME_PACKS_DIR/colloid/Colloid-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/Colloid-icon-theme"
            if [[ -f $gtk_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gtk_dir" bash ./install.sh -r
            fi
            if ! any_other_pack_uses colloid-icons "$pack"; then
                shopt -s nullglob
                local d
                for d in "$ICONS_DIR"/Colloid* "$HOME/.icons"/Colloid*; do
                    act rm -rf -- "$d"
                done
                shopt -u nullglob
                act rm -rf -- "$icon_dir"
            fi
            shopt -s nullglob
            local t
            for t in "$THEMES_DIR"/Colloid* "$LEGACY_THEMES_DIR"/Colloid*; do
                act rm -rf -- "$t"
            done
            shopt -u nullglob
            remove_gtk4_overrides "Colloid"
            act rm -rf -- "$THEME_PACKS_DIR/colloid"
            ;;

        graphite)
            local gtk_dir="$THEME_PACKS_DIR/graphite/Graphite-gtk-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/Colloid-icon-theme"
            if [[ -f $gtk_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gtk_dir" bash ./install.sh -r
                if (( had_gdm )); then act_in "$gtk_dir" sudo bash ./install.sh -r -g; fi
            fi
            if ! any_other_pack_uses colloid-icons "$pack"; then
                shopt -s nullglob
                local d
                for d in "$ICONS_DIR"/Colloid* "$HOME/.icons"/Colloid*; do
                    act rm -rf -- "$d"
                done
                shopt -u nullglob
                act rm -rf -- "$icon_dir"
            fi
            shopt -s nullglob
            local t
            for t in "$THEMES_DIR"/Graphite* "$LEGACY_THEMES_DIR"/Graphite*; do
                act rm -rf -- "$t"
            done
            shopt -u nullglob
            remove_gtk4_overrides "Graphite"
            act rm -rf -- "$THEME_PACKS_DIR/graphite"
            ;;

        fluent)
            local gtk_dir="$THEME_PACKS_DIR/fluent/Fluent-gtk-theme"
            if [[ -f $gtk_dir/install.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gtk_dir" bash ./install.sh -u
            fi
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/Fluent* "$LEGACY_THEMES_DIR"/Fluent* "$ICONS_DIR"/Fluent* "$ICONS_DIR"/.Fluent-* "$HOME/.icons"/Fluent* "$HOME/.icons"/.Fluent-*; do
                act rm -rf -- "$d"
            done
            shopt -u nullglob
            remove_gtk4_overrides "Fluent"
            act rm -rf -- "$THEME_PACKS_DIR/fluent"
            ;;

        flat-remix)
            local shell_dir="$THEME_PACKS_DIR/flat-remix/flat-remix-gnome"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            if (( had_gdm )) && [[ -f $shell_dir/Makefile || $DRY_RUN -eq 1 ]]; then
                act_in "$shell_dir" sudo make uninstall
            fi
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/Flat-Remix* "$LEGACY_THEMES_DIR"/Flat-Remix* "$ICONS_DIR"/Flat-Remix* "$HOME/.icons"/Flat-Remix*; do
                act rm -rf -- "$d"
            done
            if ! any_other_pack_uses whitesur-cursors "$pack"; then
                for d in "$ICONS_DIR"/WhiteSur-cursors* "$HOME/.icons"/WhiteSur-cursors*; do
                    act rm -rf -- "$d"
                done
                act rm -rf -- "$cur_dir"
            fi
            shopt -u nullglob
            act rm -rf -- "$THEME_PACKS_DIR/flat-remix"
            ;;

        material-gnome)
            local icon_dir="$THEME_PACKS_DIR/shared/MoreWaita"
            shopt -s nullglob
            local d
            for d in "$THEMES_DIR"/Material-Gnome* "$LEGACY_THEMES_DIR"/Material-Gnome* "$ICONS_DIR"/Bibata-Material-* "$HOME/.icons"/Bibata-Material-*; do
                act rm -rf -- "$d"
            done
            shopt -u nullglob
            if ! any_other_pack_uses morewaita "$pack"; then
                act rm -rf -- "$ICONS_DIR/MoreWaita" "$icon_dir"
            fi
            if (( had_fp )); then
                echo "○ material-gnome --flatpak added user Flatpak filesystem overrides; review $DATA_HOME/flatpak/overrides/global to clean unused entries"
            fi
            remove_gtk4_overrides "Material-Gnome"
            act rm -rf -- "$THEME_PACKS_DIR/material-gnome"
            ;;

        modular-adwaita)
            local shell_dir="$THEME_PACKS_DIR/shared/Marble-shell-theme"
            local icon_dir="$THEME_PACKS_DIR/shared/MoreWaita"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            if (( had_gdm )) && [[ -f $shell_dir/install.py || $DRY_RUN -eq 1 ]]; then
                act_in "$shell_dir" sudo python3 install.py --gdm -r
            fi
            if ! any_other_pack_uses marble "$pack"; then
                shopt -s nullglob
                local d
                for d in "$THEMES_DIR"/Marble* "$LEGACY_THEMES_DIR"/Marble*; do
                    act rm -rf -- "$d"
                done
                shopt -u nullglob
                act rm -rf -- "$shell_dir"
            fi
            if ! any_other_pack_uses morewaita "$pack"; then
                act rm -rf -- "$ICONS_DIR/MoreWaita" "$icon_dir"
            fi
            if ! any_other_pack_uses whitesur-cursors "$pack"; then
                shopt -s nullglob
                local c
                for c in "$ICONS_DIR"/WhiteSur-cursors* "$HOME/.icons"/WhiteSur-cursors*; do
                    act rm -rf -- "$c"
                done
                shopt -u nullglob
                act rm -rf -- "$cur_dir"
            fi
            ;;

        modular-gruvbox)
            local shell_dir="$THEME_PACKS_DIR/shared/Marble-shell-theme"
            local cur_dir="$THEME_PACKS_DIR/shared/WhiteSur-cursors"
            if (( had_gdm )) && [[ -f $shell_dir/install.py || $DRY_RUN -eq 1 ]]; then
                act_in "$shell_dir" sudo python3 install.py --gdm -r
            fi
            if ! any_other_pack_uses marble "$pack"; then
                shopt -s nullglob
                local d
                for d in "$THEMES_DIR"/Marble* "$LEGACY_THEMES_DIR"/Marble*; do
                    act rm -rf -- "$d"
                done
                shopt -u nullglob
                act rm -rf -- "$shell_dir"
            fi
            act rm -rf -- "$ICONS_DIR/Gruvbox-Plus-Dark" "$ICONS_DIR/Gruvbox-Plus-Light" "$THEME_PACKS_DIR/modular-gruvbox"
            if ! any_other_pack_uses whitesur-cursors "$pack"; then
                shopt -s nullglob
                local c
                for c in "$ICONS_DIR"/WhiteSur-cursors* "$HOME/.icons"/WhiteSur-cursors*; do
                    act rm -rf -- "$c"
                done
                shopt -u nullglob
                act rm -rf -- "$cur_dir"
            fi
            ;;

        gse-gdm)
            local gdm_dir="$THEME_PACKS_DIR/gse-gdm/gse-gdm-extension"
            if [[ -f $gdm_dir/uninstall.sh || $DRY_RUN -eq 1 ]]; then
                act_in "$gdm_dir" sudo bash ./uninstall.sh
            fi
            act rm -rf -- "$THEME_PACKS_DIR/gse-gdm"
            ;;

        gdm-settings)
            if command -v flatpak >/dev/null 2>&1; then
                act flatpak uninstall -y io.github.realmazharhussain.GdmSettings || true
            fi
            ;;
    esac

    local had_color
    had_color="$(state_val "$pack" color || echo dark)"
    act rm -f -- "$STATE_DIR/$pack"

    if [[ $pack != gse-gdm && $pack != gdm-settings ]] && ! any_desktop_pack_installed; then
        if have_session_bus && [[ -f $REPO_ROOT/desktop/scripts/theme-setup.sh ]]; then
            echo "→ No theme pack active; restoring stock Adwaita..."
            if [[ $had_color == light ]] && command -v gsettings >/dev/null 2>&1; then
                act gsettings set org.gnome.desktop.interface color-scheme prefer-dark
            fi
            act bash "$REPO_ROOT/desktop/scripts/theme-setup.sh"
        fi
    fi

    echo "✓ Uninstalled theme pack: $pack"
}

uninstall_all() {
    confirm_action "uninstall of all managed theme packs" || return 1
    local found=0 p rc=0
    local _prev_yes=$ASSUME_YES
    ASSUME_YES=1
    for p in "${ALL_PACKS[@]}"; do
        if pack_installed "$p"; then
            found=1
            uninstall_pack "$p" || { rc=$?; break; }
        fi
    done
    ASSUME_YES=$_prev_yes
    if (( rc != 0 )); then
        return "$rc"
    fi
    if (( ! found )); then
        echo "No managed theme packs installed."
        if have_session_bus && [[ -f $REPO_ROOT/desktop/scripts/theme-setup.sh ]]; then
            act bash "$REPO_ROOT/desktop/scripts/theme-setup.sh"
        fi
    fi
}

show_status() {
    local installed=() p
    for p in "${ALL_PACKS[@]}"; do
        if pack_installed "$p"; then
            installed+=("$p")
        fi
    done
    echo "Theme pack cache: $THEME_PACKS_DIR"
    if (( ${#installed[@]} > 0 )); then
        echo "Installed packs:  ${installed[*]}"
    else
        echo "Installed packs:  none (stock Adwaita)"
    fi
    if command -v gsettings >/dev/null 2>&1 && have_session_bus; then
        echo "Active GTK:       $(gset_get org.gnome.desktop.interface gtk-theme)"
        echo "Active Icons:     $(gset_get org.gnome.desktop.interface icon-theme)"
        echo "Active Cursor:    $(gset_get org.gnome.desktop.interface cursor-theme)"
        if gsettings list-schemas 2>/dev/null | grep -qx org.gnome.shell.extensions.user-theme; then
            echo "Active Shell:     $(gset_get org.gnome.shell.extensions.user-theme name)"
        fi
    fi
}

# Direct non-interactive CLI actions
if [[ -n $ACTION ]]; then
    case "$ACTION" in
        status) show_status ;;
        install) install_pack "$TARGET_PACK" ;;
        uninstall)
            if [[ $TARGET_PACK == all ]]; then
                uninstall_all
            else
                uninstall_pack "$TARGET_PACK"
            fi
            ;;
    esac
    exit 0
fi

# Interactive GUI/TUI/plain loop
IN_GUI=1
DEFAULT_MENU_ITEM="install"
ui_init "$UI_REQ" "Dotfiles · GNOME Theme Packs" "THEME_UI" || exit 1
trap ui_theme_cleanup EXIT
ui_theme_init

gui_install_flow() {
    local pack extras color_choice
    pack="$(ui_menu "Choose a GNOME theme pack to install" \
        mactahoe "MacTahoe macOS suite (vinceliuice GTK/Libadwaita + Shell + Icons + Cursors)" \
        kayozxo-tahoe "GNOME-macOS-Tahoe (kayozxo GTK/Libadwaita -la + Shell + Icons + Cursors)" \
        whitesur "WhiteSur macOS suite (GTK/Libadwaita + Shell + Icons + Cursors)" \
        colloid "Colloid flat/Material suite (GTK/Libadwaita + Shell + Icons + Cursors)" \
        graphite "Graphite flat monochrome suite (GTK/Libadwaita + Shell + Icons + Cursors)" \
        fluent "Fluent rounded suite (GTK/Libadwaita + Shell + Icons + Cursors)" \
        flat-remix "Flat Remix suite (GNOME Shell + GTK/Icons + Cursors; opt-in GDM uses sudo)" \
        material-gnome "Material-Gnome Material 3 (GTK/Libadwaita + Shell + MoreWaita + Bibata)" \
        modular-adwaita "GNOME 51-safe Adwaita stack (Marble Shell + adw-gtk3 + MoreWaita + Cursors)" \
        modular-gruvbox "GNOME 51-safe Gruvbox stack (Marble Shell + adw-gtk3 + Gruvbox-Plus + Cursors)")" || return 0

    color_choice="$(ui_menu "Variant for $pack" \
        dark "Dark variant (default)" \
        light "Light variant")" || return 0
    OPT_COLOR="$color_choice"

    OPT_GDM=0; OPT_FIREFOX=0; OPT_FLATPAK=0
    extras="$(ui_checklist "Optional extras for $pack (all opt-in; GDM warns on GNOME 51 gresource)" \
        GDM "Apply GDM login screen theme (uses sudo; may reset on gnome-shell upgrade)" off \
        FIREFOX "Apply matching Firefox theme (MacTahoe / WhiteSur)" off \
        FLATPAK "Apply Flatpak theme override" off)" || return 0
    if printf '%s\n' "$extras" | grep -qx GDM; then OPT_GDM=1; fi
    if printf '%s\n' "$extras" | grep -qx FIREFOX; then OPT_FIREFOX=1; fi
    if printf '%s\n' "$extras" | grep -qx FLATPAK; then OPT_FLATPAK=1; fi

    if install_pack "$pack"; then
        ui_msg "Installed theme pack: $pack"
    else
        ui_msg "Install failed for: $pack (check terminal output)"
    fi
}

gui_uninstall_flow() {
    local items=() p pack
    OPT_GDM=0; OPT_FIREFOX=0; OPT_FLATPAK=0
    for p in "${ALL_PACKS[@]}"; do
        if pack_installed "$p"; then
            items+=("$p" "Installed: $p")
        fi
    done
    if (( ${#items[@]} == 0 )); then
        items=(
            mactahoe "MacTahoe suite"
            kayozxo-tahoe "GNOME-macOS-Tahoe suite"
            whitesur "WhiteSur suite"
            colloid "Colloid suite"
            graphite "Graphite suite"
            fluent "Fluent suite"
            flat-remix "Flat Remix suite"
            material-gnome "Material-Gnome suite"
            modular-adwaita "Modular Adwaita stack"
            modular-gruvbox "Modular Gruvbox stack"
            gse-gdm "gse-gdm-extension"
            gdm-settings "gdm-settings Flatpak"
        )
    else
        items+=(all "Uninstall ALL installed theme packs & restore Adwaita")
    fi

    pack="$(ui_menu "Choose a theme pack to uninstall" "${items[@]}")" || return 0
    if [[ $pack == all ]]; then
        if uninstall_all; then
            ui_msg "Uninstalled all theme packs and restored stock Adwaita."
        else
            ui_msg "Uninstall failed (check terminal output)."
        fi
    else
        if uninstall_pack "$pack"; then
            ui_msg "Uninstalled theme pack: $pack"
        else
            ui_msg "Uninstall failed for: $pack (check terminal output)."
        fi
    fi
}

gui_gdm_flow() {
    local pick
    OPT_GDM=0; OPT_FIREFOX=0; OPT_FLATPAK=0
    pick="$(ui_menu "Standalone GDM login screen tools (GNOME 51 safe)" \
        install-gse "Install gse-gdm-extension (GNOME 42-51 safe, uses sudo)" \
        uninstall-gse "Uninstall gse-gdm-extension (uses sudo)" \
        install-settings "Install Login Manager Settings Flatpak (gdm-settings)" \
        uninstall-settings "Uninstall Login Manager Settings Flatpak")" || return 0
    case "$pick" in
        install-gse)
            if install_pack gse-gdm; then ui_msg "Installed gse-gdm-extension."; else ui_msg "Failed to install gse-gdm-extension."; fi
            ;;
        uninstall-gse)
            if uninstall_pack gse-gdm; then ui_msg "Uninstalled gse-gdm-extension."; else ui_msg "Failed to uninstall gse-gdm-extension."; fi
            ;;
        install-settings)
            if install_pack gdm-settings; then ui_msg "Installed gdm-settings Flatpak."; else ui_msg "Failed to install gdm-settings."; fi
            ;;
        uninstall-settings)
            if uninstall_pack gdm-settings; then ui_msg "Uninstalled gdm-settings Flatpak."; else ui_msg "Failed to uninstall gdm-settings."; fi
            ;;
    esac
}

while true; do
    choice="$(ui_menu "GNOME Theme Packs Manager (stock Adwaita remains install.sh default)" \
        install "Install / apply a theme pack" \
        uninstall "Uninstall a theme pack (reverts to Adwaita)" \
        gdm "Standalone GDM tools (gse-gdm / gdm-settings)" \
        status "Show installed packs & active GNOME theme" \
        adwaita "Reset desktop to stock Adwaita now" \
        quit "Quit")" || choice=quit
    # shellcheck disable=SC2034 # consumed by ui_menu in provision/lib/ui-menu.sh
    DEFAULT_MENU_ITEM="$choice"
    case "$choice" in
        install) gui_install_flow ;;
        uninstall) gui_uninstall_flow ;;
        gdm) gui_gdm_flow ;;
        status) ui_msg "$(show_status)" ;;
        adwaita)
            if act bash "$REPO_ROOT/desktop/scripts/theme-setup.sh"; then
                ui_msg "Desktop reset to stock Adwaita."
            else
                ui_msg "theme-setup.sh failed (check terminal output)."
            fi
            ;;
        quit|*) exit 0 ;;
    esac
done
