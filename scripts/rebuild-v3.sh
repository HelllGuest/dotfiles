#!/usr/bin/env bash
# rebuild-v3.sh — rebuild selected extra/ packages with /etc/makepkg.conf.d v3 flags
# Default: zstd xz lz4. Skips PKGBUILD check() (zstd fuzzer is long). Pass names for more (ffmpeg is large).
set -euo pipefail

if [[ $# -eq 0 ]]; then
    PACKAGES=(zstd xz lz4)
else
    PACKAGES=("$@")
fi

if [[ ${EUID} -eq 0 ]]; then
    echo "run as your user (makepkg refuses root)" >&2
    exit 1
fi

for pkg in "${PACKAGES[@]}"; do
    if [[ ! ${pkg} =~ ^[a-zA-Z0-9+._-]+$ ]]; then
        echo "invalid package name: ${pkg}" >&2
        exit 1
    fi
done

# shellcheck disable=1091
source /etc/makepkg.conf
for f in /etc/makepkg.conf.d/*.conf; do
    # shellcheck disable=1090
    [[ -f $f ]] && source "$f"
done
_user_mk="${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf"
# shellcheck disable=1090
[[ -f ${_user_mk} ]] && source "${_user_mk}"
# shellcheck disable=1090
[[ -f ${HOME}/.makepkg.conf ]] && source "${HOME}/.makepkg.conf"
unset _user_mk

case " ${CFLAGS-} " in
    *" -march=x86-64-v3 "*) ;;
    *)
        echo "CFLAGS lacks -march=x86-64-v3 (got: ${CFLAGS-unset})" >&2
        echo "install stow/system/etc/makepkg.conf.d/99-x86-64-v3.conf first" >&2
        exit 1
        ;;
esac

echo "CFLAGS=${CFLAGS}"
echo "packages: ${PACKAGES[*]}"

command -v git >/dev/null || { echo "git required" >&2; exit 1; }
command -v makepkg >/dev/null || { echo "base-devel/makepkg required" >&2; exit 1; }
if ! pacman -Qq base-devel >/dev/null 2>&1 || ! command -v git >/dev/null; then
    sudo -n pacman -S --needed --noconfirm base-devel git
fi

pkgdest="${XDG_CACHE_HOME:-$HOME/.cache}/rebuild-v3"
mkdir -p "${pkgdest}"
export PKGDEST="${pkgdest}"

work="$(mktemp -d /tmp/rebuild-v3.XXXXXX)"
trap 'rm -rf "$work"' EXIT

if [[ -z ${MAKEFLAGS:-} ]]; then
    export MAKEFLAGS="-j$(nproc)"
fi

# Isolated, passphrase-less key so local packages can be pacman-verified.
# Does not use the user's default GnuPG keyring.
export GNUPGHOME="${XDG_DATA_HOME:-$HOME/.local/share}/rebuild-v3/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
if ! gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "rebuild-v3 <rebuild-v3@localhost>" ed25519 sign never
fi
GPGKEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')"
if [[ -z ${GPGKEY} ]]; then
    echo "failed to create or read rebuild-v3 signing key" >&2
    exit 1
fi
export GPGKEY

# English gettext strings from makepkg/gpg (skippgpcheck matching).
export LC_ALL=C
export LANG=C

all_built=()

for pkg in "${PACKAGES[@]}"; do
    echo "==> cloning ${pkg}"
    git clone --depth 1 "https://gitlab.archlinux.org/archlinux/packaging/packages/${pkg}.git" "${work}/${pkg}"
    # shellcheck disable=SC2164
    cd "${work}/${pkg}"
    rm -f "${pkgdest}/${pkg}"-*.pkg.tar.*
    echo "==> makepkg ${pkg}"
    if [[ -f PKGBUILD ]]; then
        mapfile -t pgpkeys < <(bash -c 'set +u; source ./PKGBUILD; printf "%s\n" "${validpgpkeys[@]}"' 2>/dev/null || true)
        pgpkeys=("${pgpkeys[@]// /}")
        if [[ ${#pgpkeys[@]} -gt 0 && -n ${pgpkeys[0]:-} ]]; then
            gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "${pgpkeys[@]}" || true
        fi
    fi
    # --nocheck: upstream tests (zstd fuzzer/fullbench) are long; we only change -march.
    mkpkg=(makepkg -s --noconfirm --cleanbuild --nocheck --sign)
    mklog="${work}/${pkg}.makepkg.log"
    if ! "${mkpkg[@]}" >"${mklog}" 2>&1; then
        cat "${mklog}" >&2
        # Only missing/unknown *upstream* keys. Do not match the generic
        # "PGP signatures could not be verified" line (also used for bad/revoked).
        if grep -Eq 'unknown public key|FAILED \(unknown public key|NO_PUBKEY|No public key' "${mklog}"; then
            echo "makepkg failed on missing/unknown upstream PGP key; retrying with --skippgpcheck (checksums still apply; package still signed with rebuild-v3 key)" >&2
            "${mkpkg[@]}" --skippgpcheck
        else
            echo "makepkg failed (not a missing-key skip)" >&2
            exit 1
        fi
    fi
    mapfile -t built < <(/usr/bin/find "${pkgdest}" -maxdepth 1 -name "${pkg}-*.pkg.tar.*" ! -name '*-debug-*' ! -name '*.sig')
    if [[ ${#built[@]} -eq 0 ]]; then
        echo "no package file for ${pkg}" >&2
        exit 1
    fi
    all_built+=("${built[@]}")
    cd /
done

pub="${XDG_DATA_HOME:-$HOME/.local/share}/rebuild-v3/rebuild-v3.asc"
gpg --export --armor "${GPGKEY}" >"${pub}"
if sudo -n pacman-key --add "${pub}" && sudo -n pacman-key --lsign-key "${GPGKEY}"; then
    :
else
    echo "import the rebuild-v3 key into pacman (once):" >&2
    echo "  sudo pacman-key --add ${pub} && sudo pacman-key --lsign-key ${GPGKEY}" >&2
fi

echo "==> install ${all_built[*]}"
if sudo -n pacman -U --noconfirm "${all_built[@]}"; then
    echo "✓ rebuilt ${PACKAGES[*]} with -march=x86-64-v3 (signed by local rebuild-v3 key ${GPGKEY: -16})"
    echo "note: pacman -Syu still replaces these with extra/; re-run this script after that."
else
    echo "packages built. install with:" >&2
    printf '  sudo pacman -U --noconfirm %q\n' "${all_built[@]}" >&2
    echo "✓ rebuilt (not installed) ${PACKAGES[*]} with -march=x86-64-v3"
    exit 1
fi
