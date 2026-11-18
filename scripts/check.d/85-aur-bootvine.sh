# 85-aur-bootvine.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# aur.txt entries now in the official repos; bootvine boot screen.

echo "--- AUR list ---"
# Entries that reached the official repos belong in pacman.txt (they were
# installed in the AUR batch, so one failing AUR build skipped them too).
_moved=0
while IFS= read -r _p; do
    _p=${_p%%#*}; _p=${_p//[[:space:]]/}
    [ -n "$_p" ] || continue
    if pacman -Si "$_p" >/dev/null 2>&1; then
        echo "○ $_p (aur.txt) is in the official repos — move it to packages/pacman.txt"
        _moved=1
    fi
done < "$REPO_ROOT/packages/aur.txt"
[ "$_moved" = 1 ] || echo "✓ no aur.txt entry is in the official repos"
unset _p _moved

echo "--- Boot screen (bootvine) ---"
if pacman -Q bootvine-git >/dev/null 2>&1; then
    echo "○ bootvine-git (AUR) installed — replace with official: sudo pacman -Rns bootvine-git && sudo pacman -S bootvine"
fi
if pacman -Q bootvine >/dev/null 2>&1; then
    for _u in bootvine.service bootvine-shutdown.service; do
        if systemctl is-enabled --quiet "$_u" 2>/dev/null; then
            echo "✓ $_u enabled"
        else
            echo "○ $_u not enabled — sudo systemctl enable $_u"
        fi
    done
    unset _u
else
    echo "○ bootvine not installed — sudo pacman -S bootvine (packages/pacman.txt)"
fi
if grep -Eq '^HOOKS=.*sd-bootvine' /etc/mkinitcpio.conf 2>/dev/null; then
    echo "○ sd-bootvine in mkinitcpio HOOKS — the repo keeps bootvine out of the initrd (LUKS prompt)"
fi
