#!/usr/bin/env bash
# Slice 2b: detonation capture + lab MCP scaffolding.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/lab-detonate.sh" \
  "$ROOT/scripts/lab-mcp.sh" \
  "$ROOT/labs/lab-capture/Containerfile" \
  "$ROOT/labs/lab-capture/inetsim.conf" \
  "$ROOT/labs/lab-capture/entrypoint.sh" \
  "$ROOT/labs/lab-web/mcp-playwright.sh" \
  "$ROOT/labs/lab-web/mcp-devtools.sh" \
  "$ROOT/labs/lab-android/mcp-flutter.sh" \
  "$ROOT/labs/lab-android/mcp-adb.sh" \
  "$ROOT/labs/mcp-host.example.json"
do
  [[ -f $f ]] || fail "missing $f"
done

bash -n "$ROOT/scripts/lab-detonate.sh" || fail "bash -n lab-detonate"
bash -n "$ROOT/scripts/lab-mcp.sh" || fail "bash -n lab-mcp"
[[ -x $ROOT/scripts/lab-detonate.sh ]] || fail "lab-detonate not executable"
[[ -x $ROOT/scripts/lab-mcp.sh ]] || fail "lab-mcp not executable"

grep -q '192.168.200.1' "$ROOT/labs/lab-capture/inetsim.conf" \
  || fail "INetSim must bind malware gateway IP"
ZONE_LIB="$ROOT/scripts/lib/lab-malware-zone.sh"
[[ -f $ZONE_LIB ]] || fail "missing lib/lab-malware-zone.sh"
grep -q 'ensure_lab_malware_zone' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must call ensure_lab_malware_zone"
grep -q 'ensure_lab_malware_zone' "$ROOT/scripts/firewalld-migrate.sh" \
  || fail "firewalld-migrate must call ensure_lab_malware_zone"
grep -q 'set-target=DROP' "$ZONE_LIB" \
  || fail "lab-malware must set-target=DROP"
grep -q 'remove-masquerade' "$ZONE_LIB" \
  || fail "lab-malware must disable masquerade"
grep -q 'remove-forward-port' "$ZONE_LIB" \
  || fail "lab-malware must clear forward-ports"
grep -qE 'add-masquerade|add-forward-port' "$ZONE_LIB" \
  && fail "lab-malware zone must never enable masquerade/forward-port" || true
grep -q 'zone=block --remove-interface=virbr-malware' "$ZONE_LIB" \
  || fail "lab-malware helper must unbind legacy block zone"
grep -q 'virbr-malware' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must use virbr-malware"
grep -q 'PolarProxy' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must mention PolarProxy"
grep -q 'linux-define' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must define linux VM helpers"
grep -q 'windows-define' "$ROOT/scripts/lab-detonate.sh" \
  || fail "detonate must define windows VM helpers"

grep -q '@playwright/mcp' "$ROOT/labs/lab-web/Containerfile" \
  || fail "lab-web must install @playwright/mcp"
grep -q 'mcp-playwright' "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-mcp must launch playwright"
grep -q 'mcp-flutter' "$ROOT/scripts/lab-mcp.sh" \
  || fail "lab-mcp must launch flutter MCP"
grep -q 'android-tools' "$ROOT/labs/lab-android/Containerfile" \
  || fail "lab-android must ship android-tools (adb)"

grep -q 'lab-detonate()' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell-functions lab-detonate missing"
grep -q 'lab-mcp()' "$ROOT/stow/zsh/.shell-functions" \
  || fail "shell-functions lab-mcp missing"
grep -q 'SETUP_DETONATE' "$ROOT/scripts/configure.sh" \
  || fail "configure must expose SETUP_DETONATE"
grep -q 'lab-capture' "$ROOT/scripts/labs-setup.sh" \
  || fail "labs-setup must build lab-capture"

# No host secret mounts in MCP launcher
grep -E '(-v|--bind).*\.ssh|\.gnupg' "$ROOT/scripts/lab-mcp.sh" \
  && fail "lab-mcp must not mount secrets" || true

echo "PASS: slice2b-detonate-mcp.test.sh"
