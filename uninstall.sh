#!/usr/bin/env bash
# uninstall.sh — safe, selective uninstaller for dotfiles.
#
# Defaults to user-level sections (units, stow, ai) with no sudo required.
# Privileged/system sections (browsers, location, system) are opt-in via --all
# or --only. Never removes system packages or personal user data (~/.ssh,
# ~/.gnupg, ~/.gitconfig, browser profiles, secrets).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "error: run as your desktop user, not root (sudo ./uninstall.sh targets /root)" >&2
    exit 1
fi

UNINSTALL_DEFAULT_SECTIONS=(units stow ai)
UNINSTALL_ALL_SECTIONS=(units stow ai browsers location system)

DRY_RUN=0
ASSUME_YES=0
INCLUDE_ALL=0
ONLY_LIST=""
SKIP_LIST=""

uninstall_usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [OPTIONS]

Safely removes dotfiles symlinks, user units, AI rule links, and (optionally)
system/browser/location configs deployed by install.sh. Never uninstalls system
packages or deletes personal data (~/.ssh, ~/.gnupg, ~/.gitconfig, profiles).

Default sections (no sudo): units, stow, ai

Options:
  -n, --dry-run    Preview every action without modifying files
  -y, --yes        Skip confirmation prompt (required when non-interactive)
  --all            Include privileged sections (browsers, location, system)
  --only LIST      Run only comma-separated sections
  --skip LIST      Exclude comma-separated sections
  --list           List available section names and exit
  -h, --help       Show this help and exit

Environment:
  SYSTEM_ROOT=...      Test root prefix instead of / (no sudo)
  AI_RULES_TARGET=...  Installed ai-rules kit path (default: ~/dev/ai-rules)
EOF
}

uninstall_list_sections() {
    cat <<'EOF'
units     Disable dotfiles user systemd units (tmp-semgrep-cleanup, hr-proxy) [default]
stow      Unstow $HOME symlinks from stow/ (safe fallback if stow missing) [default]
ai        Remove ai-rules/agent skill symlinks & kit core.hooksPath [default]
browsers  Remove repo-deployed browser policies & tagged user.js/overrides [opt-in]
location  Remove vpn-location-sync, GeoClue drop-in, NM dispatcher, polkit [opt-in]
system    Remove managed /etc files (system/, zram/, gdm drop-ins, charge) [opt-in]
EOF
}

_valid_section() {
    local s
    for s in "${UNINSTALL_ALL_SECTIONS[@]}"; do
        [[ $s == "$1" ]] && return 0
    done
    return 1
}

while (($#)); do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --all) INCLUDE_ALL=1 ;;
        --only)
            [[ $# -ge 2 ]] || { echo "uninstall.sh: --only requires a comma-separated list" >&2; exit 2; }
            ONLY_LIST="$2"; shift
            ;;
        --only=*) ONLY_LIST="${1#--only=}" ;;
        --skip)
            [[ $# -ge 2 ]] || { echo "uninstall.sh: --skip requires a comma-separated list" >&2; exit 2; }
            SKIP_LIST="$2"; shift
            ;;
        --skip=*) SKIP_LIST="${1#--skip=}" ;;
        --list) uninstall_list_sections; exit 0 ;;
        -h|--help) uninstall_usage; exit 0 ;;
        *)
            echo "uninstall.sh: unknown option '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n "$ONLY_LIST" && -n "$SKIP_LIST" ]]; then
    echo "uninstall.sh: cannot combine --only and --skip" >&2
    exit 2
fi

SECTIONS=()
if [[ -n "$ONLY_LIST" ]]; then
    IFS=',' read -r -a _raw <<< "$ONLY_LIST"
    for s in "${_raw[@]}"; do
        [[ -n "$s" ]] || continue
        _valid_section "$s" || { echo "uninstall.sh: unknown section '$s' (try --list)" >&2; exit 2; }
        SECTIONS+=("$s")
    done
    unset _raw
else
    if (( INCLUDE_ALL )); then
        base=("${UNINSTALL_ALL_SECTIONS[@]}")
    else
        base=("${UNINSTALL_DEFAULT_SECTIONS[@]}")
    fi
    skip_set=" "
    if [[ -n "$SKIP_LIST" ]]; then
        IFS=',' read -r -a _raw <<< "$SKIP_LIST"
        for s in "${_raw[@]}"; do
            [[ -n "$s" ]] || continue
            _valid_section "$s" || { echo "uninstall.sh: unknown section '$s' (try --list)" >&2; exit 2; }
            skip_set+="$s "
        done
        unset _raw
    fi
    for s in "${base[@]}"; do
        [[ "$skip_set" == *" $s "* ]] && continue
        SECTIONS+=("$s")
    done
fi

if [[ ${#SECTIONS[@]} -eq 0 ]]; then
    echo "uninstall.sh: no sections selected." >&2
    exit 0
fi

section_on() {
    local s
    for s in "${SECTIONS[@]}"; do
        [[ $s == "$1" ]] && return 0
    done
    return 1
}

ROOT="${SYSTEM_ROOT:-}"
AI_RULES_TARGET="${AI_RULES_TARGET:-$HOME/dev/ai-rules}"

if [[ -n "$ROOT" ]]; then
    SUDO=()
else
    SUDO=(sudo)
fi

act() {
    if (( DRY_RUN )); then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

rm_user_path() {
    local p="$1"
    if (( DRY_RUN )); then
        printf '[dry-run] rm -f %s\n' "$p"
        return 0
    fi
    rm -f -- "$p"
}

rm_root_path() {
    local p="$1"
    if (( DRY_RUN )); then
        printf '[dry-run] %srm -f %s\n' "${SUDO[*]:+${SUDO[*]} }" "$p"
        return 0
    fi
    "${SUDO[@]}" rm -f -- "$p"
}

# Check existence under $ROOT even inside restricted root-owned dirs (e.g. 0750 /etc/polkit-1/rules.d).
root_path_exists() {
    local p="$1" parent
    if [[ -e "$p" || -L "$p" ]]; then
        return 0
    fi
    if [[ -z "$ROOT" ]]; then
        parent="$(dirname "$p")"
        if [[ -d "$parent" && ! -r "$parent" ]]; then
            if (( DRY_RUN )); then
                if sudo -n test -e "$p" -o -L "$p" 2>/dev/null; then
                    return 0
                fi
                printf '[dry-run] %srm -f %s  # if present (%s unreadable without sudo)\n' \
                    "${SUDO[*]:+${SUDO[*]} }" "$p" "$parent"
                return 1
            fi
            sudo test -e "$p" -o -L "$p" 2>/dev/null
            return $?
        fi
    fi
    return 1
}

# Confirmation gate: never mutate silently when non-interactive without --yes.
if (( ! DRY_RUN && ! ASSUME_YES )); then
    if [[ ! -t 0 ]]; then
        echo "error: non-interactive uninstall requires --yes (-y) or --dry-run (-n)" >&2
        exit 1
    fi
    echo "Selected uninstall sections: ${SECTIONS[*]}"
    read -r -p "Proceed with uninstall? [y/N] " _reply
    case "$_reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    unset _reply
fi

echo "Uninstalling dotfiles (${SECTIONS[*]})$([[ $DRY_RUN == 1 ]] && echo ' [dry-run]' || true)..."

# ── 1. units: disable user systemd units BEFORE unstowing unit files ─────────
if section_on units; then
    echo "--- Disabling user systemd units ---"
    if command -v systemctl >/dev/null 2>&1; then
        for _u in tmp-semgrep-cleanup.timer hr-proxy.service; do
            if systemctl --user is-enabled "$_u" >/dev/null 2>&1 || systemctl --user is-active "$_u" >/dev/null 2>&1; then
                act systemctl --user disable --now "$_u" || echo "○ could not disable $_u"
            fi
        done
        act systemctl --user daemon-reload 2>/dev/null || true
        unset _u
    else
        echo "○ systemctl not found — skipped"
    fi
    echo "✓ User units processed"
fi

# ── 2. stow: remove $HOME symlinks pointing into stow/ ───────────────────────
_prune_empty_parents() {
    local dir="$1" home_real
    home_real="$(realpath -s "$HOME")"
    while [[ "$dir" != "$home_real" && "$dir" != "$home_real/.config" && "$dir" != "$home_real/.local" && "$dir" != "$home_real/.local/share" && "$dir" != "/" && "$dir" != "." ]]; do
        if [[ -d "$dir" && ! -L "$dir" ]]; then
            rmdir "$dir" 2>/dev/null || break
        else
            break
        fi
        dir="$(dirname "$dir")"
    done
}

_fallback_unstow_pkg() {
    local pkg_dir="$1" stow_real="$2"
    local src rel dest target parent dir_target
    while IFS= read -r -d '' src; do
        rel="${src#"$pkg_dir/"}"
        dest="$HOME/$rel"
        # Check folded parent symlinks first (GNU Stow folds whole subdirs).
        parent="$(dirname "$dest")"
        local removed_folded=0
        while [[ "$parent" != "$HOME" && "$parent" != "/" && "$parent" != "." ]]; do
            if [[ -L "$parent" ]]; then
                dir_target="$(readlink -m "$parent" 2>/dev/null || true)"
                if [[ "$dir_target" == "$stow_real/"* || "$dir_target" == "$stow_real" ]]; then
                    rm_user_path "$parent"
                    if (( ! DRY_RUN )); then
                        _prune_empty_parents "$(dirname "$parent")"
                    fi
                    removed_folded=1
                    break
                fi
            fi
            parent="$(dirname "$parent")"
        done
        if (( removed_folded )); then
            continue
        fi

        if [[ -L "$dest" ]]; then
            target="$(readlink -m "$dest" 2>/dev/null || readlink "$dest" 2>/dev/null || true)"
            if [[ "$target" == "$stow_real/"* ]]; then
                rm_user_path "$dest"
                if (( ! DRY_RUN )); then
                    _prune_empty_parents "$(dirname "$dest")"
                fi
            fi
        fi
    done < <(find "$pkg_dir" \
        \( -name Cache -o -name CachedData -o -name 'Code Cache' -o -name GPUCache -o -name Backups -o -name History \) -prune \
        -o \( -type f -o -type l \) -print0)
}

if section_on stow; then
    echo "--- Unstowing \$HOME packages ---"
    STOW_REAL="$(cd "$REPO_ROOT/stow" && pwd -P)"
    use_stow=0
    if [[ "${UNINSTALL_NO_STOW:-0}" != 1 ]] && command -v stow >/dev/null 2>&1; then
        use_stow=1
    fi
    for pkg_path in "$REPO_ROOT"/stow/*/; do
        [[ -d "$pkg_path" ]] || continue
        pkg="$(basename "$pkg_path")"
        if (( use_stow )); then
            if (( DRY_RUN )); then
                printf '[dry-run] stow -d %s -t %s -D %s\n' "$REPO_ROOT/stow" "$HOME" "$pkg"
            else
                stow -d "$REPO_ROOT/stow" -t "$HOME" -D "$pkg" 2>/dev/null || _fallback_unstow_pkg "${pkg_path%/}" "$STOW_REAL"
            fi
        else
            _fallback_unstow_pkg "${pkg_path%/}" "$STOW_REAL"
        fi
    done
    # Local theme override links created by rice-theme (only when symlinks into stow/).
    for _tl in "$HOME/.config/ghostty/theme.local.conf" "$HOME/.config/alacritty/theme.local.toml"; do
        if [[ -L "$_tl" ]]; then
            _tgt="$(readlink -m "$_tl" 2>/dev/null || true)"
            if [[ "$_tgt" == "$STOW_REAL/"* ]]; then
                rm_user_path "$_tl"
            fi
        fi
    done
    unset _tl _tgt
    if section_on units && command -v systemctl >/dev/null 2>&1; then
        act systemctl --user daemon-reload 2>/dev/null || true
    fi
    echo "✓ Stow packages processed"
fi

# ── 3. ai: remove kit/hub symlinks and unset kit core.hooksPath ──────────────
_is_ai_managed_target() {
    local t="$1"
    [[ "$t" == "$AI_RULES_TARGET" || "$t" == "$AI_RULES_TARGET/"* \
        || "$t" == "$REPO_ROOT/ai/rules" || "$t" == "$REPO_ROOT/ai/rules/"* \
        || "$t" == "$HOME/.agents/skills" || "$t" == "$HOME/.agents/skills/"* \
        || "$t" == "${KIMI_CODE_HOME:-$HOME/.kimi-code}/AGENTS.md" ]]
}

if section_on ai; then
    echo "--- Removing AI rules & skill symlinks ---"
    # ~/.local/bin/agentsync
    if [[ -L "$HOME/.local/bin/agentsync" ]]; then
        _t="$(readlink -m "$HOME/.local/bin/agentsync" 2>/dev/null || readlink "$HOME/.local/bin/agentsync" 2>/dev/null || true)"
        if _is_ai_managed_target "$_t"; then
            rm_user_path "$HOME/.local/bin/agentsync"
        fi
    fi

    # Global AGENTS.md / GEMINI.md symlinks
    for _r in \
        "$HOME/.agents/AGENTS.md" \
        "$HOME/.claude/AGENTS.md" \
        "$HOME/.gemini/AGENTS.md" \
        "$HOME/.gemini/GEMINI.md" \
        "$HOME/.gemini/config/AGENTS.md" \
        "$HOME/.gemini/config/GEMINI.md" \
        "$HOME/.codex/AGENTS.md" \
        "$HOME/.kimi/AGENTS.md"
    do
        if [[ -L "$_r" ]]; then
            _t="$(readlink -m "$_r" 2>/dev/null || readlink "$_r" 2>/dev/null || true)"
            if _is_ai_managed_target "$_t"; then
                rm_user_path "$_r"
            fi
        fi
    done

    # Agent skill directories (symlinks only; never delete real vendor dirs)
    for _sdir in \
        "$HOME/.claude/skills" \
        "$HOME/.kiro/skills" \
        "$HOME/.cursor/skills" \
        "$HOME/.gemini/skills" \
        "$HOME/.gemini/config/skills" \
        "$HOME/.codex/skills" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills" \
        "${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills" \
        "$HOME/.agents/skills"
    do
        if [[ -L "$_sdir" ]]; then
            _t="$(readlink -m "$_sdir" 2>/dev/null || readlink "$_sdir" 2>/dev/null || true)"
            if _is_ai_managed_target "$_t"; then
                rm_user_path "$_sdir"
            fi
        elif [[ -d "$_sdir" ]]; then
            shopt -s nullglob
            for _entry in "$_sdir"/*; do
                [[ -L "$_entry" ]] || continue
                _t="$(readlink -m "$_entry" 2>/dev/null || readlink "$_entry" 2>/dev/null || true)"
                if _is_ai_managed_target "$_t"; then
                    rm_user_path "$_entry"
                fi
            done
            shopt -u nullglob
        fi
    done

    # Remove unmodified copies created by sync-agent-skills.sh (never delete edited/merged files)
    for _pair in \
        "${KIMI_CODE_HOME:-$HOME/.kimi-code}/AGENTS.md:AGENTS.md" \
        "$HOME/.kiro/steering/agents.md:AGENTS.md" \
        "$HOME/.cursor/rules/00-agents-pointer.mdc:cursor-mdc/00-agents-pointer.mdc" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md:AGENTS.md"
    do
        _dst="${_pair%%:*}"
        _rel="${_pair#*:}"
        if [[ -f "$_dst" && ! -L "$_dst" ]]; then
            if { [[ -f "$AI_RULES_TARGET/$_rel" ]] && cmp -s "$_dst" "$AI_RULES_TARGET/$_rel"; } \
                || { [[ -f "$REPO_ROOT/ai/rules/$_rel" ]] && cmp -s "$_dst" "$REPO_ROOT/ai/rules/$_rel"; }; then
                rm_user_path "$_dst"
            fi
        fi
    done

    # Stock Claude bridge stub only (@AGENTS.md); keep any customized CLAUDE.md
    _claude_md="$HOME/.claude/CLAUDE.md"
    if [[ -f "$_claude_md" && ! -L "$_claude_md" ]]; then
        _claude_body="$(<"$_claude_md")"
        if [[ "$_claude_body" == "@AGENTS.md" ]]; then
            rm_user_path "$_claude_md"
        fi
        unset _claude_body
    fi
    unset _claude_md

    # Unset global core.hooksPath only if pointing into ai-rules/git-hooks
    if command -v git >/dev/null 2>&1; then
        _hp="$(git config --global --get core.hooksPath 2>/dev/null || true)"
        if [[ -n "$_hp" && ( "$_hp" == "$AI_RULES_TARGET/git-hooks" || "$_hp" == */ai-rules/git-hooks || "$_hp" == */ai/rules/git-hooks ) ]]; then
            act git config --global --unset core.hooksPath
        fi
    fi
    unset _t _r _sdir _entry _pair _dst _rel _hp
    echo "✓ AI symlinks & unmodified rule copies processed (kit at $AI_RULES_TARGET and edited/merged files kept)"
fi

# ── 4. browsers (opt-in): remove repo policies & tagged prefs ──────────────────
if section_on browsers; then
    echo "--- Removing browser policies & tagged prefs ---"
    for _pol in \
        "$ROOT/etc/opt/chrome/policies/managed/00-privacy.json" \
        "$ROOT/etc/brave/policies/managed/00-privacy.json" \
        "$ROOT/etc/firefox/policies/policies.json"
    do
        if root_path_exists "$_pol"; then
            rm_root_path "$_pol"
        fi
    done

    shopt -s nullglob
    _zen_pol_src="$REPO_ROOT/security/browsers/policies/zen-policies.json"
    for _zpol in "${XDG_DATA_HOME:-$HOME/.local/share}"/flatpak/extension/app.zen_browser.zen.systemconfig/*/stable/policies/policies.json; do
        # Only remove unmodified copies of the repo Zen policy (no tag in JSON).
        if [[ -f "$_zpol" && -f "$_zen_pol_src" ]] && cmp -s "$_zpol" "$_zen_pol_src"; then
            rm_user_path "$_zpol"
        fi
    done
    for _zjs in "$HOME/.var/app/app.zen_browser.zen/.zen"/*/user.js; do
        if [[ -f "$_zjs" ]] && grep -q 'browser-hardening\.sh' "$_zjs" 2>/dev/null; then
            rm_user_path "$_zjs"
        fi
    done
    _lw="$HOME/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg"
    if [[ -f "$_lw" ]] && grep -q 'browser-hardening\.sh' "$_lw" 2>/dev/null; then
        rm_user_path "$_lw"
    fi
    shopt -u nullglob
    unset _pol _zpol _zjs _lw _zen_pol_src
    echo "✓ Browser policies processed"
fi

# ── 5. location (opt-in): remove GeoClue/VPN sync files ──────────────────────
if section_on location; then
    echo "--- Removing location/VPN sync files ---"
    if [[ -L "$HOME/.local/bin/vpn-location-sync" ]]; then
        _vt="$(readlink -m "$HOME/.local/bin/vpn-location-sync" 2>/dev/null || true)"
        if [[ "$_vt" == "$REPO_ROOT/"* || "$_vt" == */dotfiles/*vpn-location-sync.sh ]]; then
            rm_user_path "$HOME/.local/bin/vpn-location-sync"
        fi
        unset _vt
    fi
    for _lf in \
        "$ROOT/usr/local/bin/vpn-location-sync" \
        "$ROOT/usr/local/share/vpn-location-sync/home.geolocation" \
        "$ROOT/etc/geolocation" \
        "$ROOT/etc/geolocation.local" \
        "$ROOT/etc/geoclue/conf.d/99-static-location.conf" \
        "$ROOT/etc/NetworkManager/dispatcher.d/99-vpn-location" \
        "$ROOT/etc/polkit-1/rules.d/50-vpn-location-sync.rules"
    do
        if root_path_exists "$_lf"; then
            rm_root_path "$_lf"
        fi
    done
    unset _lf
    echo "✓ Location sync files processed"
fi

# ── 6. system (opt-in): remove managed /etc files & restore backups ──────────
_restore_latest_backup() {
    local dest="$1" latest=""
    shopt -s nullglob
    local baks=("${dest}.bak."*)
    shopt -u nullglob
    if (( ${#baks[@]} > 0 )); then
        latest="${baks[-1]}"
        if (( DRY_RUN )); then
            printf '[dry-run] %smv %s %s\n' "${SUDO[*]:+${SUDO[*]} }" "$latest" "$dest"
        else
            "${SUDO[@]}" mv -f -- "$latest" "$dest"
        fi
        return 0
    fi
    return 1
}

if section_on system; then
    echo "--- Removing managed /etc system files ---"
    # Disable systemd units BEFORE deleting their unit files (avoids dangling wants links).
    if [[ -z "$ROOT" ]] && command -v systemctl >/dev/null 2>&1; then
        for _svc in virbr0-up.service bootvine.service bootvine-shutdown.service thinkpad-charge-thresholds.service; do
            if systemctl is-enabled "$_svc" >/dev/null 2>&1; then
                act "${SUDO[@]}" systemctl disable "$_svc" || true
            fi
        done
    fi

    # Location-owned files stay in the location section; 50-kali-lan-host-prep.rules
    # is intentionally removed here alongside /usr/local/bin/kali-lan-host-prep below.
    LOCATION_OWNED=(
        etc/geolocation
        etc/geolocation.local
        etc/geoclue/conf.d/99-static-location.conf
        etc/NetworkManager/dispatcher.d/99-vpn-location
        etc/polkit-1/rules.d/50-vpn-location-sync.rules
    )
    if [[ -d "$REPO_ROOT/system/etc" ]]; then
        while IFS= read -r -d '' src; do
            rel="etc/${src#"$REPO_ROOT/system/etc"/}"
            if [[ " ${LOCATION_OWNED[*]} " == *" $rel "* ]]; then
                continue
            fi
            dest="$ROOT/$rel"
            if root_path_exists "$dest"; then
                rm_root_path "$dest"
            fi
        done < <(find "$REPO_ROOT/system/etc" -type f -print0 | sort -z)
    fi

    # zram-generator.conf: restore backup if present, else remove
    _zram="$ROOT/etc/systemd/zram-generator.conf"
    if root_path_exists "$_zram"; then
        _restore_latest_backup "$_zram" || rm_root_path "$_zram"
    fi

    # GDM drop-ins: remove our drop-ins; for custom.conf only restore backup (never leave missing)
    for _gf in \
        "$ROOT/etc/dconf/db/gdm.d/00-login-screen" \
        "$ROOT/etc/dconf/profile/gdm" \
        "$ROOT/etc/systemd/system/gdm.service.d/override.conf" \
        "$ROOT/etc/udev/rules.d/61-gdm-wayland.rules"
    do
        if root_path_exists "$_gf"; then
            rm_root_path "$_gf"
        fi
    done
    _gdm_cfg="$ROOT/etc/gdm/custom.conf"
    if root_path_exists "$_gdm_cfg"; then
        if ! _restore_latest_backup "$_gdm_cfg"; then
            echo "○ keeping $_gdm_cfg (no backup found; edit manually if needed)"
        fi
    fi

    # ThinkPad charge thresholds & kali-lan helper
    for _sf in \
        "$ROOT/etc/tmpfiles.d/thinkpad-charge-thresholds.conf" \
        "$ROOT/etc/systemd/system/thinkpad-charge-thresholds.service" \
        "$ROOT/usr/local/lib/thinkpad/apply-charge-thresholds.sh" \
        "$ROOT/usr/local/bin/kali-lan-host-prep"
    do
        if root_path_exists "$_sf"; then
            rm_root_path "$_sf"
        fi
    done

    if [[ -z "$ROOT" && $DRY_RUN -eq 0 ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl daemon-reload || true
        fi
        if command -v udevadm >/dev/null 2>&1; then
            sudo udevadm control --reload || true
        fi
        if command -v dconf >/dev/null 2>&1; then
            sudo dconf update || true
        fi
    fi
    unset _zram _gf _gdm_cfg _sf _svc
    echo "✓ System files processed"
fi

echo "Uninstall finished."
