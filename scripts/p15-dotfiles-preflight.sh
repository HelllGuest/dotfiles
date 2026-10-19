#!/usr/bin/env bash
# p15-dotfiles-preflight.sh — verify a fresh P15 Arch+GNOME host before ./install.sh
# Run in a GNOME session terminal as the normal user (sudo for checks that need it).
#
# Usage (after clone):
#   bash scripts/p15-dotfiles-preflight.sh
# Or from repo root before clone is optional — install missing bits, then print next commands.

set -euo pipefail

ok() { printf 'PASS: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
FAILS=0

echo "== P15 dotfiles preflight =="

# Session
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  ok "graphical session (DISPLAY/WAYLAND set)"
else
  warn "no DISPLAY/WAYLAND — GNOME dconf/extension steps need a logged-in GNOME session"
fi

# Identity / sudo
if [[ "$(id -u)" -eq 0 ]]; then
  fail "run as normal user (not root); install.sh uses sudo"
else
  ok "user=$(id -un) uid=$(id -u)"
fi
if sudo -n true 2>/dev/null; then
  ok "passwordless sudo"
elif sudo -v; then
  ok "sudo authenticated"
else
  fail "sudo not available — add user to wheel and re-login"
fi

# Network
if ping -c1 -W3 archlinux.org >/dev/null 2>&1 || ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
  ok "network"
else
  fail "no network — nmcli device wifi connect 'SSID' --ask"
fi

# Hostname (profiles/p15.sh matches hostname p15)
HOST="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)"
if [[ "$HOST" == "p15" ]]; then
  ok "hostname=p15 (profiles/p15.sh)"
else
  warn "hostname=$HOST — expected p15 for hostname profile; hardware detect still finds thinkpad-p15"
fi

# DMI / GPU
# shellcheck source=lib/dmi.sh
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$REPO_ROOT/scripts/lib/dmi.sh" ]]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/lib/dmi.sh"
  if is_thinkpad_p15; then
    ok "DMI ThinkPad P15"
  else
    warn "DMI does not match P15: $(dmi_label)"
  fi
  if has_nvidia_gpu; then
    ok "NVIDIA GPU present (lspci)"
    lspci -nn 2>/dev/null | grep -iE 'vga|3d|display.*\[10de:' || true
  else
    warn "no NVIDIA VGA/3D in lspci — Optimus profile will skip NVIDIA block"
  fi
else
  warn "repo lib/dmi.sh missing — run from cloned dotfiles"
fi

# Tools for clone + install
need_pkgs=()
for c in git curl sudo; do
  if command -v "$c" >/dev/null 2>&1; then
    ok "have $c"
  else
    need_pkgs+=("$c")
    fail "missing $c"
  fi
done
if ! pacman -Q base-devel >/dev/null 2>&1; then
  # base-devel is a group
  if pacman -Qg base-devel >/dev/null 2>&1; then
    ok "base-devel group installed"
  else
    need_pkgs+=(base-devel)
    warn "base-devel group not fully installed (AUR/paru may need it)"
  fi
fi

if ((${#need_pkgs[@]})); then
  echo "Installing missing packages: ${need_pkgs[*]}"
  sudo pacman -S --needed --noconfirm "${need_pkgs[@]}"
fi

# Disk / EFI / LUKS sanity
if findmnt -n -o FSTYPE / | grep -q btrfs; then
  ok "root is btrfs"
else
  warn "root FSTYPE=$(findmnt -n -o FSTYPE /)"
fi
if [[ -f /etc/kernel/cmdline ]] && grep -q 'rd.luks.name=' /etc/kernel/cmdline; then
  ok "kernel cmdline has rd.luks.name"
else
  warn "missing /etc/kernel/cmdline LUKS entry"
fi
if [[ -d /boot/EFI/Linux ]] && ls /boot/EFI/Linux/arch-linux-lts.efi >/dev/null 2>&1; then
  ok "UKI arch-linux-lts.efi present"
else
  warn "UKI missing under /boot/EFI/Linux"
fi

# NVIDIA packages (install.sh will pull them; preflight can soft-check)
if pacman -Q nvidia-open-dkms nvidia-utils nvidia-prime >/dev/null 2>&1; then
  ok "nvidia-open-dkms nvidia-utils nvidia-prime already installed"
else
  ok "nvidia packages not installed yet — install.sh / packages/pacman.txt will pull them"
fi

# Placeholder user from install example
if [[ "$(id -un)" == "YOURUSER" ]]; then
  fail "username is still YOURUSER — rename before living on this account"
fi

echo
if [[ "$FAILS" -gt 0 ]]; then
  echo "Preflight: $FAILS failure(s). Fix, then re-run."
  exit 1
fi

echo "Preflight: ready."
echo
echo "Next (GNOME session terminal):"
echo "  git clone https://github.com/HelllGuest/dotfiles.git ~/dotfiles"
echo "  cd ~/dotfiles"
echo "  git pull   # if you already cloned an older tree"
echo "  ./install.sh"
echo "  # install.sh: Optimus + sync-agent-skills + caveman + android-ui + ghidra-cli + REA"
echo "  # Manual AI-only re-run:"
echo "  #   bash scripts/sync-agent-skills.sh"
echo "  #   bash scripts/install-caveman.sh"
echo "  #   bash scripts/install-android-ui-skills.sh"
echo "  #   bash scripts/install-ghidra-cli.sh"
echo "  #   bash scripts/install-rea.sh"
echo "  bash profiles/thinkpad-p15.sh   # optional explicit Optimus pass"
echo "  reboot   # required for nouveau blacklist + NVIDIA early KMS"
echo "  prime-run glxinfo -B | grep -i renderer   # after reboot"
