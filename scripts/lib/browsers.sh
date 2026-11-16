#!/usr/bin/env bash
# Browser flatpak list + policy deploy helpers.

: "${REPO_ROOT:?REPO_ROOT must be set}"

BROWSERS_LIST="${REPO_ROOT}/packages/browsers.txt"
CHROMIUM_BASE="${REPO_ROOT}/browsers/policies/chromium-base.json"
# Brand overlays merged over chromium-base (missing file = base only).
CHROME_EXTRA="${REPO_ROOT}/browsers/policies/chrome-extra.json"
BRAVE_EXTRA="${REPO_ROOT}/browsers/policies/brave-extra.json"
ZEN_POLICY_SRC="${REPO_ROOT}/browsers/policies/zen-policies.json"
ZEN_USERJS_SRC="${REPO_ROOT}/browsers/zen/user.js"
LIBREWOLF_OVERRIDES_SRC="${REPO_ROOT}/browsers/librewolf/librewolf.overrides.cfg"
ZEN_FLATPAK_ID="app.zen_browser.zen"
BRAVE_FLATPAK_ID="com.brave.Browser"
LIBREWOLF_FLATPAK_ID="io.gitlab.librewolf-community"
ZEN_PROFILE_ROOT="${HOME}/.var/app/${ZEN_FLATPAK_ID}/.zen"
LIBREWOLF_HOME="${HOME}/.var/app/${LIBREWOLF_FLATPAK_ID}/.librewolf"

# Set by deploy_browser_policies when /etc writes need a re-run with sudo.
BROWSER_ETC_DEPLOY_FAILED=0

# Flatpak extension arch (arm64 → aarch64). Shared by deploy + check.
flatpak_ext_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|aarch64) printf '%s' "$arch" ;;
    arm64) printf 'aarch64' ;;
    *) printf 'x86_64' ;;
  esac
}

# Zen Flatpak systemconfig extension (mounted at /app/etc/zen).
zen_systemconfig_dir() {
  printf '%s/flatpak/extension/%s.systemconfig/%s/stable' \
    "${XDG_DATA_HOME:-$HOME/.local/share}" "$ZEN_FLATPAK_ID" "$(flatpak_ext_arch)"
}

# sudo: askpass when SUDO_ASKPASS set; else TTY prompt; else -n (no hang).
_browser_sudo() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  elif [[ -t 0 ]]; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

read_browser_flatpaks() {
  [[ -f "$BROWSERS_LIST" ]] || return 0
  grep -v '^#' "$BROWSERS_LIST" | grep -v '^[[:space:]]*$' || true
}

deploy_file_policy() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || { echo "WARN: missing policy source: $src" >&2; return 1; }
  if ! _browser_sudo mkdir -p "$(dirname "$dest")"; then
    echo "⚠ need sudo for $dest (re-run: bash scripts/browser-hardening.sh)" >&2
    return 1
  fi
  if ! _browser_sudo cp "$src" "$dest"; then
    echo "⚠ need sudo to write $dest" >&2
    return 1
  fi
  _browser_sudo chmod 644 "$dest" || true
  echo "✓ deployed $(basename "$dest") → $dest"
}

# Print chromium-base merged with an optional brand overlay (missing → base only).
chromium_policy_json() {
  local extra="$1"
  if [[ ! -f "$CHROMIUM_BASE" ]]; then
    echo "WARN: missing chromium base policy $CHROMIUM_BASE" >&2
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "WARN: jq not installed — cannot merge chromium policies" >&2
    return 1
  fi
  if [[ -n "$extra" && -f "$extra" ]]; then
    jq -s 'add' "$CHROMIUM_BASE" "$extra"
  else
    jq '.' "$CHROMIUM_BASE"
  fi
}

deploy_chromium_policy() {
  local extra="$1" dest="$2" merged
  merged="$(chromium_policy_json "$extra")" || return 1
  if ! _browser_sudo mkdir -p "$(dirname "$dest")"; then
    echo "⚠ need sudo for $dest (re-run: bash scripts/browser-hardening.sh)" >&2
    return 1
  fi
  if ! printf '%s\n' "$merged" | _browser_sudo tee "$dest" >/dev/null; then
    echo "⚠ need sudo to write $dest" >&2
    return 1
  fi
  _browser_sudo chmod 644 "$dest" || true
  echo "✓ deployed $(basename "$dest") → $dest"
}

# Only real profiles (prefs.js present). Skip "Profile Groups" and other dirs.
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
    if [[ -f "$prof/user.js" && ! -f "$prof/prefs.js" ]]; then
      rm -f "$prof/user.js"
      echo "✓ removed stray Zen user.js → $prof/user.js"
    fi
  done
  for prof in "$ZEN_PROFILE_ROOT"/*; do
    [[ -d "$prof" ]] || continue
    [[ -f "$prof/prefs.js" ]] || continue
    cp "$ZEN_USERJS_SRC" "$prof/user.js"
    chmod 644 "$prof/user.js"
    echo "✓ deployed Zen user.js → $prof/user.js"
    deployed=1
  done
  if [[ $deployed -eq 0 ]]; then
    echo "⚠ No Zen profile dirs with prefs.js under $ZEN_PROFILE_ROOT — launch Zen once, then re-run"
  fi
}

# Flatpak Zen does not see /etc/firefox; use systemconfig extension.
deploy_zen_flatpak_policies() {
  [[ -f "$ZEN_POLICY_SRC" ]] || return 0
  if ! command -v flatpak >/dev/null 2>&1; then
    return 0
  fi
  if ! flatpak info "$ZEN_FLATPAK_ID" &>/dev/null; then
    return 0
  fi
  local dest_dir dest
  dest_dir="$(zen_systemconfig_dir)/policies"
  dest="${dest_dir}/policies.json"
  mkdir -p "$dest_dir"
  cp "$ZEN_POLICY_SRC" "$dest"
  chmod 644 "$dest"
  echo "✓ deployed Zen Flatpak policies → $dest"
}

deploy_librewolf_overrides() {
  if [[ ! -f "$LIBREWOLF_OVERRIDES_SRC" ]]; then
    echo "WARN: missing LibreWolf overrides: $LIBREWOLF_OVERRIDES_SRC" >&2
    return 0
  fi
  if ! command -v flatpak >/dev/null 2>&1 \
    || ! flatpak info "$LIBREWOLF_FLATPAK_ID" &>/dev/null; then
    return 0
  fi
  mkdir -p "$LIBREWOLF_HOME"
  cp "$LIBREWOLF_OVERRIDES_SRC" "$LIBREWOLF_HOME/librewolf.overrides.cfg"
  chmod 644 "$LIBREWOLF_HOME/librewolf.overrides.cfg"
  echo "✓ deployed LibreWolf overrides → $LIBREWOLF_HOME/librewolf.overrides.cfg"
}

# Brave Flatpak reads /etc/brave/policies via host-etc; ensure path is visible.
ensure_brave_flatpak_policies_access() {
  if ! command -v flatpak >/dev/null 2>&1 \
    || ! flatpak info "$BRAVE_FLATPAK_ID" &>/dev/null; then
    return 0
  fi
  if flatpak override --user --show "$BRAVE_FLATPAK_ID" 2>/dev/null \
    | grep -q '/etc/brave/policies'; then
    echo "✓ Brave Flatpak already has /etc/brave/policies override"
    return 0
  fi
  if flatpak override --user --filesystem=/etc/brave/policies:ro \
    "$BRAVE_FLATPAK_ID" 2>/dev/null; then
    echo "✓ Brave Flatpak override: /etc/brave/policies:ro"
  else
    echo "⚠ could not set Brave Flatpak policy override (host-etc may still work)" >&2
  fi
}

deploy_browser_policies() {
  BROWSER_ETC_DEPLOY_FAILED=0

  # User-writable first so non-interactive / no-sudo still hardens Flatpak browsers.
  deploy_zen_flatpak_policies
  deploy_zen_userjs
  deploy_librewolf_overrides
  ensure_brave_flatpak_policies_access

  # /etc needs sudo — failures must not skip the layers above.
  if ! deploy_chromium_policy "$CHROME_EXTRA" /etc/opt/chrome/policies/managed/00-privacy.json; then
    BROWSER_ETC_DEPLOY_FAILED=1
  fi
  if ! deploy_chromium_policy "$BRAVE_EXTRA" /etc/brave/policies/managed/00-privacy.json; then
    BROWSER_ETC_DEPLOY_FAILED=1
  fi
  if ! deploy_file_policy "$ZEN_POLICY_SRC" /etc/firefox/policies/policies.json; then
    BROWSER_ETC_DEPLOY_FAILED=1
  fi

  if [[ "$BROWSER_ETC_DEPLOY_FAILED" -ne 0 ]]; then
    echo "⚠ /etc browser policies not fully updated — run in a terminal: bash scripts/browser-hardening.sh" >&2
    return 1
  fi
  return 0
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
