#!/usr/bin/env bash
# validate-configs.sh — smoke-test stowed configs against installed tools

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
FAIL=0

warn() { echo "⚠ $*"; }
ok()   { echo "✓ $*"; }
fail() { echo "✗ $*"; FAIL=1; }

echo "=== Terminals ==="

if command -v ghostty >/dev/null 2>&1; then
  OUT=$(timeout 5s ghostty -e true 2>&1 || true)
  if echo "$OUT" | rg -q 'FileIsEmpty|both config files'; then
    fail "ghostty: remove empty ~/.config/ghostty/config.ghostty if present"
  fi
  if echo "$OUT" | rg -qi 'invalid|unknown config'; then
    fail "ghostty: unknown config keys (see log above)"
    echo "$OUT" | rg -i 'invalid|unknown|Ignoring unknown' | head -5
  else
    ok "ghostty config loads"
  fi
else
  warn "ghostty not installed"
fi

if command -v kitty >/dev/null 2>&1; then
  OUT=$(timeout 5s kitty --config="$HOME/.config/kitty/kitty.conf" -1 -e true 2>&1 || true)
  if echo "$OUT" | rg -q 'Ignoring unknown config key'; then
    fail "kitty: unknown config keys"
    echo "$OUT" | rg 'Ignoring unknown' | head -5
  else
    ok "kitty config loads"
  fi
  if [[ ! -f "$REPO_ROOT/stow/kitty/.config/kitty/sessions/dev.conf" ]]; then
    fail "kitty: missing sessions/dev.conf"
  fi
else
  warn "kitty not installed"
fi

for term_pair in \
  "alacritty:$HOME/.config/alacritty/alacritty.toml" \
  "contour:$HOME/.config/contour/contour.yml"
do
  bin="${term_pair%%:*}"
  cfg="${term_pair#*:}"
  if command -v "$bin" >/dev/null 2>&1; then
    if [[ -f "$cfg" || -L "$cfg" ]]; then
      ok "$bin config present"
    else
      warn "$bin installed but config missing (stow $bin?)"
    fi
  fi
done

echo ""
echo "=== Git / delta ==="
if git config --get pull.rebase >/dev/null 2>&1; then
  ok "git config (pull.rebase=$(git config --get pull.rebase))"
else
  fail "git: XDG config not loaded (run desktop/scripts/git-setup.sh)"
fi
if command -v delta >/dev/null 2>&1; then
  ok "delta installed"
else
  fail "delta missing"
fi

echo ""
echo "=== Shell ==="
export TERM="${TERM:-xterm-256color}"
if command -v starship >/dev/null 2>&1; then
  starship print-config >/dev/null 2>&1 && ok "starship config" || fail "starship config invalid"
fi
if command -v atuin >/dev/null 2>&1; then
  atuin doctor >/dev/null 2>&1 && ok "atuin config" || fail "atuin doctor failed"
fi

echo ""
echo "=== Neovim ==="
if command -v nvim >/dev/null 2>&1; then
  OUT=$(timeout 15s nvim --headless -e true 2>&1 || true)
  if echo "$OUT" | rg -q 'Failed to run .config. for blink.cmp'; then
    fail "nvim: blink.cmp config error"
  elif echo "$OUT" | rg -q 'nvim-treesitter.configs'; then
    fail "nvim: old treesitter API in use"
  else
    ok "nvim config loads"
  fi
else
  warn "nvim not installed"
fi

echo ""
echo "=== GNOME ==="
if [[ -f "$REPO_ROOT/desktop/gnome/dconf/user.conf" ]]; then
  ok "desktop/gnome/dconf/user.conf present"
fi
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All config checks passed."
else
  echo "Some config checks failed."
  exit 1
fi
