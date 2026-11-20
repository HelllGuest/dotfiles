#!/usr/bin/env bash
# Chrome DevTools MCP via Arch chromium (headless CDP).
set -euo pipefail
chromium="${PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH:-/usr/bin/chromium}"
# Prefer dedicated package when present; else delegate to mcp-playwright.
if command -v chrome-devtools-mcp >/dev/null 2>&1; then
  extra=()
  case "${1:-}" in
    -h|--help|-V|--version) ;;
    *)
      [[ -x "$chromium" ]] && extra+=(--executablePath "$chromium")
      [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && extra+=(--headless)
      ;;
  esac
  exec chrome-devtools-mcp "${extra[@]}" "$@"
fi
exec /usr/local/bin/mcp-playwright "$@"
