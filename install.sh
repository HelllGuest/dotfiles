#!/bin/bash

# Arch GNOME Rice Installer
# Run from a GNOME session terminal after first login (Stage B in README).
# dconf, extension enable, and gsettings steps need an active user session.
#
# Interactive TTY opens a TUI menu (dialog/whiptail/plain) so you can run
# everything, pick sections, or use a preset. Non-TTY or --all runs full install.

# Ensure we are in the repo root
cd "$(dirname "$0")" || exit 1

# Stow targets $HOME; makepkg/AUR refuse root. Never sudo ./install.sh.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "error: run as your desktop user, not root (sudo ./install.sh stows into /root)" >&2
    exit 1
fi

# Ensure user-local tool paths are on PATH on fresh first-boot bash sessions
for _p in "$HOME/.opencode/bin" "$HOME/.npm-global/bin" "${PNPM_HOME:-$HOME/.local/share/pnpm}" "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_p:"*) ;;
        *) export PATH="$_p:$PATH" ;;
    esac
done
unset _p

# ── Sections & CLI / Menu selection ──────────────────────────────────────
INSTALL_DEFAULT_SECTIONS=(packages profile flatpak fonts stow aur shell desktop dev ai apps hardening check)
INSTALL_ALL_SECTIONS=("${INSTALL_DEFAULT_SECTIONS[@]}" configure)

install_usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Run interactively on a TTY to open the TUI menu, or pass flags for GUI / selective runs.
Non-TTY sessions (CI / headless VM) run the full default install automatically.

Options:
  --menu           Open interactive menu (default on interactive TTY)
  --all, -y        Run all default sections non-interactively
  --tui            Force terminal TUI (dialog / whiptail)
  --gui            Force GNOME GUI dialogs (zenity)
  --plain          Force plain text prompts
  --only LIST      Run only comma-separated sections (no menu)
  --skip LIST      Run default sections except comma-separated ones (no menu)
  --minimal        Skip heavy IDE/mobile/RE package bundles (MINIMAL_PACKAGES=1)
  --list           List available section names and exit
  -h, --help       Show this help and exit

Environment:
  INSTALL_ALL=1    Same as --all
  INSTALL_UI=...   plain|tui|dialog|whiptail|gui|zenity
  MINIMAL_PACKAGES=1 / SKIP_AI_IDES=1 / SKIP_MOBILE_DEV=1 / SKIP_RE_TOOLS=1
  SKIP_THEME=1 / SKIP_RICE=1 / SKIP_OLLAMA=1 / SKIP_FOXCAGE=1 / SKIP_OPS_HYGIENE=1 / CONFIGURE=1
EOF
}

install_list_sections() {
    cat <<'EOF'
packages   Pacman packages (pacman.txt), input cleanup, bootvine
profile    Machine hardware profile (apply-profile.sh)
flatpak    Flatpak apps (packages/flatpak.txt)
fonts      Fonts (provision/scripts/install-fonts.sh)
stow       Dotfiles stow + /etc system configs + user timers
aur        AUR packages (packages/aur.txt)
shell      zsh login shell, Node 22 (fnm), atuin history, zram
desktop    GNOME session, location, Console, GDM, theme, terminal rice, extensions
dev        Git global config + Neovim plugins/treesitter
ai         AI & RE stack (skills, Headroom, agents, ghidra-cli, Obscura, Ollama)
apps       Optional apps (PhotoGIMP, foxcage)
configure  Stage B configurator (firewalld, labs, detonate, rice) [opt-in]
hardening  Privacy hardener, ops hygiene, Tailscale firewalld
check      Health check (check.sh) + config validation
EOF
}

_install_valid_section() {
    local s
    for s in "${INSTALL_ALL_SECTIONS[@]}"; do
        [[ $s == "$1" ]] && return 0
    done
    return 1
}

INSTALL_MODE="auto"
INSTALL_CLI_MODE=0
INSTALL_UI="${INSTALL_UI:-}"
INSTALL_ONLY=""
INSTALL_SKIP=""
INSTALL_SECTIONS=""

if [[ ${INSTALL_ALL:-0} == 1 ]]; then
    INSTALL_MODE="all"
fi

while (($#)); do
    case "$1" in
        --menu) INSTALL_MODE="menu"; INSTALL_CLI_MODE=1 ;;
        --all|-y) INSTALL_MODE="all"; INSTALL_CLI_MODE=1 ;;
        --gui|--zenity) INSTALL_UI="gui"; (( INSTALL_CLI_MODE == 0 )) && INSTALL_MODE="menu" ;;
        --tui) INSTALL_UI="tui"; (( INSTALL_CLI_MODE == 0 )) && INSTALL_MODE="menu" ;;
        --plain) INSTALL_UI="plain"; (( INSTALL_CLI_MODE == 0 )) && INSTALL_MODE="menu" ;;
        --only)
            [[ $# -ge 2 ]] || { echo "install.sh: --only requires a comma-separated list" >&2; exit 2; }
            INSTALL_ONLY="$2"; INSTALL_MODE="filter"; INSTALL_CLI_MODE=1; shift
            ;;
        --only=*)
            INSTALL_ONLY="${1#--only=}"; INSTALL_MODE="filter"; INSTALL_CLI_MODE=1
            ;;
        --skip)
            [[ $# -ge 2 ]] || { echo "install.sh: --skip requires a comma-separated list" >&2; exit 2; }
            INSTALL_SKIP="$2"; INSTALL_MODE="filter"; INSTALL_CLI_MODE=1; shift
            ;;
        --skip=*)
            INSTALL_SKIP="${1#--skip=}"; INSTALL_MODE="filter"; INSTALL_CLI_MODE=1
            ;;
        --minimal) export MINIMAL_PACKAGES=1 ;;
        --list) install_list_sections; exit 0 ;;
        -h|--help) install_usage; exit 0 ;;
        *)
            echo "install.sh: unknown option '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n $INSTALL_ONLY && -n $INSTALL_SKIP ]]; then
    echo "install.sh: use either --only or --skip, not both" >&2
    exit 2
fi

if [[ -n $INSTALL_ONLY ]]; then
    IFS=',' read -r -a _req <<<"$INSTALL_ONLY"
    _chosen=()
    for _s in "${_req[@]}"; do
        [[ -z $_s ]] && continue
        if ! _install_valid_section "$_s"; then
            echo "install.sh: unknown section '$_s' (run ./install.sh --list)" >&2
            exit 2
        fi
        _chosen+=("$_s")
    done
    if [[ ${#_chosen[@]} -eq 0 ]]; then
        echo "install.sh: --only list is empty" >&2
        exit 2
    fi
    INSTALL_SECTIONS="$(printf '%s\n' "${_chosen[@]}")"
    if printf '%s\n' "$INSTALL_SECTIONS" | grep -qx 'configure'; then
        CONFIGURE=1
        SKIP_CONFIGURE=0
    fi
    unset _req _chosen _s
elif [[ -n $INSTALL_SKIP ]]; then
    IFS=',' read -r -a _sk <<<"$INSTALL_SKIP"
    for _s in "${_sk[@]}"; do
        [[ -z $_s ]] && continue
        if ! _install_valid_section "$_s"; then
            echo "install.sh: unknown section '$_s' (run ./install.sh --list)" >&2
            exit 2
        fi
    done
    _base=("${INSTALL_DEFAULT_SECTIONS[@]}")
    if [[ ${CONFIGURE:-0} == 1 || ${CONFIGURE:-} == Y ]]; then
        _base+=(configure)
    fi
    _chosen=()
    for _d in "${_base[@]}"; do
        _drop=0
        for _s in "${_sk[@]}"; do
            [[ $_d == "$_s" ]] && _drop=1
        done
        (( _drop == 0 )) && _chosen+=("$_d")
    done
    if [[ ${#_chosen[@]} -eq 0 ]]; then
        echo "install.sh: nothing left to run after --skip" >&2
        exit 0
    fi
    INSTALL_SECTIONS="$(printf '%s\n' "${_chosen[@]}")"
    unset _sk _base _chosen _d _s _drop
elif [[ $INSTALL_MODE == menu || ( $INSTALL_MODE == auto && ( ( -t 0 && -t 1 ) || $INSTALL_UI == gui || $INSTALL_UI == zenity ) ) ]]; then
    # shellcheck source=provision/lib/ui-menu.sh
    source provision/lib/ui-menu.sh
    ui_init "$INSTALL_UI" "Dotfiles Installer · Stage B" "INSTALL_UI" || exit 1
    trap ui_theme_cleanup EXIT
    ui_theme_init
    # shellcheck disable=SC2034 # consumed by ui_menu in lib/ui-menu.sh
    DEFAULT_MENU_ITEM="custom"

    while true; do
        _pick="$(ui_menu "Choose what to install" \
            custom    "Custom install — pick sections (checklist)" \
            full      "Full install — all standard sections" \
            core      "Core system (packages, profile, stow, shell, dev, check)" \
            desktop   "Dotfiles & desktop (stow, desktop, dev, check)" \
            ai        "AI & RE stack (ai, check)" \
            configure "Stage B modules (configure.sh: firewalld, labs, rice)" \
            check     "Health check & config validation only" \
            quit      "Quit")" || _pick="quit"
        # shellcheck disable=SC2034 # consumed by ui_menu in lib/ui-menu.sh
        DEFAULT_MENU_ITEM="$_pick"
        case "$_pick" in
            custom)
                if _sel="$(UI_CANCEL_LABEL=Back ui_checklist "Select sections to run" \
                    packages  "Pacman packages (pacman.txt), input cleanup, bootvine" on \
                    profile   "Machine hardware profile (apply-profile.sh)" on \
                    flatpak   "Flatpak apps (packages/flatpak.txt)" on \
                    fonts     "Fonts (provision/scripts/install-fonts.sh)" on \
                    stow      "Dotfiles stow + /etc system configs + user timers" on \
                    aur       "AUR packages (packages/aur.txt)" on \
                    shell     "zsh login shell, Node 22 (fnm), atuin history, zram" on \
                    desktop   "GNOME session, location, Console, GDM, theme, extensions" on \
                    dev       "Git global config + Neovim plugins/treesitter" on \
                    ai        "AI & RE stack (skills, Headroom, agents, ghidra-cli, Obscura, Ollama)" on \
                    apps      "Optional apps (PhotoGIMP, foxcage)" on \
                    configure "Stage B configurator (firewalld, labs, detonate, rice)" off \
                    hardening "Privacy hardener, ops hygiene, Tailscale firewalld" on \
                    check     "Health check (check.sh) + config validation" on)"; then
                    _valid=()
                    _bad=()
                    while IFS= read -r _s; do
                        [[ -z $_s || $_s == NONE ]] && continue
                        if _install_valid_section "$_s"; then
                            _valid+=("$_s")
                        else
                            _bad+=("$_s")
                        fi
                    done <<<"$_sel"
                    if [[ ${#_bad[@]} -gt 0 ]]; then
                        ui_msg "Unknown section(s): ${_bad[*]}"
                        unset _sel _valid _bad _s
                        continue
                    fi
                    if [[ ${#_valid[@]} -eq 0 ]]; then
                        ui_msg "No sections selected."
                        unset _sel _valid _bad _s
                        continue
                    fi
                    INSTALL_SECTIONS="$(printf '%s\n' "${_valid[@]}")"
                    if printf '%s\n' "$INSTALL_SECTIONS" | grep -qx 'configure'; then
                        CONFIGURE=1
                        SKIP_CONFIGURE=0
                    fi
                    unset _sel _valid _bad _s
                    break
                fi
                ;;
            full)
                INSTALL_SECTIONS=""
                break
                ;;
            core)
                INSTALL_SECTIONS="$(printf '%s\n' packages profile stow shell dev check)"
                break
                ;;
            desktop)
                INSTALL_SECTIONS="$(printf '%s\n' stow desktop dev check)"
                break
                ;;
            ai)
                INSTALL_SECTIONS="$(printf '%s\n' ai check)"
                break
                ;;
            configure)
                ui_theme_cleanup
                CONFIGURE_UI="$UI" CONFIGURE_FROM_INSTALL=1 bash provision/scripts/configure.sh
                _rc=$?
                if (( _rc == 0 )); then
                    ui_theme_init
                    continue
                fi
                if [[ ${INSTALL_PAUSE:-0} == 1 && -t 0 ]]; then
                    read -r -p "Press Enter to close..." _
                fi
                exit "$_rc"
                ;;
            check)
                INSTALL_SECTIONS="check"
                break
                ;;
            quit|*)
                ui_theme_cleanup
                echo "Installation cancelled."
                exit 0
                ;;
        esac
    done
    unset _pick
fi

# Every failed step sets this (the run continues); exit 1 at the end if set.
# Only explicit opt-outs (SKIP_*=1 or menu/section selection) skip a step.
INSTALL_FAILED=0
INSTALL_FAIL_REASONS=()
: "${INSTALL_SECTIONS:=}"
section_on() {
    [[ -z "$INSTALL_SECTIONS" ]] && return 0
    printf '%s\n' "$INSTALL_SECTIONS" | grep -qx "$1"
}
fail_step() {
    if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
        printf '\e[1;31m✗ %s\e[0m\n' "$1"
    else
        echo "$1"
    fi
    INSTALL_FAILED=1
    INSTALL_FAIL_REASONS+=("$1")
}

# Progress bars (provision/lib/progress.sh). Stub when tests eval this helper
# block without the lib on disk.
# shellcheck source=provision/lib/progress.sh
if [[ -f provision/lib/progress.sh ]]; then
    source provision/lib/progress.sh
elif [[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/provision/lib/progress.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]:-$0}")/provision/lib/progress.sh"
else
    ui_bar() { printf '[----------]'; }
    progress_line() { :; }
    progress_banner() { :; }
fi
# Ceiling = run_step sites + advance_progress sites (conditionals leave headroom).
INSTALL_STEP=0
INSTALL_STEPS=45

# Tick the Stage B bar without wrapping a command (pacman/stow/profile/…).
advance_progress() {
    local label="$1"
    INSTALL_STEP=$((INSTALL_STEP + 1))
    progress_line "$INSTALL_STEP" "$INSTALL_STEPS" "$label"
}

# run_step LABEL CMD...: a failing step is recorded (exit 1 at the end) and the
# run continues, so one broken step never silently drops the others.
run_step() {
    local label="$1"; shift
    advance_progress "$label"
    "$@" || fail_step "$label failed — re-run: $*"
}
# need_cmd CMD LABEL [SOURCE]: a missing prerequisite is a failure, not a
# reason to skip quietly. SOURCE names where CMD should have come from.
need_cmd() {
    command -v "$1" >/dev/null 2>&1 && return 0
    fail_step "$2 not installed: '$1' missing (${3:-packages/pacman.txt} install failed?)"
    return 1
}
NODE_SRC="Node 22 via fnm, step 2.1"

echo "Starting installation..."
if [[ -n "$INSTALL_SECTIONS" ]]; then
    echo "Selected sections: $(printf '%s' "$INSTALL_SECTIONS" | tr '\n' ' ')"
fi
progress_banner "Stage B · $(ui_bar 0 20) 0/${INSTALL_STEPS}"

SUDO_KEEPALIVE_PID=""
_install_cleanup() {
    if declare -F ui_theme_cleanup >/dev/null 2>&1; then
        ui_theme_cleanup
    fi
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
    fi
}
trap _install_cleanup EXIT

_install_needs_sudo() {
    local s
    for s in packages profile flatpak fonts stow aur shell desktop dev ai apps configure hardening; do
        section_on "$s" && return 0
    done
    return 1
}

# Authenticate once and keep sudo alive for the whole run: AUR builds take
# long enough for a later sudo prompt to time out unattended, which used to
# drop every built AUR package without installing it.
if _install_needs_sudo; then
    if ! sudo -v; then
        if [[ -t 2 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
            printf '\e[1;31m✗ sudo authentication failed — install.sh needs sudo.\e[0m\n' >&2
        else
            echo "sudo authentication failed — install.sh needs sudo." >&2
        fi
        exit 1
    fi
    ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
fi

# Legacy touchpad udev/inhibit cleanup (if present from older dotfiles)
if section_on packages && [ -f "desktop/scripts/cleanup-input-overrides.sh" ]; then
    run_step "Input override cleanup" bash desktop/scripts/cleanup-input-overrides.sh
fi

# 1. Install packages (before machine profile — NVIDIA/Optimus needs nvidia-* present)
if section_on packages; then
if [ -f "packages/pacman.txt" ]; then
    advance_progress "pacman packages"
    echo "Installing pacman packages..."
    REPO_ROOT="$PWD"
    # shellcheck source=provision/lib/pkg-lists.sh
    source provision/lib/pkg-lists.sh
    mapfile -t pkgs < <(pacman_targets)
    # Older dotfiles built AUR bootvine-git: same files as official bootvine and
    # no conflicts= metadata, so installing bootvine would abort the whole
    # transaction ("conflicting files"). Swap it out first.
    if pacman -Q bootvine-git >/dev/null 2>&1 && printf '%s\n' "${pkgs[@]}" | grep -qx 'bootvine'; then
        echo "Replacing AUR bootvine-git with the official bootvine package..."
        if ! sudo pacman -R --noconfirm bootvine-git; then
            # Keep bootvine out of the batch so the conflict cannot abort it.
            fail_step "could not remove bootvine-git, bootvine not installed (sudo pacman -R bootvine-git && sudo pacman -S bootvine)"
            mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx 'bootvine')
        fi
    fi
    if [ "${#pkgs[@]}" -gt 0 ]; then
        # -Syu: installing from a stale sync db is a partial upgrade on Arch and
        # 404s on rotated mirrors (one bad target aborts the whole batch).
        if ! sudo pacman -Syu --needed --noconfirm -- "${pkgs[@]}"; then
            echo "Batch install failed — retrying one package at a time..."
            mapfile -t missing < <(printf '%s\n' "${pkgs[@]}" | missing_pkgs)
            for p in "${missing[@]}"; do
                sudo pacman -S --needed --noconfirm -- "$p" \
                    || fail_step "pacman: could not install $p — sudo pacman -S $p"
            done
        fi
    fi
    unset pkgs missing p
    # A kernel upgrade removes the running kernel's modules: later steps that
    # load one (fuse-overlayfs for podman, zram, libvirt) fail until a reboot.
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        fail_step "Kernel upgraded during this run (running $(uname -r) has no modules left): reboot, then re-run ./install.sh — module-loading steps below may fail until then"
    fi
fi
fi

# 1.04 Boot screen (bootvine): stage 2 + shutdown only. No sd-bootvine initrd
# hook, so the LUKS unlock prompt stays the stock sd-encrypt flow.
# bootvine-shutdown.service has its own [Install] (no Also=), enable both.
if section_on packages; then
if pacman -Q bootvine >/dev/null 2>&1; then
    run_step "bootvine enable" sudo systemctl enable bootvine.service bootvine-shutdown.service
else
    fail_step "bootvine not installed (packages/pacman.txt) — boot screen not enabled"
fi
fi

# 1.05 Machine profile (hostname override, else hardware detect)
# Runs after pacman so thinkpad-p15 can enable nvidia-*.service and rebuild UKIs.
if section_on profile && [ -f "provision/scripts/apply-profile.sh" ]; then
    advance_progress "machine profile"
    bash provision/scripts/apply-profile.sh \
        || fail_step "Profile application failed (sudo / hardware setup) — see output above."
fi

# 1.1 Install Flatpaks
if section_on flatpak && [ -f "provision/scripts/install-flatpaks.sh" ]; then
    echo "Installing flatpak packages..."
    run_step "Flatpak install" bash provision/scripts/install-flatpaks.sh
fi

# 1.2 Install Fonts
if section_on fonts && [ -f "provision/scripts/install-fonts.sh" ]; then
    run_step "Font install" bash provision/scripts/install-fonts.sh
fi

# 2. Setup symlinks using Stow or Fallback
# system-setup.sh installs /etc/makepkg.conf.d/zz-x86-64-v3.conf before AUR builds.
if section_on stow; then
STOW_CMD="stow"
if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow not found. Using minimal-stow fallback..."
    STOW_CMD="../scripts/minimal-stow.sh"
    chmod +x scripts/minimal-stow.sh
fi

advance_progress "stow dotfiles"
echo "Applying dotfiles..."
mkdir -p "$HOME/.config"
# shellcheck source=provision/lib/skel.sh
source provision/lib/skel.sh
remove_unmodified_skel "$PWD/stow"
remove_stage_a_seeds "$PWD/stow" || fail_step "Stage A ~/.zshrc not cleared — stow will refuse the zsh package"
cd stow || exit 1
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir" \
            || fail_step "stow failed for package: $dir"
    else
        $STOW_CMD "$dir" "$HOME" \
            || fail_step "minimal-stow failed for package: $dir"
    fi
done
cd .. || exit 1
echo "Installing system/etc as root-owned files (system/scripts/system-setup.sh — /etc must not symlink into \$HOME)."
bash system/scripts/system-setup.sh || fail_step "System setup failed (sudo required)."
fi

# 2.05 AUR after system-setup so paru/makepkg see x86-64-v3 flags
if section_on aur && [ -f "provision/scripts/install-aur.sh" ]; then
    echo "Installing AUR packages..."
    run_step "AUR install" bash provision/scripts/install-aur.sh
fi

# 2.0a User units shipped by stow packages (stow links them; nothing enabled them).
# daemon-reload first: the manager has not seen the freshly linked unit file.
if section_on stow; then
    run_step "tmp-semgrep-cleanup.timer" bash -c \
        'systemctl --user daemon-reload && systemctl --user enable --now tmp-semgrep-cleanup.timer'
fi

# 2.0 Login shell: zsh (the dotfiles' primary shell; kitty, Ghostty, Console
# and the rest start the login shell). Stage A sets it at useradd; other hosts
# may still be on bash.
if section_on shell; then
if need_cmd zsh "zsh login shell"; then
    zsh_path="$(command -v zsh)"
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$(readlink -f "$login_shell")" != "$(readlink -f "$zsh_path")" ]; then
        if grep -qx "$zsh_path" /etc/shells; then
            run_step "Login shell → zsh" sudo usermod -s "$zsh_path" "$USER"
        else
            fail_step "$zsh_path is not in /etc/shells — login shell left as $login_shell"
        fi
    fi
    unset zsh_path login_shell
fi
fi

# 2.1 Bootstrap Node.js LTS via fnm (avoids bleeding-edge system node breaking native addons)
if section_on shell; then
if need_cmd fnm "Node.js LTS via fnm"; then
    echo "Setting up Node.js LTS (22) via fnm..."
    eval "$(fnm env --shell bash)"
    advance_progress "Node 22 (fnm install)"
    if fnm install 22; then
        run_step "Node 22 (fnm default)" fnm default 22
        run_step "Node 22 (fnm use)" fnm use 22
    else
        fail_step "Node 22 (fnm install) failed — re-run: fnm install 22"
    fi
fi
elif command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
fi

# 2.2 Import shell history into atuin
# The rc files keep history under XDG_STATE_HOME; atuin only finds it via
# HISTFILE (import auto would look for ~/.zsh_history and fail). No history yet
# (fresh install) means nothing to import, not a failure. Import once: atuin
# re-imports duplicate entries (bash history has no timestamps), and after the
# first import atuin records new commands itself.
if section_on shell; then
if need_cmd atuin "atuin history import"; then
    _hist_found=0
    _stamp_dir="${XDG_DATA_HOME:-$HOME/.local/share}/atuin"
    for _sh in zsh bash; do
        _hf="${XDG_STATE_HOME:-$HOME/.local/state}/$_sh/history"
        if [ -s "$_hf" ]; then
            _hist_found=1
            if [ -e "$_stamp_dir/.dotfiles-imported-$_sh" ]; then
                echo "✓ $_sh history already imported into atuin"
            elif env HISTFILE="$_hf" atuin import "$_sh"; then
                if ! { mkdir -p "$_stamp_dir" && : >"$_stamp_dir/.dotfiles-imported-$_sh"; }; then
                    fail_step "atuin import ($_sh) done but not recorded ($_stamp_dir) — the next run would duplicate it"
                fi
            else
                fail_step "atuin import ($_sh) failed — re-run: HISTFILE=$_hf atuin import $_sh"
            fi
        fi
    done
    unset _stamp_dir
    if [ "$_hist_found" = 0 ]; then
        echo "○ no shell history yet — nothing for atuin to import"
    fi
    unset _hist_found _sh _hf
fi
fi

# 2.3 Materialize zram config (early-boot safe; not a $HOME symlink)
if section_on shell && [ -f "system/scripts/zram-setup.sh" ]; then
    run_step "zram setup" bash system/scripts/zram-setup.sh
fi

# 3. Restore GNOME session (dconf + extensions + tablet handler)
if section_on desktop; then
if [ -f "desktop/scripts/gnome-session-setup.sh" ]; then
    # Extensions are fetched + enabled once, at 3.7/3.8 (failures recorded there).
    run_step "GNOME session setup" env SKIP_GNOME_EXTENSIONS=1 bash desktop/scripts/gnome-session-setup.sh
fi

if [ -f "security/scripts/location-setup.sh" ]; then
    run_step "Location setup" bash security/scripts/location-setup.sh
fi

# 3.0 GNOME Console (kgx app settings only — shortcuts in desktop/gnome/dconf/user.conf)
if [ -f "desktop/scripts/gnome-console-setup.sh" ]; then
    run_step "GNOME Console setup" bash desktop/scripts/gnome-console-setup.sh
fi

# 3.2 GDM login screen (Wayland, greeter dconf, udev)
if [ -f "desktop/scripts/gdm-setup.sh" ]; then
    run_step "GDM setup" bash desktop/scripts/gdm-setup.sh
fi

# 3.2a Theme: stock Adwaita. Cleans leftover greeter hooks once.
# Needs a GNOME login session. Opt out: SKIP_THEME=1 (headless VM).
if [ "${SKIP_THEME:-0}" = 1 ]; then
    echo "Skipping theme setup (SKIP_THEME=1)."
elif [ -f "desktop/scripts/theme-setup.sh" ]; then
    run_step "Theme setup" bash desktop/scripts/theme-setup.sh
fi

# 3.2b Terminal/CLI rice (Contour wrapper, fastfetch logos, htop, bat/fzf,
# GNOME accent + Text Editor). Re-stows rice packages; applies gruvbox defaults.
# Opt out: SKIP_RICE=1 (headless / no sudo pacman for rice deps).
if [ "${SKIP_RICE:-0}" = 1 ]; then
    echo "Skipping terminal rice (SKIP_RICE=1)."
elif [ -f "desktop/scripts/rice-setup.sh" ]; then
    run_step "Terminal rice" bash desktop/scripts/rice-setup.sh
fi
fi

# 3.3 Git global config (identity, hooks, signing). Noninteractive when
# stdin is not a TTY or GIT_SETUP_NONINTERACTIVE=1 (applies defaults).
if section_on dev; then
if [ -f "desktop/scripts/git-setup.sh" ]; then
    run_step "Git setup" bash desktop/scripts/git-setup.sh
fi

# 3.4 Neovim (lazy.nvim, treesitter parsers)
if [ -f "desktop/scripts/nvim-setup.sh" ]; then
    run_step "Neovim setup" bash desktop/scripts/nvim-setup.sh
fi
fi

if section_on ai; then
# 3.5 Kit skills first (creates ~/.claude, ~/.cursor, … that Headroom merges into)
if [ -f "ai/scripts/sync-agent-skills.sh" ]; then
    run_step "Agent skills pre-sync" bash ai/scripts/sync-agent-skills.sh
fi

# 3.5a Headroom (Claude / Cursor context proxy — optional, pipx user-local)
if [ -f "ai/scripts/headroom-setup.sh" ]; then
    run_step "Headroom setup" bash ai/scripts/headroom-setup.sh
fi

# 3.5b OpenCode + Kimi CLIs + MCP configs (before caveman so opencode is detected)
if [ -f "ai/scripts/install-coding-agents.sh" ]; then
    if need_cmd npm "OpenCode/Kimi" "$NODE_SRC"; then
        run_step "Coding agents" env SKIP_CAVEMAN_OPENCODE=1 bash ai/scripts/install-coding-agents.sh
    fi
fi

# 3.5c Caveman (terse voice + ultracave/megacave; pinned installer + SHA-256)
if [ -f "ai/scripts/install-caveman.sh" ]; then
    if need_cmd npm "Caveman" "$NODE_SRC"; then
        run_step "Caveman install" env SKIP_SKILL_SYNC=1 bash ai/scripts/install-caveman.sh
    fi
fi

# 3.5c1 Ponytail (lazy senior dev mode; pinned tag + skills/hooks/plugins)
if [ -f "ai/scripts/install-ponytail.sh" ]; then
    if need_cmd node "Ponytail" "$NODE_SRC"; then
        run_step "Ponytail install" env SKIP_SKILL_SYNC=1 bash ai/scripts/install-ponytail.sh
    fi
fi

# 3.5d Android UI skills (Compose anti-slop + Material 3; pinned refs)
if [ -f "ai/scripts/install-android-ui-skills.sh" ]; then
    if need_cmd npx "Android UI skills" "$NODE_SRC"; then
        run_step "Android UI skills" env SKIP_SKILL_SYNC=1 bash ai/scripts/install-android-ui-skills.sh
    fi
fi

# 3.5e ghidra-cli (optional Rust bridge; needs pacman ghidra + rust/cargo)
if [ -f "ai/scripts/install-ghidra-cli.sh" ]; then
    if [[ ${MINIMAL_PACKAGES:-0} == 1 || ${SKIP_RE_TOOLS:-0} == 1 ]]; then
        echo "Skipping ghidra-cli (MINIMAL_PACKAGES/SKIP_RE_TOOLS)."
    elif pacman -Q ghidra >/dev/null 2>&1; then
        run_step "ghidra-cli install" bash ai/scripts/install-ghidra-cli.sh
    else
        fail_step "ghidra-cli not installed: pacman package ghidra missing (packages/pacman.txt)"
    fi
fi

# 3.5f REA backends live in lab-re (JDK21/Ghidra/jadx). Host install-rea is
# optional only (needs host JDK>=21); prefer: lab-re --check && lab-re

# 3.5f1 Obscura headless browser + MCP (OpenCode/Cursor/Claude)
if [ -f "ai/scripts/install-obscura.sh" ]; then
    run_step "Obscura install" bash ai/scripts/install-obscura.sh
fi

# 3.5f2 RE agent skills (leanrea, reverse-engineering, android-RE, ghidra-iterative-re)
if [ -f "ai/scripts/install-re-skills.sh" ]; then
    if need_cmd npx "RE skills" "$NODE_SRC"; then
        run_step "RE skills" env SKIP_SKILL_SYNC=1 bash ai/scripts/install-re-skills.sh
    fi
fi

# 3.5g Third-party skill packs (cloudflare, emil, vercel, … — packages/agent-skills.txt)
if [ -f "ai/scripts/install-ecosystem-skills.sh" ]; then
    if need_cmd npx "Ecosystem skills" "$NODE_SRC"; then
        run_step "Ecosystem skills" env SKIP_SKILL_SYNC=1 bash ai/scripts/install-ecosystem-skills.sh
    fi
fi

# 3.5h Hub mirror after AI installers (→ Claude/Cursor/OpenCode/Kimi)
if [ -f "ai/scripts/sync-agent-skills.sh" ]; then
    run_step "Agent skills post-sync" bash ai/scripts/sync-agent-skills.sh
fi

# 3.5i Caveman OpenCode plugin (after hub sync; coding-agents skipped this in 3.5b)
if [ -f "ai/scripts/install-coding-agents.sh" ] && command -v npm >/dev/null 2>&1; then
    if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ]; then
        run_step "Caveman OpenCode plugin" env ONLY_CAVEMAN_OPENCODE=1 bash ai/scripts/install-coding-agents.sh
    fi
fi

# 3.5j AI stack extras (Continue FIM config, P15 OpenCode↔ollama, hr-proxy unit).
# Cores (Headroom / coding-agents / Caveman / Ponytail) already ran above.
if [ -f "ai/scripts/ai-stack-setup.sh" ]; then
    run_step "AI stack extras" env AI_STACK_EXTRAS_ONLY=1 bash ai/scripts/ai-stack-setup.sh
fi

# 3.5k Local LLM on P15 (ollama-cuda + qwen pulls; no-op on other hosts).
# Opt out: SKIP_OLLAMA=1 ./install.sh
if [ "${SKIP_OLLAMA:-0}" != 1 ] && [ -f "ai/scripts/ollama-setup.sh" ]; then
    run_step "ollama setup" bash ai/scripts/ollama-setup.sh
fi
fi

if section_on apps; then
# 3.6 PhotoGIMP (Photoshop-like GIMP layout — optional)
if [ -f "provision/scripts/install-photogimp.sh" ]; then
    run_step "PhotoGIMP setup" bash provision/scripts/install-photogimp.sh
fi

# 3.6a foxcage: Firefox in a rootless Podman container (pinned commit + SHA-256)
if [ "${SKIP_FOXCAGE:-0}" = 1 ]; then
    echo "Skipping foxcage (SKIP_FOXCAGE=1)."
elif ! need_cmd podman "foxcage"; then
    :
elif [ -f "provision/scripts/install-foxcage.sh" ]; then
    run_step "foxcage install" bash provision/scripts/install-foxcage.sh
fi
fi

if section_on desktop; then
# 3.7 Extension downloads: EGO Full pack + Caffeine + Dash2Dock, before enable
if [ -f "desktop/scripts/fetch-gnome-extensions.sh" ]; then
    run_step "GNOME extension downloads" bash desktop/scripts/fetch-gnome-extensions.sh
fi

# 3.8 Enable GNOME Extensions (list in desktop/gnome/extensions.txt)
if [ -f "desktop/scripts/install-extensions.sh" ]; then
    run_step "GNOME extensions" bash desktop/scripts/install-extensions.sh
fi
fi

# 3.9 Stage B configurator (firewalld / ollama / labs / rice) — opt-in.
# Default: print hint only (Stage A already seeds firewalld drop). Force with
# CONFIGURE=1; skip with SKIP_CONFIGURE=1. Headless: CONFIGURE_UI=plain.
# Runs after stow (containers storage.conf, continue, starship), fnm (node/npm
# for SETUP_AI) and the extension pass, so its modules find what they build on.
if section_on configure && [ "${SKIP_CONFIGURE:-0}" != 1 ] && [ -f provision/scripts/configure.sh ]; then
    if [ "${CONFIGURE:-0}" = 1 ] || [ "${CONFIGURE:-}" = Y ]; then
        if [ ! -t 0 ] && [ -z "${CONFIGURE_UI:-}" ] && [ "${UI:-}" != "zenity" ]; then
            export CONFIGURE_UI=plain
        elif [ -n "${UI:-}" ] && [ -z "${CONFIGURE_UI:-}" ]; then
            export CONFIGURE_UI="$UI"
        fi
        # One checklist pass then continue install (no interactive menu loop).
        CONFIGURE_ONCE=1 bash provision/scripts/configure.sh \
            || fail_step "configure.sh failed — see module output above."
    elif [ -t 0 ]; then
        echo "Stage B modules: run  bash provision/scripts/configure.sh  (or CONFIGURE=1 ./install.sh)"
    fi
fi

if section_on hardening; then
# 4. Privacy Hardening (before health check so telemetry probes reflect final state)
if [ -f "security/scripts/privacy-hardener.sh" ]; then
    advance_progress "privacy hardener"
    bash security/scripts/privacy-hardener.sh || fail_step "Privacy hardener failed."
fi

# 4.1 Ops hygiene: weekly paccache.timer + optional cache/flatpak prune
# Full prune: default. Skip with SKIP_OPS_HYGIENE=1. usbguard/dnscrypt stay opt-in
# (bash security/scripts/usbguard-setup.sh / bash security/scripts/dnscrypt-setup.sh).
if [ "${SKIP_OPS_HYGIENE:-0}" != 1 ] && [ -f "security/scripts/ops-hygiene.sh" ]; then
    run_step "Ops hygiene" bash security/scripts/ops-hygiene.sh
fi

# 4.5 Tailscale + firewalld (tailscale is in pacman.txt; need_cmd fails if missing)
if [ -f "security/scripts/firewalld-tailscale.sh" ] && need_cmd tailscale "Tailscale firewalld rules"; then
    run_step "Tailscale firewalld rules" bash security/scripts/firewalld-tailscale.sh
fi
fi

# 5. Final Health Check
if section_on check; then
if [ -f "scripts/check.sh" ]; then
    advance_progress "health check"
    bash scripts/check.sh \
        || fail_step "Health check reported failures (✗) — see output above."
fi

if [ -f "scripts/validate-configs.sh" ]; then
    run_step "Config validation" bash scripts/validate-configs.sh
fi
fi

if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-} != dumb ]]; then
    _IC_R=$'\e[1;31m' _IC_G=$'\e[1;32m' _IC_0=$'\e[0m'
else
    _IC_R='' _IC_G='' _IC_0=''
fi
if [ "$INSTALL_FAILED" -ne 0 ]; then
    printf '%sInstallation finished with failures:%s\n' "$_IC_R" "$_IC_0"
    for _r in "${INSTALL_FAIL_REASONS[@]}"; do
        printf '  %s-%s %s\n' "$_IC_R" "$_IC_0" "$_r"
    done
    unset _r
    if [[ ${INSTALL_PAUSE:-0} == 1 && -t 0 ]]; then
        read -r -p "Press Enter to close..." _
    fi
    exit 1
fi

printf '%sInstallation complete!%s\n' "$_IC_G" "$_IC_0"
if [[ ${INSTALL_PAUSE:-0} == 1 && -t 0 ]]; then
    read -r -p "Press Enter to close..." _
fi
