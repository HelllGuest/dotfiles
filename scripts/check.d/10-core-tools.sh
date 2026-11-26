# 10-core-tools.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Required binaries, /etc ownership and dotfiles system/ links, shell tools, login shell.

# 1. Check for required binaries
# kitty is the primary terminal (Super+Return / MIME); ghostty is also required.
REQUIRED_BINARIES=("stow" "zsh" "starship" "nvim" "kitty" "ghostty" "fastfetch" "btop" "htop" "dconf" "jq")
SHELL_BINARIES=("atuin" "fzf" "fd" "rg" "bat" "eza" "zoxide" "direnv" "delta")
for bin in "${REQUIRED_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        check_fail "$bin is missing"
    fi
done

echo "--- System ownership ---"
etc_owner="$(stat -c '%U' /etc 2>/dev/null || echo unknown)"
if [[ "$etc_owner" == "root" ]]; then
    echo "✓ /etc owned by root"
else
    check_fail "/etc owned by $etc_owner (must be root — pacman hooks fail with unsafe path transition)"
    echo "  run: sudo chown root:root /etc && sudo chmod 755 /etc"
fi
# sudo -n when cached: plain find cannot enter 700 dirs (e.g. /etc/sudoers.d).
find_etc=(find)
sudo -n true 2>/dev/null && find_etc=(sudo -n find)
stowed_etc="$("${find_etc[@]}" /etc -type l \( -lname '*/stow/system/*' -o -lname '*/dotfiles/system/*' -o -lname "${REPO_ROOT}/system/*" \) 2>/dev/null)"
if [[ -z "$stowed_etc" ]]; then
    echo "✓ no /etc symlinks into dotfiles system/"
else
    check_fail "/etc symlinks into dotfiles system/ (dangle at early boot; user-writable root config):"
    echo "$stowed_etc" | sed 's/^/  /'
    echo "  run: bash system/scripts/system-setup.sh"
fi

echo "--- Shell productivity tools ---"
for bin in "${SHELL_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        check_fail "$bin is missing"
    fi
done

echo "--- Login shell ---"
_ls="$(getent passwd "$USER" | cut -d: -f7)"
if command -v zsh >/dev/null 2>&1 && [[ "$(readlink -f "$_ls")" == "$(readlink -f "$(command -v zsh)")" ]]; then
    echo "✓ login shell is zsh ($_ls)"
else
    check_fail "login shell is ${_ls:-unknown}, not zsh — sudo usermod -s /usr/bin/zsh $USER (or re-run ./install.sh)"
fi
unset _ls
