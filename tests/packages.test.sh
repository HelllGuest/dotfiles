#!/usr/bin/env bash
# Package lists: no AUR entry that lives in the official repos; opt-in services
# that nothing enables are reported by check.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$ROOT/packages/$1"; }

# Moved to extra (gone from the AUR): must be repo installs, not AUR builds.
for p in curlie gnome-shell-extension-vitals; do
  list pacman.txt | grep -qx "$p" || fail "pacman.txt must include $p (official extra)"
  ! list aur.txt | grep -qx "$p" || fail "aur.txt must not list $p (official extra)"
done
dup="$(comm -12 <(list pacman.txt | sort -u) <(list aur.txt | sort -u))"
[[ -z $dup ]] || fail "packages in both pacman.txt and aur.txt: $dup"

# check.sh flags aur.txt entries that reached the official repos (stub pacman).
block="$(awk '/^echo "--- AUR list ---"$/{f=1} f&&/^echo "--- Boot screen/{exit} f' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh)"
[[ -n $block ]] || fail "could not find check.sh AUR list section"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/packages"
printf '#!/bin/sh\n[ "$1" = -Si ] && [ "$2" = curlie ]\n' >"$T/bin/pacman"
chmod +x "$T/bin/pacman"
printf '%s\n' '# comment' 'curlie  # moved to extra' 'forgit' '' >"$T/packages/aur.txt"
out="$(PATH="$T/bin:$PATH" REPO_ROOT="$T" bash -c "$block")"
grep -qx '○ curlie (aur.txt) is in the official repos — move it to packages/pacman.txt' <<<"$out" \
  || fail "check.sh must flag an official package in aur.txt: $out"
! grep -q forgit <<<"$out" || fail "check.sh must not flag AUR-only packages: $out"
! grep -q '✓ no aur.txt entry' <<<"$out" || fail "check.sh must not report all-clear when an entry moved: $out"
printf '%s\n' 'forgit' >"$T/packages/aur.txt"
out="$(PATH="$T/bin:$PATH" REPO_ROOT="$T" bash -c "$block")"
grep -qx '✓ no aur.txt entry is in the official repos' <<<"$out" && ! grep -q '^○' <<<"$out" \
  || fail "check.sh must print an all-clear line: $out"

# Tailscale: nothing enables tailscaled (network service, opt-in) — check.sh
# must say so and give the order: daemon, tailscale up, then firewall binding.
grep -q 'tailscaled not enabled — sudo systemctl enable --now tailscaled && sudo tailscale up, then bash scripts/firewalld-tailscale.sh' \
  "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh || fail "check.sh must report tailscaled not enabled with the setup order"

echo "PASS: packages.test.sh"
