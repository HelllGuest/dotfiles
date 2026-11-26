#!/usr/bin/env bash
# usbguard-setup.sh — allow currently plugged USB devices, then enable usbguard
#
# Generates /etc/usbguard/rules.conf from the live device set when empty/missing,
# so the keyboard/mouse you are using now stay allowed. Re-plug new devices
# later need: sudo usbguard list-devices && sudo usbguard allow-device <id> -p
#
# Usage:
#   bash security/scripts/usbguard-setup.sh
#   FORCE_REGEN=1 bash security/scripts/usbguard-setup.sh   # rewrite rules from present devices
#   SKIP_ENABLE=1 bash security/scripts/usbguard-setup.sh   # policy only

set -euo pipefail

RULES=/etc/usbguard/rules.conf

say() { printf '→ %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

if ! command -v usbguard >/dev/null 2>&1; then
  die "usbguard not installed — pacman -S usbguard (or ./install.sh)"
fi

# rules.conf is root:root 0600 — unprivileged [[ -f ]] lies; probe with sudo.
_rules_present=0
if sudo test -s "$RULES" 2>/dev/null; then
  _rules_present=1
fi

if [[ $_rules_present -eq 0 || ${FORCE_REGEN:-0} == 1 ]]; then
  say "generate allowlist from currently connected USB devices → $RULES"
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$tmp"' EXIT
  # Root sees the full USB set (HID used for this session included).
  if ! sudo usbguard generate-policy | tee "$tmp" >/dev/null; then
    die "usbguard generate-policy failed"
  fi
  if [[ ! -s $tmp ]]; then
    die "generate-policy produced empty rules — abort (would lock out USB)"
  fi
  sudo install -d -m 0750 -o root -g root /etc/usbguard
  sudo install -m 0600 -o root -g root "$tmp" "$RULES"
  rm -f "$tmp"
  trap - EXIT
else
  say "keep existing $RULES (FORCE_REGEN=1 to rewrite)"
fi

if [[ "${SKIP_ENABLE:-0}" != 1 ]]; then
  say "enable --now usbguard.service"
  sudo systemctl enable --now usbguard.service \
    || die "could not enable usbguard"
  systemctl is-active --quiet usbguard \
    && echo "✓ usbguard active" \
    || warn "usbguard enabled but not active — check: journalctl -u usbguard"
else
  echo "✓ rules ready (SKIP_ENABLE=1 — not starting service)"
fi

echo "  new device: sudo usbguard list-devices && sudo usbguard allow-device <id> -p"
unset -v _rules_present
