#!/usr/bin/env bash
# Browser flatpak list + policy deploy helpers.

: "${REPO_ROOT:?REPO_ROOT must be set}"

BROWSERS_LIST="${REPO_ROOT}/packages/browsers.txt"
CHROMIUM_BASE="${REPO_ROOT}/browsers/policies/chromium-base.json"
CHROME_EXTRA="${REPO_ROOT}/browsers/policies/chrome-extra.json"
BRAVE_EXTRA="${REPO_ROOT}/browsers/policies/brave-extra.json"
ZEN_POLICY_SRC="${REPO_ROOT}/browsers/policies/zen-policies.json"
ZEN_USERJS_SRC="${REPO_ROOT}/browsers/zen/user.js"
ZEN_FLATPAK_ID="app.zen_browser.zen"
ZEN_PROFILE_ROOT="${HOME}/.var/app/${ZEN_FLATPAK_ID}/.zen"

read_browser_flatpaks() {
  [[ -f "$BROWSERS_LIST" ]] || return 0
  grep -v '^#' "$BROWSERS_LIST" | grep -v '^[[:space:]]*$' || true
}

deploy_file_policy() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || { echo "WARN: missing policy source: $src" >&2; return 0; }
  sudo mkdir -p "$(dirname "$dest")"
  sudo cp "$src" "$dest"
  sudo chmod 644 "$dest"
  echo "✓ deployed $(basename "$dest") → $dest"
}

deploy_chromium_policy() {
  local extra="$1" dest="$2"
  if [[ ! -f "$CHROMIUM_BASE" || ! -f "$extra" ]]; then
    echo "WARN: missing chromium policy parts for $dest" >&2
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN: jq not installed — cannot merge chromium policies for $dest" >&2
    return 0
  fi
  sudo mkdir -p "$(dirname "$dest")"
  jq -s 'add' "$CHROMIUM_BASE" "$extra" | sudo tee "$dest" >/dev/null
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
  local deployed=0 prof
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

deploy_browser_policies() {
  deploy_chromium_policy "$CHROME_EXTRA" /etc/opt/chrome/policies/managed/00-privacy.json
  deploy_chromium_policy "$BRAVE_EXTRA" /etc/brave/policies/managed/00-privacy.json
  deploy_file_policy "$ZEN_POLICY_SRC" /etc/firefox/policies/policies.json
  deploy_zen_userjs
}

verify_browser_flatpaks() {
  command -v flatpak >/dev/null 2>&1 || { echo "⚠ flatpak not installed"; return 0; }
  local app
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if flatpak info "$app" &>/dev/null; then
      echo "✓ flatpak installed: $app"
    else
      echo "⚠ flatpak missing: $app (run scripts/install-flatpaks.sh)"
    fi
  done < <(read_browser_flatpaks)
}
