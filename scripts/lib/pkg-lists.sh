# shellcheck shell=bash
# pkg-lists.sh: read packages/*.txt the same way in install.sh and check.sh.
# Source it; needs REPO_ROOT. Comments ("# …", also inline) and blanks dropped.

# list_entries FILE: one entry per line.
list_entries() {
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# pacman_targets: packages/pacman.txt minus entries this host must not get.
pacman_targets() {
    local list
    list="$(list_entries "$REPO_ROOT/packages/pacman.txt")"
    # tuned-ppd provides+conflicts power-profiles-daemon; --noconfirm would
    # refuse the removal and abort the whole transaction.
    if pacman -Q tuned-ppd >/dev/null 2>&1; then
        list="$(grep -vx 'power-profiles-daemon' <<<"$list" || true)"
    fi
    # Stage A installs rustup (provides cargo/rustc), which conflicts with rust.
    if pacman -Q rustup >/dev/null 2>&1; then
        list="$(grep -vx 'rust' <<<"$list" || true)"
    fi
    # shellcheck source=scripts/lib/dmi.sh
    source "$REPO_ROOT/scripts/lib/dmi.sh"
    if is_thinkpad_t14s; then
        # AMD T14s: no Intel iGPU.
        list="$(grep -vxE 'intel-media-driver|vulkan-intel' <<<"$list" || true)"
    fi
    if ! has_nvidia_gpu; then
        # No NVIDIA card: skip the Optimus stack + DKMS builds.
        list="$(grep -vxE 'nvidia-open-dkms|nvidia-prime|nvidia-utils|egl-wayland' <<<"$list" || true)"
    fi
    # Nothing left: print nothing (not one empty line, which would become a target).
    if [ -n "$list" ]; then
        printf '%s\n' "$list"
    fi
}

# missing_pkgs: read names on stdin, print those pacman does not have installed.
missing_pkgs() {
    local p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        pacman -Q "$p" >/dev/null 2>&1 || echo "$p"
    done
}
