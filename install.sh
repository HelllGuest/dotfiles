#!/bin/bash

# Arch GNOME Rice Installer
# Run from a GNOME session terminal after first login (Stage B in README).
# dconf, extension enable, and gsettings steps need an active user session.

# Ensure we are in the repo root
cd "$(dirname "$0")" || exit 1

# Ensure user-local tool paths are on PATH on fresh first-boot bash sessions
for _p in "$HOME/.opencode/bin" "$HOME/.npm-global/bin" "${PNPM_HOME:-$HOME/.local/share/pnpm}" "$HOME/go/bin" "$HOME/.cargo/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_p:"*) ;;
        *) export PATH="$_p:$PATH" ;;
    esac
done
unset _p

# Every failed step sets this (the run continues); exit 1 at the end if set.
# Only explicit opt-outs (SKIP_*=1) skip a step.
INSTALL_FAILED=0
INSTALL_FAIL_REASONS=()
fail_step() {
    echo "$1"
    INSTALL_FAILED=1
    INSTALL_FAIL_REASONS+=("$1")
}

# Progress bars (scripts/lib/progress.sh). Stub when tests eval this helper
# block without the lib on disk.
# shellcheck source=scripts/lib/progress.sh
if [[ -f scripts/lib/progress.sh ]]; then
    source scripts/lib/progress.sh
elif [[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/lib/progress.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/lib/progress.sh"
else
    ui_bar() { printf '[----------]'; }
    progress_line() { :; }
    progress_banner() { :; }
fi
# Ceiling = run_step sites + advance_progress sites (conditionals leave headroom).
INSTALL_STEP=0
INSTALL_STEPS=44

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
progress_banner "Stage B · $(ui_bar 0 20) 0/${INSTALL_STEPS}"

# Authenticate once and keep sudo alive for the whole run: AUR builds take
# long enough for a later sudo prompt to time out unattended, which used to
# drop every built AUR package without installing it.
sudo -v || { echo "sudo authentication failed — install.sh needs sudo." >&2; exit 1; }
( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# Legacy touchpad udev/inhibit cleanup (if present from older dotfiles)
if [ -f "scripts/cleanup-input-overrides.sh" ]; then
    run_step "Input override cleanup" bash scripts/cleanup-input-overrides.sh
fi

# 1. Install packages (before machine profile — NVIDIA/Optimus needs nvidia-* present)
if [ -f "packages/pacman.txt" ]; then
    advance_progress "pacman packages"
    echo "Installing pacman packages..."
    REPO_ROOT="$PWD"
    # shellcheck source=scripts/lib/pkg-lists.sh
    source scripts/lib/pkg-lists.sh
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

# 1.04 Boot screen (bootvine): stage 2 + shutdown only. No sd-bootvine initrd
# hook, so the LUKS unlock prompt stays the stock sd-encrypt flow.
# bootvine-shutdown.service has its own [Install] (no Also=), enable both.
if pacman -Q bootvine >/dev/null 2>&1; then
    run_step "bootvine enable" sudo systemctl enable bootvine.service bootvine-shutdown.service
else
    fail_step "bootvine not installed (packages/pacman.txt) — boot screen not enabled"
fi

# 1.05 Machine profile (hostname override, else hardware detect)
# Runs after pacman so thinkpad-p15 can enable nvidia-*.service and rebuild UKIs.
if [ -f "scripts/apply-profile.sh" ]; then
    advance_progress "machine profile"
    bash scripts/apply-profile.sh \
        || fail_step "Profile application failed (sudo / hardware setup) — see output above."
fi

# 1.06 Stage B configurator (firewalld / ollama / labs / rice) — opt-in.
# Default: print hint only (Stage A already seeds firewalld drop). Force with
# CONFIGURE=1; skip with SKIP_CONFIGURE=1. Headless: CONFIGURE_UI=plain.
if [ "${SKIP_CONFIGURE:-0}" != 1 ] && [ -f scripts/configure.sh ]; then
    if [ "${CONFIGURE:-0}" = 1 ] || [ "${CONFIGURE:-}" = Y ]; then
        if [ ! -t 0 ] && [ -z "${CONFIGURE_UI:-}" ]; then
            export CONFIGURE_UI=plain
        fi
        # One checklist pass then continue install (no interactive menu loop).
        CONFIGURE_ONCE=1 bash scripts/configure.sh \
            || fail_step "configure.sh failed — see module output above."
    elif [ -t 0 ]; then
        echo "Stage B modules: run  bash scripts/configure.sh  (or CONFIGURE=1 ./install.sh)"
    fi
fi

# 1.1 Install Flatpaks
if [ -f "scripts/install-flatpaks.sh" ]; then
    echo "Installing flatpak packages..."
    run_step "Flatpak install" bash scripts/install-flatpaks.sh
fi

# 1.15 Install AUR packages (optional — requires yay/paru)
if [ -f "scripts/install-aur.sh" ]; then
    echo "Installing AUR packages..."
    run_step "AUR install" bash scripts/install-aur.sh
fi

# 1.2 Install Fonts
if [ -f "scripts/install-fonts.sh" ]; then
    run_step "Font install" bash scripts/install-fonts.sh
fi

# 2. Setup symlinks using Stow or Fallback
STOW_CMD="stow"
if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow not found. Using minimal-stow fallback..."
    STOW_CMD="../scripts/minimal-stow.sh"
    chmod +x scripts/minimal-stow.sh
fi

advance_progress "stow dotfiles"
echo "Applying dotfiles..."
# shellcheck source=scripts/lib/skel.sh
source scripts/lib/skel.sh
remove_unmodified_skel "$PWD/stow"
remove_stage_a_seeds "$PWD/stow" || fail_step "Stage A ~/.zshrc not cleared — stow will refuse the zsh package"
cd stow || exit 1
for dir in */; do
    dir=${dir%/}
    echo "Processing $dir..."
    if [ "$dir" = "zram" ]; then
        echo "Skipping zram stow (use scripts/zram-setup.sh — /etc must not symlink into \$HOME)."
    elif [ "$dir" = "system" ]; then
        echo "Installing $dir as root-owned files (scripts/system-setup.sh — /etc must not symlink into \$HOME)."
        bash ../scripts/system-setup.sh || fail_step "System setup failed (sudo required)."
    elif [ "$dir" = "gdm" ]; then
        echo "Skipping gdm (handled by scripts/gdm-setup.sh)."
    elif [ "$STOW_CMD" == "stow" ]; then
        stow -R -t "$HOME" "$dir" \
            || fail_step "stow failed for package: $dir"
    else
        $STOW_CMD "$dir" "$HOME" \
            || fail_step "minimal-stow failed for package: $dir"
    fi
done
cd .. || exit 1

# 2.0a User units shipped by stow packages (stow links them; nothing enabled them).
run_step "tmp-semgrep-cleanup.timer" systemctl --user enable --now tmp-semgrep-cleanup.timer

# 2.0 Login shell: zsh (the dotfiles' primary shell; kitty, Ghostty, Console
# and the rest start the login shell). Stage A sets it at useradd; other hosts
# may still be on bash.
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

# 2.1 Bootstrap Node.js LTS via fnm (avoids bleeding-edge system node breaking native addons)
if need_cmd fnm "Node.js LTS via fnm"; then
    echo "Setting up Node.js LTS (22) via fnm..."
    eval "$(fnm env --shell bash)"
    run_step "Node 22 (fnm install)" fnm install 22
    run_step "Node 22 (fnm default)" fnm default 22
    run_step "Node 22 (fnm use)" fnm use 22
    eval "$(fnm env --shell bash)"
fi

# 2.2 Import shell history into atuin
# The rc files keep history under XDG_STATE_HOME; atuin only finds it via
# HISTFILE (import auto would look for ~/.zsh_history and fail). No history yet
# (fresh install) means nothing to import, not a failure. Import once: atuin
# re-imports duplicate entries (bash history has no timestamps), and after the
# first import atuin records new commands itself.
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

# 2.3 Materialize zram config (early-boot safe; not a $HOME symlink)
if [ -f "scripts/zram-setup.sh" ]; then
    run_step "zram setup" bash scripts/zram-setup.sh
fi

# 3. Restore GNOME session (dconf + extensions + tablet handler)
if [ -f "scripts/gnome-session-setup.sh" ]; then
    run_step "GNOME session setup" bash scripts/gnome-session-setup.sh
fi

if [ -f "scripts/location-setup.sh" ]; then
    run_step "Location setup" bash scripts/location-setup.sh
fi

# 3.0 GNOME Console (kgx app settings only — shortcuts in gnome/dconf/user.conf)
if [ -f "scripts/gnome-console-setup.sh" ]; then
    run_step "GNOME Console setup" bash scripts/gnome-console-setup.sh
fi

# 3.2 GDM login screen (Wayland, greeter dconf, udev)
if [ -f "scripts/gdm-setup.sh" ]; then
    run_step "GDM setup" bash scripts/gdm-setup.sh
fi

# 3.2a Theme: Orchis-Dark + Tela-blue-dark + Bibata-Modern-Ice for the session,
# libadwaita apps (~/.config/gtk-4.0), Flatpaks and the GDM login screen.
if [ -f "scripts/theme-setup.sh" ]; then
    run_step "Theme setup" bash scripts/theme-setup.sh
fi

# 3.3 Git global config (identity, hooks, signing). Noninteractive when
# stdin is not a TTY or GIT_SETUP_NONINTERACTIVE=1 (applies defaults).
if [ -f "scripts/git-setup.sh" ]; then
    run_step "Git setup" bash scripts/git-setup.sh
fi

# 3.4 Neovim (lazy.nvim, treesitter parsers)
if [ -f "scripts/nvim-setup.sh" ]; then
    run_step "Neovim setup" bash scripts/nvim-setup.sh
fi

# 3.5 Headroom (Claude / Cursor context proxy — optional, pipx user-local)
if [ -f "scripts/headroom-setup.sh" ]; then
    run_step "Headroom setup" bash scripts/headroom-setup.sh
fi

# 3.5a Kit skills first (fallback if post-AI sync fails later)
if [ -f "scripts/sync-agent-skills.sh" ]; then
    run_step "Agent skills pre-sync" bash scripts/sync-agent-skills.sh
fi

# 3.5b OpenCode + Kimi CLIs + MCP configs (before caveman so opencode is detected)
if [ -f "scripts/install-coding-agents.sh" ]; then
    if need_cmd npm "OpenCode/Kimi" "$NODE_SRC"; then
        run_step "Coding agents" env SKIP_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh
    fi
fi

# 3.5c Caveman (terse voice + ultracave/megacave; pinned installer + SHA-256)
if [ -f "scripts/install-caveman.sh" ]; then
    if need_cmd npm "Caveman" "$NODE_SRC"; then
        run_step "Caveman install" env SKIP_SKILL_SYNC=1 bash scripts/install-caveman.sh
    fi
fi

# 3.5c1 Ponytail (lazy senior dev mode; pinned tag + skills/hooks/plugins)
if [ -f "scripts/install-ponytail.sh" ]; then
    if need_cmd node "Ponytail" "$NODE_SRC"; then
        run_step "Ponytail install" env SKIP_SKILL_SYNC=1 bash scripts/install-ponytail.sh
    fi
fi

# 3.5d Android UI skills (Compose anti-slop + Material 3; pinned refs)
if [ -f "scripts/install-android-ui-skills.sh" ]; then
    if need_cmd npx "Android UI skills" "$NODE_SRC"; then
        run_step "Android UI skills" env SKIP_SKILL_SYNC=1 bash scripts/install-android-ui-skills.sh
    fi
fi

# 3.5e ghidra-cli (optional Rust bridge; needs pacman ghidra + rust/cargo)
if [ -f "scripts/install-ghidra-cli.sh" ]; then
    if pacman -Q ghidra >/dev/null 2>&1; then
        run_step "ghidra-cli install" bash scripts/install-ghidra-cli.sh
    else
        fail_step "ghidra-cli not installed: pacman package ghidra missing (packages/pacman.txt)"
    fi
fi

# 3.5f REA backends live in lab-re (JDK21/Ghidra/jadx). Host install-rea is
# optional only (needs host JDK>=21); prefer: lab-re --check && lab-re

# 3.5f1 Obscura headless browser + MCP (OpenCode/Cursor/Claude)
if [ -f "scripts/install-obscura.sh" ]; then
    run_step "Obscura install" bash scripts/install-obscura.sh
fi

# 3.5f2 RE agent skills (leanrea, reverse-engineering, android-RE, ghidra-iterative-re)
if [ -f "scripts/install-re-skills.sh" ]; then
    if need_cmd npx "RE skills" "$NODE_SRC"; then
        run_step "RE skills" env SKIP_SKILL_SYNC=1 bash scripts/install-re-skills.sh
    fi
fi

# 3.5g Third-party skill packs (cloudflare, emil, vercel, … — packages/agent-skills.txt)
if [ -f "scripts/install-ecosystem-skills.sh" ]; then
    if need_cmd npx "Ecosystem skills" "$NODE_SRC"; then
        run_step "Ecosystem skills" env SKIP_SKILL_SYNC=1 bash scripts/install-ecosystem-skills.sh
    fi
fi

# 3.5h Hub mirror after AI installers (→ Claude/Cursor/OpenCode/Kimi)
if [ -f "scripts/sync-agent-skills.sh" ]; then
    run_step "Agent skills post-sync" bash scripts/sync-agent-skills.sh
fi

# 3.5i Caveman OpenCode plugin (after hub sync; coding-agents skipped this in 3.5b)
if [ -f "scripts/install-coding-agents.sh" ] && command -v npm >/dev/null 2>&1; then
    if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ]; then
        run_step "Caveman OpenCode plugin" env ONLY_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh
    fi
fi

# 3.5j AI stack extras (Continue FIM config, P15 OpenCode↔ollama, hr-proxy unit).
# Cores (Headroom / coding-agents / Caveman / Ponytail) already ran above.
if [ -f "scripts/ai-stack-setup.sh" ]; then
    run_step "AI stack extras" env AI_STACK_EXTRAS_ONLY=1 bash scripts/ai-stack-setup.sh
fi

# 3.5k Local LLM on P15 (ollama-cuda + qwen pulls; no-op on other hosts).
# Opt out: SKIP_OLLAMA=1 ./install.sh
if [ "${SKIP_OLLAMA:-0}" != 1 ] && [ -f "scripts/ollama-setup.sh" ]; then
    run_step "ollama setup" bash scripts/ollama-setup.sh
fi

# 3.6 PhotoGIMP (Photoshop-like GIMP layout — optional)
if [ -f "scripts/install-photogimp.sh" ]; then
    run_step "PhotoGIMP setup" bash scripts/install-photogimp.sh
fi

# 3.6a foxcage: Firefox in a rootless Podman container (pinned commit + SHA-256)
if [ "${SKIP_FOXCAGE:-0}" = 1 ]; then
    echo "Skipping foxcage (SKIP_FOXCAGE=1)."
elif ! need_cmd podman "foxcage"; then
    :
elif [ -f "scripts/install-foxcage.sh" ]; then
    run_step "foxcage install" bash scripts/install-foxcage.sh
fi

# 3.7 Dash2Dock Animated (EGO — before extension enable)
if [ -f "scripts/install-dash2dock.sh" ]; then
    run_step "Dash2Dock setup" bash scripts/install-dash2dock.sh
fi

# 3.8 Enable GNOME Extensions (list in gnome/extensions.txt)
if [ -f "scripts/install-extensions.sh" ]; then
    run_step "GNOME extensions" bash scripts/install-extensions.sh
fi

# 4. Privacy Hardening (before health check so telemetry probes reflect final state)
if [ -f "scripts/privacy-hardener.sh" ]; then
    advance_progress "privacy hardener"
    bash scripts/privacy-hardener.sh || fail_step "Privacy hardener failed."
fi

# 4.1 Ops hygiene: weekly paccache.timer + optional cache/flatpak prune
# Full prune: default. Skip with SKIP_OPS_HYGIENE=1. usbguard/dnscrypt stay opt-in
# (bash scripts/usbguard-setup.sh / bash scripts/dnscrypt-setup.sh).
if [ "${SKIP_OPS_HYGIENE:-0}" != 1 ] && [ -f "scripts/ops-hygiene.sh" ]; then
    run_step "Ops hygiene" bash scripts/ops-hygiene.sh
fi

# 4.5 Tailscale + firewalld (optional; no-op if firewalld inactive / tailscale absent)
if [ -f "scripts/firewalld-tailscale.sh" ] && need_cmd tailscale "Tailscale firewalld rules"; then
    run_step "Tailscale firewalld rules" bash scripts/firewalld-tailscale.sh
fi

# 5. Final Health Check
if [ -f "scripts/check.sh" ]; then
    advance_progress "health check"
    bash scripts/check.sh \
        || fail_step "Health check reported failures (✗) — see output above."
fi

if [ -f "scripts/validate-configs.sh" ]; then
    run_step "Config validation" bash scripts/validate-configs.sh
fi

if [ "$INSTALL_FAILED" -ne 0 ]; then
    echo "Installation finished with failures:"
    for _r in "${INSTALL_FAIL_REASONS[@]}"; do
        echo "  - $_r"
    done
    unset _r
    exit 1
fi

echo "Installation complete!"
