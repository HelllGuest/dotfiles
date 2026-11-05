#!/usr/bin/env bash
# install-re-extras.sh — optional host RE/triage packages from packages/re-extra.txt
#
# Not part of the default pacman.txt set (keeps install lighter). Safe to re-run.
# Does not install AUR packages (imhex-bin, android-apktool-bin): use paru after.
#
# Env:
#   RE_EXTRA_FILE   override manifest path
#
# Usage:
#   bash scripts/install-re-extras.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RE_EXTRA_FILE="${RE_EXTRA_FILE:-$REPO_ROOT/packages/re-extra.txt}"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }

[[ -f "$RE_EXTRA_FILE" ]] || die "missing manifest: $RE_EXTRA_FILE"
command -v pacman >/dev/null 2>&1 || die "pacman required"

mapfile -t PKGS < <(
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$RE_EXTRA_FILE" \
    | awk 'NF'
)
[[ ${#PKGS[@]} -gt 0 ]] || die "no packages in $RE_EXTRA_FILE"

say "pacman -S --needed: ${PKGS[*]}"
if [[ -n "${SUDO_ASKPASS:-}" ]]; then
  sudo -A pacman -S --needed --noconfirm "${PKGS[@]}"
else
  sudo pacman -S --needed --noconfirm "${PKGS[@]}"
fi

say "optional AUR (paru): imhex-bin android-apktool-bin"

# unblob: preferred recursive firmware extractor (OrbitCurve skills expect it)
if command -v unblob >/dev/null 2>&1; then
  say "unblob already on PATH"
elif command -v pipx >/dev/null 2>&1; then
  say "pipx install unblob"
  pipx install unblob || say "warning: unblob pipx install failed (optional)"
else
  say "skip unblob (install pipx, then: pipx install unblob)"
fi

# clamav signatures (package may already be present from triage list)
if pacman -Q clamav >/dev/null 2>&1; then
  say "enable clamav-freshclam"
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A systemctl enable --now clamav-freshclam.service 2>/dev/null \
      || say "warning: clamav-freshclam enable failed"
  else
    sudo systemctl enable --now clamav-freshclam.service 2>/dev/null \
      || say "warning: clamav-freshclam enable failed"
  fi
fi

# ThinkPad charge window 70–80 (only batteries that exist)
bash "${REPO_ROOT}/scripts/thinkpad-charge-thresholds.sh" \
  || say "warning: charge thresholds skipped (sudo/sysfs?)"

say "install-re-extras done"
