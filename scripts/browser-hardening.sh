#!/usr/bin/env bash
# browser-hardening.sh — deploy Chromium-family policies + Zen prefs + verify flatpaks
# Chrome/Brave flatpaks read host policies from /etc/opt/chrome and /etc/brave.
# Zen: user.js per profile under ~/.var/app/.../.zen/<profile>/ (not .zen/ root).
# LibreWolf: upstream-hardened flatpak.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME_SRC="$REPO_ROOT/browsers/policies/chrome-managed.json"
BRAVE_SRC="$REPO_ROOT/browsers/policies/brave-managed.json"
ZEN_POLICY_SRC="$REPO_ROOT/browsers/policies/zen-policies.json"
ZEN_USERJS_SRC="$REPO_ROOT/browsers/zen/user.js"
ZEN_PROFILE_ROOT="${HOME}/.var/app/io.github.zen_browser.zen/.zen"

deploy_policy() {
  local src="$1" dest="$2"
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing policy source: $src" >&2
    return 0
  fi
  sudo mkdir -p "$(dirname "$dest")"
  sudo cp "$src" "$dest"
  sudo chmod 644 "$dest"
  echo "✓ deployed $(basename "$dest") → $dest"
}

deploy_zen_userjs() {
  if [[ ! -f "$ZEN_USERJS_SRC" ]]; then
    echo "WARN: missing Zen user.js source: $ZEN_USERJS_SRC" >&2
    return 0
  fi
  if [[ ! -d "$ZEN_PROFILE_ROOT" ]]; then
    echo "⚠ Zen not run yet — launch Zen once, then re-run: bash scripts/browser-hardening.sh"
    return 0
  fi
  local deployed=0
  local prof
  for prof in "$ZEN_PROFILE_ROOT"/*; do
    [[ -d "$prof" ]] || continue
    cp "$ZEN_USERJS_SRC" "$prof/user.js"
    chmod 644 "$prof/user.js"
    echo "✓ deployed Zen user.js → $prof/user.js"
    deployed=1
  done
  if [[ $deployed -eq 0 ]]; then
    echo "⚠ No Zen profile dirs under $ZEN_PROFILE_ROOT — launch Zen once, then re-run"
  fi
}

echo "→ Browser privacy hardening..."

deploy_policy "$CHROME_SRC" /etc/opt/chrome/policies/managed/00-privacy.json
deploy_policy "$BRAVE_SRC" /etc/brave/policies/managed/00-privacy.json
deploy_policy "$ZEN_POLICY_SRC" /etc/firefox/policies/policies.json
deploy_zen_userjs

BROWSERS=(
  com.brave.Browser
  io.github.zen_browser.zen
  com.google.Chrome
  io.gitlab.librewolf-community
)

if command -v flatpak >/dev/null 2>&1; then
  for app in "${BROWSERS[@]}"; do
    if flatpak info "$app" &>/dev/null; then
      echo "✓ flatpak installed: $app"
    else
      echo "⚠ flatpak missing: $app (run scripts/install-flatpaks.sh)"
    fi
  done
else
  echo "⚠ flatpak not installed — browser flatpaks skipped"
fi

cat <<'EOF'

Browser telemetry debloat:
  • Google Chrome  — /etc/opt/chrome/policies/managed/00-privacy.json
  • Brave          — /etc/brave/policies/managed/00-privacy.json
  • Zen            — browsers/zen/user.js → each profile dir; /etc/firefox/policies/policies.json
  • LibreWolf      — upstream defaults (telemetry off by design)

Verify: chrome://policy  brave://policy  about:policies (Zen)
Restart browsers after policy deploy.
EOF
