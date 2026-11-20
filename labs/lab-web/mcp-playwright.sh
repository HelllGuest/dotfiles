#!/usr/bin/env bash
# MCP stdio entry: Playwright tools inside lab-web (no host browser).
set -euo pipefail
chromium="${PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH:-/usr/bin/chromium}"
extra=()
case "${1:-}" in
  -h|--help|-V|--version) ;;
  *)
    [[ -x "$chromium" ]] && extra+=(--executable-path "$chromium")
    [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && extra+=(--headless)
    extra+=(--no-sandbox)
    ;;
esac
if command -v mcp-server-playwright >/dev/null 2>&1; then
  exec mcp-server-playwright "${extra[@]}" "$@"
fi
if command -v playwright-mcp >/dev/null 2>&1; then
  exec playwright-mcp "${extra[@]}" "$@"
fi
exec npx --offline --no @playwright/mcp "${extra[@]}" "$@"
