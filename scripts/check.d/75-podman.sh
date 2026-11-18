# 75-podman.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Rootless Podman storage.

echo "--- Podman (rootless) ---"
if command -v podman >/dev/null 2>&1; then
    # Image storage alone can auto-detect fuse-overlayfs; podman build's context
    # overlay only uses it via mount_program (stow containers → storage.conf).
    if _podman_err="$(podman info --format '{{.Store.GraphOptions}}' 2>&1 >/dev/null)"; then
        if podman info --format '{{.Store.GraphOptions}}' 2>/dev/null | grep -q 'mount_program'; then
            echo "✓ podman storage usable (overlay via fuse-overlayfs)"
        else
            check_fail "podman mount_program unset: podman build fails on linux-hardened (stow -R containers)"
        fi
    else
        check_fail "podman storage unusable: ${_podman_err%%$'\n'*}"
        echo "  linux-hardened has no unprivileged overlayfs: sudo pacman -S fuse-overlayfs, then stow -R containers"
    fi
    unset _podman_err
else
    echo "○ podman not installed"
fi
