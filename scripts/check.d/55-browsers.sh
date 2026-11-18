# 55-browsers.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Flatpak browsers and browser policies (Chrome, Brave, Firefox, Zen, LibreWolf).

# shellcheck source=lib/browsers.sh
source "$REPO_ROOT/scripts/lib/browsers.sh"

echo "--- Flatpaks ---"
if command -v flatpak >/dev/null 2>&1; then
    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        if flatpak list --app 2>/dev/null | grep -q "$app"; then
            echo "✓ $app installed"
        else
            check_fail "$app missing (run scripts/install-flatpaks.sh)"
        fi
    done < <(read_browser_flatpaks)
    if flatpak list --app 2>/dev/null | grep -q com.protonvpn.www; then
        echo "✓ com.protonvpn.www installed"
    else
        check_fail "com.protonvpn.www missing (run scripts/install-flatpaks.sh)"
    fi
else
    check_fail "flatpak not installed"
fi

echo "--- Browser policies ---"
for policy in /etc/opt/chrome/policies/managed/00-privacy.json /etc/brave/policies/managed/00-privacy.json; do
    if [[ -f "$policy" ]]; then
        echo "✓ $policy"
    else
        check_fail "$policy missing (run scripts/browser-hardening.sh)"
    fi
done
# Deployed Chromium policies must equal base + brand overlay from the repo.
check_chromium_policy() {
    local label=$1 extra=$2 dest=$3 want
    if [[ ! -f "$dest" ]]; then
        check_fail "$label policy file missing (bash scripts/browser-hardening.sh)"
    elif ! want="$(chromium_policy_json "$extra" 2>/dev/null | jq -S .)"; then
        check_fail "$label policy check needs jq + browsers/policies (bash scripts/browser-hardening.sh)"
    elif [[ "$(jq -S . "$dest" 2>/dev/null)" == "$want" ]]; then
        echo "✓ $label policies match repo ($(jq length "$dest") keys)"
    else
        check_fail "$label policies stale vs repo (bash scripts/browser-hardening.sh)"
    fi
}
check_chromium_policy Chrome "$CHROME_EXTRA" /etc/opt/chrome/policies/managed/00-privacy.json
check_chromium_policy Brave "$BRAVE_EXTRA" /etc/brave/policies/managed/00-privacy.json
if [[ -f /etc/firefox/policies/policies.json ]] \
  && grep -q '"DisableTelemetry": true' /etc/firefox/policies/policies.json; then
    echo "✓ /etc/firefox/policies/policies.json DisableTelemetry"
elif [[ -f /etc/firefox/policies/policies.json ]]; then
    check_fail "/etc/firefox/policies stale (bash scripts/browser-hardening.sh)"
else
    check_fail "/etc/firefox/policies/policies.json missing (bash scripts/browser-hardening.sh)"
fi
zen_pol="$(zen_systemconfig_dir)/policies/policies.json"
if [[ -f "$zen_pol" ]] && grep -q '"DisableTelemetry": true' "$zen_pol"; then
    echo "✓ Zen Flatpak systemconfig DisableTelemetry"
elif flatpak list --app 2>/dev/null | grep -q 'app\.zen_browser\.zen'; then
    check_fail "Zen Flatpak policies missing (run scripts/browser-hardening.sh)"
else
    echo "○ Zen Flatpak not installed"
fi
zen_userjs_ok=0
if [[ -d "${HOME}/.var/app/app.zen_browser.zen/.zen" ]]; then
    while IFS= read -r -d '' uj; do
        prof="$(dirname "$uj")"
        if [[ -f "$prof/prefs.js" ]]; then
            zen_userjs_ok=1
            break
        fi
    done < <(find "${HOME}/.var/app/app.zen_browser.zen/.zen" -mindepth 2 -maxdepth 2 -name user.js -print0 2>/dev/null)
fi
if [[ "$zen_userjs_ok" -eq 1 ]]; then
    echo "✓ Zen user.js deployed in profile(s)"
elif flatpak list --app 2>/dev/null | grep -qE 'app\.zen_browser\.zen|io\.github\.zen_browser\.zen'; then
    check_fail "Zen user.js missing — launch Zen once, then run scripts/browser-hardening.sh"
fi
if [[ -f "${HOME}/.var/app/app.zen_browser.zen/.zen/Profile Groups/user.js" ]]; then
    check_fail "stray Zen user.js under Profile Groups (re-run browser-hardening.sh)"
fi
lw_ov="${HOME}/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg"
if [[ -f "$lw_ov" ]] && grep -q 'toolkit.telemetry.enabled' "$lw_ov"; then
    echo "✓ LibreWolf librewolf.overrides.cfg"
elif flatpak list --app 2>/dev/null | grep -q 'io\.gitlab\.librewolf-community'; then
    check_fail "LibreWolf overrides missing (run scripts/browser-hardening.sh)"
else
    echo "○ LibreWolf Flatpak not installed"
fi
