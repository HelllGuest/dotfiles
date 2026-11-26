# shellcheck shell=bash
# pkg-lists.sh: read packages/*.txt the same way in install.sh and check.sh.
# Source it; needs REPO_ROOT. Comments ("# …", also inline) and blanks dropped.

# list_entries FILE: one entry per line.
list_entries() {
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# pacman_targets: packages/pacman.txt minus entries this host must not get.
# Opt-out env flags: MINIMAL_PACKAGES=1 (skips heavy toolchains/IDEs),
# SKIP_RE_TOOLS=1 (skips ghidra, JDKs, openssl-3).
pacman_targets() {
    local list skip_re="${SKIP_RE_TOOLS:-0}"
    [[ ${MINIMAL_PACKAGES:-0} == 1 ]] && skip_re=1
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
    if [[ $skip_re == 1 ]]; then
        list="$(grep -vxE 'ghidra|jdk-openjdk|jdk17-openjdk|openssl-3' <<<"$list" || true)"
    fi
    # shellcheck source=dmi.sh
    source "$REPO_ROOT/provision/lib/dmi.sh"
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

# aur_targets: packages/aur.txt minus opt-out heavy bundles.
# Opt-out env flags: MINIMAL_PACKAGES=1, SKIP_AI_IDES=1, SKIP_MOBILE_DEV=1.
aur_targets() {
    local list skip_ides="${SKIP_AI_IDES:-0}" skip_mobile="${SKIP_MOBILE_DEV:-0}"
    if [[ ${MINIMAL_PACKAGES:-0} == 1 ]]; then
        skip_ides=1
        skip_mobile=1
    fi
    list="$(list_entries "$REPO_ROOT/packages/aur.txt")"
    if [[ $skip_ides == 1 ]]; then
        list="$(grep -vxE 'vscodium-bin|cursor-bin|antigravity-ide' <<<"$list" || true)"
    fi
    if [[ $skip_mobile == 1 ]]; then
        list="$(grep -vx 'flutter-bin' <<<"$list" || true)"
    fi
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
