#!/usr/bin/env bash
# ops-hygiene.sh — pacman cache trim + flatpak unused prune + weekly paccache.timer
#
# Usage:
#   bash security/scripts/ops-hygiene.sh
#   SKIP_PACCACHE=1 SKIP_FLATPAK_PRUNE=1 bash security/scripts/ops-hygiene.sh   # timer only
#   SKIP_TIMER=1 bash security/scripts/ops-hygiene.sh
#
# Keep last N package versions (default 2): PACCACHE_KEEP=3 bash security/scripts/ops-hygiene.sh

set -euo pipefail

KEEP="${PACCACHE_KEEP:-2}"

say() { printf '→ %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

if [[ "${SKIP_PACCACHE:-0}" != 1 ]]; then
  if command -v paccache >/dev/null 2>&1; then
    say "paccache: keep last ${KEEP} version(s)"
    sudo paccache -rk"$KEEP" || warn "paccache failed"
  else
    warn "paccache missing — install pacman-contrib"
  fi
fi

if [[ "${SKIP_FLATPAK_PRUNE:-0}" != 1 ]]; then
  if command -v flatpak >/dev/null 2>&1; then
    say "flatpak uninstall --unused"
    # system + user; ignore "nothing to do"
    flatpak uninstall --unused -y --noninteractive 2>/dev/null \
      || flatpak uninstall --unused -y 2>/dev/null \
      || true
    if flatpak --system list &>/dev/null; then
      sudo flatpak uninstall --system --unused -y --noninteractive 2>/dev/null \
        || sudo flatpak uninstall --system --unused -y 2>/dev/null \
        || true
    fi
  else
    say "flatpak not installed — skip unused prune"
  fi
fi

if [[ "${SKIP_TIMER:-0}" != 1 ]]; then
  if systemctl list-unit-files paccache.timer &>/dev/null; then
    say "enable paccache.timer (weekly)"
    sudo systemctl enable --now paccache.timer \
      || warn "could not enable paccache.timer"
  else
    warn "paccache.timer missing — install pacman-contrib"
  fi
fi

echo "✓ ops hygiene done"
