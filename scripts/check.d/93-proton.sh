# 93-proton.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Proton VPN API reachability.

echo "--- Proton VPN ---"
if [ -f "$REPO_ROOT/security/scripts/proton-connectivity-check.sh" ]; then
    bash "$REPO_ROOT/security/scripts/proton-connectivity-check.sh" 2>/dev/null || echo "⚠ Proton API unreachable (run security/scripts/proton-connectivity-check.sh)"
else
    check_fail "proton-connectivity-check.sh missing"
fi
