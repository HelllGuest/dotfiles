#!/bin/bash
# check.sh — read-only health check (+ optional safe auto-fix and drift audit).
#
#   bash scripts/check.sh [--post]   post-install: Stage A follow-ups (Secure Boot,
#                                    first-boot Flatpaks, t14s-selftest) + dotfiles
#                                    (Stage B). Default; ./install.sh runs this.
#   bash scripts/check.sh --stage-a  Arch ISO install (Stage A): runs
#                                    t14s-arch-install tests/host-check.sh
#                                    (also as root when sudo is cached)
#   bash scripts/check.sh --all      both Stage A and Stage B
#   bash scripts/check.sh --drift    package & stow symlink drift (scripts/drift.sh)
#   bash scripts/check.sh --fix      run safe idempotent fixes, then re-run --post
#
#   T14S_INSTALLER_DIR  t14s-arch-install dir (default: in-repo t14s-arch-install/)
#
# Exit 1 when any ✗ fails; ○ is a hint only.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DRIFT_ARGS=()
case ${1:-} in
    '' | --post)
        [[ $# -le 1 ]] || { sed -n '2,16p' "$0" >&2; exit 2; }
        MODE=post
        ;;
    --stage-a)
        [[ $# -eq 1 ]] || { sed -n '2,16p' "$0" >&2; exit 2; }
        MODE=stage-a
        ;;
    --all)
        [[ $# -eq 1 ]] || { sed -n '2,16p' "$0" >&2; exit 2; }
        MODE=all
        ;;
    --drift)
        MODE=drift
        shift
        DRIFT_ARGS=("$@")
        ;;
    --fix)
        [[ $# -eq 1 ]] || { sed -n '2,16p' "$0" >&2; exit 2; }
        MODE=fix
        ;;
    -h | --help) sed -n '2,16p' "$0"; exit 0 ;;
    *) sed -n '2,16p' "$0" >&2; exit 2 ;;
esac

# ✗ probes set CHECK_FAILED; install.sh treats non-zero as fail_step.
CHECK_FAILED=0
check_fail() { printf '✗ %s\n' "$*"; CHECK_FAILED=$((CHECK_FAILED + 1)); }
finish() {
    echo "Health check finished."
    if [[ "$CHECK_FAILED" -ne 0 ]]; then
        echo "Health check failed ($CHECK_FAILED)."
        exit 1
    fi
    exit 0
}

# shellcheck source=../provision/lib/dmi.sh
source "$REPO_ROOT/provision/lib/dmi.sh"

# Written unconditionally by t14s-arch-install (lib/chroot/01-base-config.sh).
is_stage_a_host() { [[ -f /etc/makepkg.conf.d/t14s.conf ]]; }

# Stage A is verified by the installer's own read-only checker, so the
# expectations (cmdline, LUKS2/argon2id, Btrfs subvolumes, UKIs, AppArmor,
# firewalld drop, sysctl, charge/touchpad/lid, GDM, makepkg, services) live
# in one place and follow installer changes.
find_host_check() {
    local d
    for d in "${T14S_INSTALLER_DIR:-}" "$REPO_ROOT/t14s-arch-install" "$HOME/t14s-arch-install" "$REPO_ROOT/../t14s-arch-install"; do
        [[ -n $d && -f $d/tests/host-check.sh ]] && { printf '%s\n' "$d/tests/host-check.sh"; return 0; }
    done
    return 1
}
stage_a_check() {
    echo "--- Stage A (Arch ISO install) ---"
    local hc rc rc_root=0 strict=1
    if ! hc="$(find_host_check)"; then
        check_fail "t14s-arch-install not found — expected $REPO_ROOT/t14s-arch-install (or set T14S_INSTALLER_DIR)"
        return
    fi
    is_stage_a_host || echo "○ /etc/makepkg.conf.d/t14s.conf missing: this host was probably not installed by t14s-arch-install"
    # host-check.sh targets the T14s Gen 3 AMD (amd-pstate, ELAN/SYNA touchpad,
    # 21CQ/21CR); elsewhere its result is shown but not counted.
    if ! is_thinkpad_t14s; then
        strict=0
        echo "○ not a T14s Gen 3 AMD ($(dmi_label | tr -s ' ')): host-check results below are informational"
    fi
    echo "  using $hc ($(git -C "$(dirname "$hc")" log -1 --format='%h %cs' 2>/dev/null || echo 'not a git checkout'))"
    bash "$hc"; rc=$?
    # Root-only checks (ESP/UKIs, sbctl, LUKS PBKDF, snapper) need sudo; never prompt.
    if [[ $EUID -ne 0 ]] && sudo -n true 2>/dev/null; then
        echo "  root pass (ESP, UKIs, sbctl, LUKS PBKDF, snapper):"
        sudo -n bash "$hc"; rc_root=$?
    elif [[ $EUID -ne 0 ]]; then
        echo "○ root-only Stage A checks skipped — sudo -v && bash scripts/check.sh --stage-a"
    fi
    if (( rc == 0 && rc_root == 0 )); then
        echo "✓ Stage A host-check passed"
    elif (( strict )); then
        check_fail "Stage A host-check reported FAIL lines (see above)"
    else
        echo "○ Stage A host-check reported FAIL lines (informational on this hardware)"
    fi
}

# What the installer leaves for after first boot (its README "After first boot").
stage_a_followups() {
    echo "--- After first boot (Stage A follow-ups) ---"
    if ! is_stage_a_host; then
        echo "○ not installed by t14s-arch-install — skipped"
        return
    fi
    local sb
    sb=$(compgen -G '/sys/firmware/efi/efivars/SecureBoot-*' | head -1)
    if [[ -n $sb && $(od -An -tu1 -j4 -N1 "$sb" 2>/dev/null | tr -d ' ') == 1 ]]; then
        echo "✓ Secure Boot enabled"
        if command -v sbctl >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            local unsigned
            unsigned=$(sudo -n sbctl verify 2>/dev/null | grep -c 'is not signed' || true)
            if [[ $unsigned -eq 0 ]]; then
                echo "✓ sbctl: every tracked EFI file signed"
            else
                check_fail "sbctl: $unsigned EFI file(s) not signed with Secure Boot on (next boot may fail) — sudo sbctl sign-all"
            fi
        fi
    elif [[ -d /sys/firmware/efi ]]; then
        echo "○ Secure Boot off — BIOS Setup Mode, then sudo sbctl verify && sudo sbctl enroll-keys -m, then enable SB"
    else
        echo "○ not booted in UEFI mode"
    fi
    if [[ -e /var/lib/t14s/flatpak-apps.done ]]; then
        echo "✓ first-boot Flatpak apps installed"
    elif systemctl is-failed --quiet t14s-flatpak-apps.service 2>/dev/null; then
        check_fail "first-boot Flatpak install failed — journalctl -u t14s-flatpak-apps; bash provision/scripts/install-flatpaks.sh"
    elif systemctl is-enabled --quiet t14s-flatpak-apps.timer 2>/dev/null; then
        echo "○ first-boot Flatpak apps still pending (needs network) — journalctl -u t14s-flatpak-apps -f"
    fi
    # host-check.sh (--all) already runs t14s-selftest.
    local selftest_bin="${T14S_SELFTEST_BIN:-/usr/local/bin/t14s-selftest}"
    if [[ -x $selftest_bin && $MODE != all ]]; then
        local out
        if out="$("$selftest_bin" 2>&1)"; then
            echo "✓ ${out##*$'\n'}"
        else
            check_fail "t14s-selftest: $(grep '^FAIL' <<<"$out" | tr '\n' ' ')"
        fi
    fi
}

run_safe_fixes() {
    echo "--- Safe auto-fix ---"
    local _need_stow=0 _lnk
    for _lnk in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.inputrc" "$HOME/.shell-exports" \
        "$HOME/.shell-aliases" "$HOME/.shell-git" "$HOME/.config/starship.toml" \
        "$HOME/.config/atuin/config.toml" "$HOME/.config/nvim/init.lua" "$HOME/.config/fastfetch/config.jsonc"; do
        if [[ ! -L "$_lnk" && ! -e "$_lnk" ]]; then
            _need_stow=1
            break
        fi
    done
    if (( _need_stow )) && [[ -f "$REPO_ROOT/stow-only.sh" ]] && command -v stow >/dev/null 2>&1; then
        echo "→ Running stow-only.sh..."
        bash "$REPO_ROOT/stow-only.sh" || echo "○ stow-only.sh reported warnings"
    fi
    if [[ -x "$REPO_ROOT/ai/rules/bin/agentsync" ]]; then
        echo "→ Running ai/rules/bin/agentsync..."
        "$REPO_ROOT/ai/rules/bin/agentsync" "$REPO_ROOT" || echo "○ agentsync reported warnings"
    elif command -v agentsync >/dev/null 2>&1; then
        echo "→ Running agentsync..."
        agentsync "$REPO_ROOT" || echo "○ agentsync reported warnings"
    fi
    if [[ -f "$REPO_ROOT/security/scripts/browser-hardening.sh" ]]; then
        if [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null; then
            echo "→ Running browser-hardening.sh..."
            bash "$REPO_ROOT/security/scripts/browser-hardening.sh" || echo "○ browser-hardening.sh reported warnings"
        else
            echo "→ Running browser-hardening.sh (user layer only; no cached sudo)..."
            bash "$REPO_ROOT/security/scripts/browser-hardening.sh" </dev/null || echo "○ /etc browser policies need sudo — sudo -v && bash security/scripts/browser-hardening.sh"
        fi
    fi
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" && -f "$REPO_ROOT/desktop/scripts/gnome-session-setup.sh" ]] \
        && command -v gsettings >/dev/null 2>&1; then
        echo "→ Running gnome-session-setup.sh..."
        bash "$REPO_ROOT/desktop/scripts/gnome-session-setup.sh" || echo "○ gnome-session-setup.sh reported warnings"
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tailscaled 2>/dev/null \
        && sudo -n true 2>/dev/null && [[ -f "$REPO_ROOT/security/scripts/firewalld-tailscale.sh" ]]; then
        echo "→ Running firewalld-tailscale.sh..."
        bash "$REPO_ROOT/security/scripts/firewalld-tailscale.sh" || echo "○ firewalld-tailscale.sh reported warnings"
    fi
}

if [[ $MODE == drift ]]; then
    exec bash "$REPO_ROOT/scripts/drift.sh" "${DRIFT_ARGS[@]}"
fi
if [[ $MODE == stage-a ]]; then
    stage_a_check
    finish
fi
[[ $MODE == fix ]] && run_safe_fixes
[[ $MODE == all ]] && stage_a_check

echo "Running health check..."
stage_a_followups

# Area checks: scripts/check.d/NN-area.sh, sourced here at top level in name
# order (they share check_fail, CHECK_FAILED, MODE and REPO_ROOT). A new check
# is a new file there; its number decides where it prints.
for _check in "$REPO_ROOT"/scripts/check.d/[0-9]*.sh; do
    # shellcheck source=/dev/null
    source "$_check"
done
unset _check

finish
