# 30-dotfile-links.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Key dotfile symlinks and a dry-run stow of every package.

# 2. Check for symlinks
check_link() {
    local path=$1
    if [ -L "$path" ]; then
        echo "✓ Symlink exists: $path"
    elif [ -L "$(dirname "$path")" ] && [ -f "$path" ]; then
        echo "✓ Stowed via $(dirname "$path") -> $(readlink "$(dirname "$path")")"
    else
        check_fail "Symlink missing: $path"
    fi
}

CHECK_LINKS=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.inputrc" "$HOME/.shell-exports" "$HOME/.shell-aliases" "$HOME/.shell-git" "$HOME/.config/starship.toml" "$HOME/.config/atuin/config.toml" "$HOME/.config/nvim/init.lua" "$HOME/.config/fastfetch/config.jsonc")
for link in "${CHECK_LINKS[@]}"; do
    check_link "$link"
done
# Every package must stow cleanly: a regular file in the way (an app's
# first-run config like htoprc, an installer seed like ~/.zshrc) makes stow
# skip the whole package, which the fixed list above cannot see.
if command -v stow >/dev/null 2>&1; then
    _blocked=""
    for _d in "$REPO_ROOT"/stow/*/; do
        _d=$(basename "$_d")
        stow -d "$REPO_ROOT/stow" -n -R -t "$HOME" "$_d" >/dev/null 2>&1 || _blocked+="$_d "
    done
    if [[ -z $_blocked ]]; then
        echo "✓ every stow package links cleanly"
    else
        check_fail "stow packages blocked by existing files: $_blocked— cd stow && stow -n -R -t ~ <pkg> shows the file; move it aside, then stow -R -t ~ <pkg>"
    fi
    unset _blocked _d
fi
