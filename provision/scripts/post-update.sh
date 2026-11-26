#!/usr/bin/env bash
# post-update.sh — post-update maintenance (Flatpaks, Neovim, fonts, tldr, ops hygiene).
#
# Usage: bash provision/scripts/post-update.sh [--full]
#   --full  Also run system upgrade (paru/pacman -Syu), agentsync, sync-agent-skills.sh,
#           sbctl verify (when Secure Boot is on and sudo is cached), and check.sh --post.
set -o pipefail

FULL=0
while (($#)); do
    case $1 in
        --full) FULL=1 ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *)
            echo "post-update.sh: unknown option '$1' (use --full|-h)" >&2
            exit 2
            ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0
fail() { echo "warning: $*" >&2; FAILED=1; }

echo "Running post-update maintenance..."

if [[ $FULL -eq 1 ]]; then
    if command -v paru >/dev/null 2>&1; then
        echo "Updating system + AUR via paru..."
        paru -Syu || fail "paru -Syu failed"
    elif command -v pacman >/dev/null 2>&1; then
        echo "Updating system via pacman..."
        sudo pacman -Syu || fail "pacman -Syu failed"
    fi
fi

# Install any new flatpaks from packages/flatpak.txt, then update
if [ -f "$REPO_ROOT/provision/scripts/install-flatpaks.sh" ]; then
    bash "$REPO_ROOT/provision/scripts/install-flatpaks.sh" || fail "install-flatpaks.sh failed"
fi
if command -v flatpak >/dev/null 2>&1; then
    echo "Updating Flatpaks..."
    flatpak update -y || fail "flatpak update failed"
fi

# Update Neovim plugins
if command -v nvim >/dev/null 2>&1; then
    echo "Updating Neovim plugins..."
    nvim --headless "+Lazy! sync" +qa 2>&1 | tail -3 \
        || fail "Lazy sync failed"
    nvim --headless "+lua require('nvim-treesitter').install({'lua','vim','vimdoc'}):wait(120000)" +qa 2>&1 | tail -2 \
        || fail "treesitter install failed"
fi

# Update font cache
echo "Updating font cache..."
fc-cache -fv || fail "fc-cache failed"

# Update tldr if present
if command -v tldr >/dev/null 2>&1; then
    echo "Updating tldr..."
    tldr --update || fail "tldr --update failed"
fi

# Pacman cache + unused Flatpak runtimes (weekly timer stays enabled)
if [ "${SKIP_OPS_HYGIENE:-0}" != 1 ] && [ -f "$REPO_ROOT/security/scripts/ops-hygiene.sh" ]; then
    bash "$REPO_ROOT/security/scripts/ops-hygiene.sh" || fail "ops-hygiene.sh failed"
fi

if [[ $FULL -eq 1 ]]; then
    if command -v agentsync >/dev/null 2>&1; then
        echo "Syncing AI agent rules (agentsync)..."
        agentsync || fail "agentsync failed"
    elif [[ -x "$REPO_ROOT/ai/rules/bin/agentsync" ]]; then
        echo "Syncing AI agent rules..."
        "$REPO_ROOT/ai/rules/bin/agentsync" || fail "agentsync failed"
    fi
    if [[ -f "$REPO_ROOT/ai/scripts/sync-agent-skills.sh" ]]; then
        echo "Syncing agent skills..."
        bash "$REPO_ROOT/ai/scripts/sync-agent-skills.sh" || fail "sync-agent-skills.sh failed"
    fi
    _sb="$(compgen -G '/sys/firmware/efi/efivars/SecureBoot-*' | head -1 || true)"
    if [[ -n $_sb && $(od -An -tu1 -j4 -N1 "$_sb" 2>/dev/null | tr -d ' ') == 1 ]] \
        && command -v sbctl >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        echo "Verifying Secure Boot signatures (sbctl)..."
        sudo -n sbctl verify || fail "sbctl verify reported unsigned EFI files"
    fi
    unset _sb
    if [[ -f "$REPO_ROOT/scripts/check.sh" ]]; then
        echo "Running health check..."
        bash "$REPO_ROOT/scripts/check.sh" --post || fail "check.sh --post reported failures"
    fi
fi

if [ "$FAILED" -ne 0 ]; then
    echo "Maintenance finished with failures (see warnings above)."
    exit 1
fi
echo "Maintenance complete!"
