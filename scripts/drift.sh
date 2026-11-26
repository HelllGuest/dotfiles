#!/usr/bin/env bash
# drift.sh — read-only package and stow symlink drift checker.
#
# Usage: bash scripts/drift.sh [--strict]
#   Default: reports untracked packages as hints (○) and broken stow symlinks as failures (✗).
#   --strict: also exit 1 when untracked explicit packages/Flatpaks or stale stow inventory exist.
set -euo pipefail

STRICT=0
while (($#)); do
    case $1 in
        --strict) STRICT=1 ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *)
            echo "drift.sh: unknown option '$1' (use --strict|-h)" >&2
            exit 2
            ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../provision/lib/pkg-lists.sh
source "$REPO_ROOT/provision/lib/pkg-lists.sh"

DRIFT_FAILS=0
DRIFT_HINTS=0
drift_fail() { printf '✗ %s\n' "$*"; DRIFT_FAILS=$((DRIFT_FAILS + 1)); }
drift_hint() { printf '○ %s\n' "$*"; DRIFT_HINTS=$((DRIFT_HINTS + 1)); }

echo "--- Package & stow drift ---"

# Build declared native package set across tracked pacman lists + Stage A base packages.
declared_native="$(
    {
        for f in "$REPO_ROOT"/packages/pacman.txt "$REPO_ROOT"/packages/browsers.txt \
                 "$REPO_ROOT"/packages/thinkpad-t14s.txt "$REPO_ROOT"/packages/re-extra.txt; do
            if [[ -f $f ]]; then list_entries "$f"; fi
        done
        if [[ -f $REPO_ROOT/t14s-arch-install/lib/50-packages.sh ]]; then
            (
                yn_on() { [[ ${1:-N} == Y ]]; }
                die() { exit 1; }
                # shellcheck source=/dev/null
                source "$REPO_ROOT/t14s-arch-install/lib/50-packages.sh"
                UCODE=amd-ucode INSTALL_BLUETOOTH=Y INSTALL_LINUX_HARDENED=Y t14s_base_packages
                printf '%s\n' "${BASE_PKGS[@]}" intel-ucode e2fsprogs xfsprogs
            )
        fi
    } | sort -u
)"

if command -v pacman >/dev/null 2>&1; then
    mapfile -t extra_native < <(comm -23 <(pacman -Qqen 2>/dev/null | sort -u) <(printf '%s\n' "$declared_native" | sort -u))
    if [[ ${#extra_native[@]} -eq 0 ]]; then
        echo "✓ no untracked explicit native packages"
    else
        suffix=""
        if (( ${#extra_native[@]} > 12 )); then
            suffix=" (+$(( ${#extra_native[@]} - 12 )) more)"
        fi
        drift_hint "${#extra_native[@]} explicit native package(s) not in packages/*.txt: ${extra_native[*]:0:12}${suffix}"
    fi

    declared_aur="$(
        {
            if [[ -f $REPO_ROOT/packages/aur.txt ]]; then list_entries "$REPO_ROOT/packages/aur.txt"; fi
            printf '%s\n' paru paru-bin paru-debug yay yay-bin yay-debug
        } | sort -u
    )"
    mapfile -t extra_aur < <(comm -23 <(pacman -Qqem 2>/dev/null | sort -u) <(printf '%s\n' "$declared_aur" | sort -u))
    if [[ ${#extra_aur[@]} -eq 0 ]]; then
        echo "✓ no untracked AUR/foreign packages"
    else
        drift_hint "${#extra_aur[@]} foreign package(s) not in packages/aur.txt: ${extra_aur[*]}"
    fi
else
    echo "○ pacman not found — skipped native/AUR package drift"
fi

if command -v flatpak >/dev/null 2>&1; then
    declared_fp="$(
        if [[ -f $REPO_ROOT/packages/flatpak.txt ]]; then list_entries "$REPO_ROOT/packages/flatpak.txt" | sort -u; fi
    )"
    mapfile -t extra_fp < <(comm -23 <(flatpak list --app --columns=application 2>/dev/null | sed '/^$/d' | sort -u) <(printf '%s\n' "$declared_fp" | sort -u))
    if [[ ${#extra_fp[@]} -eq 0 ]]; then
        echo "✓ no untracked Flatpak apps"
    else
        drift_hint "${#extra_fp[@]} Flatpak app(s) not in packages/flatpak.txt: ${extra_fp[*]}"
    fi
else
    echo "○ flatpak not found — skipped Flatpak drift"
fi

# Broken symlinks in $HOME pointing into $REPO_ROOT/stow/
stow_real="$(cd "$REPO_ROOT/stow" 2>/dev/null && pwd -P || printf '%s/stow' "$REPO_ROOT")"
broken_links=()
while IFS= read -r -d '' lnk; do
    [[ -e $lnk ]] && continue
    target="$(readlink -m "$lnk" 2>/dev/null || readlink "$lnk" 2>/dev/null || true)"
    if [[ $target == "$stow_real/"* || $target == "$REPO_ROOT/stow/"* ]]; then
        broken_links+=("$lnk -> $target")
    fi
done < <(find "$HOME" -maxdepth 6 \
    \( -name .git -o -path "$HOME/.cache" -o -path "$HOME/.local/share/Trash" -o -path "$HOME/.npm" \
       -o -path "$HOME/.cargo" -o -path "$HOME/.rustup" -o -path "$HOME/.mozilla" \
       -o -path "$HOME/.zen" -o -path "$HOME/.config/BraveSoftware" \
       -o -path "$HOME/.config/Cursor" -o -path "$HOME/.config/VSCodium" \
       -o -path "$HOME/.config/Antigravity" -o -path "$REPO_ROOT" \) -prune \
    -o -type l -print0 2>/dev/null)

if [[ ${#broken_links[@]} -eq 0 ]]; then
    echo "✓ no broken stow symlinks in $HOME"
else
    for b in "${broken_links[@]}"; do
        drift_fail "broken stow symlink: $b"
    done
fi

# Stow inventory freshness
if [[ -f $REPO_ROOT/all_stow_files.txt && -f $REPO_ROOT/scripts/list-stow-files.sh ]]; then
    if diff -q "$REPO_ROOT/all_stow_files.txt" <(bash "$REPO_ROOT/scripts/list-stow-files.sh") >/dev/null 2>&1; then
        echo "✓ all_stow_files.txt matches stow/"
    else
        drift_hint "all_stow_files.txt is out of date — bash scripts/list-stow-files.sh > all_stow_files.txt"
    fi
fi

if (( DRIFT_FAILS > 0 )) || (( STRICT == 1 && DRIFT_HINTS > 0 )); then
    exit 1
fi
exit 0
