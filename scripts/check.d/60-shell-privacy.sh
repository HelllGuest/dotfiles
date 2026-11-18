# 60-shell-privacy.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Tracked shell rc files and bash/zsh/atuin history privacy.

echo "--- Shell rc (tracked) ---"
# Third-party installers (Antigravity, …) append to ~/.zshrc / ~/.bashrc, which
# are stow symlinks into this repo; such lines belong in ~/.zshrc.local / ~/.bashrc.local.
for _rc in "$REPO_ROOT/stow/zsh/.zshrc" "$REPO_ROOT/stow/bash/.bashrc"; do
    if _hits="$(grep -n -iE '^# (Added|Generated) by .*install' "$_rc" 2>/dev/null)"; then
        echo "○ installer lines in ${_rc#"$REPO_ROOT"/} (move to ~/.$(basename "$_rc" | tr -d .).local): ${_hits%%$'\n'*}"
    else
        echo "✓ no installer-appended lines in ${_rc#"$REPO_ROOT"/}"
    fi
done
unset _rc _hits

echo "--- Shell (bash/zsh) privacy ---"
if grep -q '90-telemetry-optout.conf' "${HOME}/.shell-exports" 2>/dev/null \
  || grep -q '90-telemetry-optout.conf' "$REPO_ROOT/stow/zsh/.shell-exports" 2>/dev/null; then
    echo "✓ shell-exports sources telemetry-optout.conf"
else
    check_fail "shell-exports missing telemetry-optout source"
fi
if grep -q 'umask 077' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q 'umask 077' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash umask 077"
else
    check_fail "bash umask 077 missing"
fi
if grep -q '\*--password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*--password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash HISTIGNORE secret filters (--flag / KEY=)"
else
    check_fail "bash HISTIGNORE secret filters missing"
fi
if grep -q '\*password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    check_fail "bash HISTIGNORE still has over-broad *password* (use *--password*)"
fi
if grep -q 'HISTORY_IGNORE' "${HOME}/.zsh-plugins" 2>/dev/null \
  || grep -q 'HISTORY_IGNORE' "$REPO_ROOT/stow/zsh/.zsh-plugins" 2>/dev/null; then
    echo "✓ zsh HISTORY_IGNORE secret filters"
else
    check_fail "zsh HISTORY_IGNORE missing"
fi
atuin_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml"
if [[ -f "$atuin_cfg" ]] \
  && grep -qE '^auto_sync\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^update_check\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^secrets_filter\s*=\s*true' "$atuin_cfg" \
  && grep -q '(?i)--token' "$atuin_cfg"; then
    echo "✓ atuin privacy keys + secret history_filter"
else
    check_fail "atuin privacy keys/filters missing (stow atuin / bash scripts/privacy-hardener.sh)"
fi
# Bare "(?i)password" as whole pattern (not --password / password=)
if grep -qE '"\(\?i\)password"' "$atuin_cfg" 2>/dev/null \
  || grep -qE '"\(\?i\)password"' "$REPO_ROOT/stow/atuin/.config/atuin/config.toml" 2>/dev/null; then
    check_fail "atuin history_filter still has bare (?i)password (over-broad)"
fi
if grep -q 'LESSHISTFILE=-' "${HOME}/.shell-exports" 2>/dev/null \
  || grep -q 'LESSHISTFILE=-' "$REPO_ROOT/stow/zsh/.shell-exports" 2>/dev/null; then
    echo "✓ LESSHISTFILE=- (no less history file)"
else
    echo "○ LESSHISTFILE not disabled"
fi
