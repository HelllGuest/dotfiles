# 45-git-nvim.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Git config/identity and Neovim (lazy.nvim).

echo "--- Git ---"
if [ -f "$HOME/.config/git/config" ]; then
    echo "✓ Git XDG config deployed"
else
    check_fail "Git config missing (run scripts/git-setup.sh)"
fi
if command -v delta >/dev/null 2>&1; then
    echo "✓ delta is installed"
else
    check_fail "delta is missing"
fi
if git config --get user.email >/dev/null 2>&1; then
    echo "✓ Git identity: $(git config --get user.name) <$(git config --get user.email)>"
else
    # Not a failure: git-setup.sh deliberately ships no default identity.
    echo "⚠ Git identity not set (git config --global user.name/user.email, or GIT_USER_NAME/GIT_USER_EMAIL with git-setup.sh)"
fi

echo "--- Neovim ---"
if [ -f "$HOME/.config/nvim/init.lua" ]; then
    echo "✓ Neovim config deployed"
else
    check_fail "Neovim config missing (run scripts/nvim-setup.sh)"
fi
if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim" ]; then
    echo "✓ lazy.nvim bootstrapped"
else
    check_fail "lazy.nvim not bootstrapped (run scripts/nvim-setup.sh)"
fi
