#!/usr/bin/env bash
# browser-hardening.sh — deploy Chromium-family policies + Zen prefs + verify flatpaks

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/browsers.sh
source "$REPO_ROOT/scripts/lib/browsers.sh"

echo "→ Browser privacy hardening..."

deploy_browser_policies
verify_browser_flatpaks

cat <<'EOF'

Browser telemetry debloat:
  • Google Chrome  — /etc/opt/chrome/policies/managed/00-privacy.json
  • Brave          — /etc/brave/policies/managed/00-privacy.json
  • Zen            — browsers/zen/user.js → each profile dir; /etc/firefox/policies/policies.json
  • LibreWolf      — upstream defaults (telemetry off by design)

Verify: chrome://policy  brave://policy  about:policies (Zen)
Restart browsers after policy deploy.
EOF
