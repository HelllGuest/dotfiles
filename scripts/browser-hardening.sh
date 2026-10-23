#!/usr/bin/env bash
# browser-hardening.sh — deploy Chromium-family policies + Zen/LibreWolf prefs + verify flatpaks

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/browsers.sh
source "$REPO_ROOT/scripts/lib/browsers.sh"

echo "→ Browser privacy hardening..."

etc_ok=0
deploy_browser_policies && etc_ok=1 || true
verify_browser_flatpaks

cat <<'EOF'

Browser telemetry debloat:
  • Google Chrome  — /etc/opt/chrome/policies/managed/00-privacy.json
  • Brave          — /etc/brave/policies/managed/00-privacy.json (+ Flatpak override)
  • Zen            — user.js per profile; Flatpak systemconfig policies; /etc/firefox/policies
  • LibreWolf      — upstream policies + librewolf.overrides.cfg

Verify: chrome://policy  brave://policy  about:policies (Zen/LibreWolf)
Restart browsers after policy deploy.
EOF

# Non-zero if /etc layer failed (user-layer still applied above).
[[ "$etc_ok" -eq 1 ]]
