#!/usr/bin/env bash
# Chrome DevTools MCP via Playwright chromium (headless CDP).
set -euo pipefail
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/home/lab/.cache/ms-playwright}"
# Prefer dedicated package when present; else Playwright MCP covers browser tooling.
if npm ls -g chrome-devtools-mcp >/dev/null 2>&1; then
  exec npx --yes chrome-devtools-mcp "$@"
fi
exec npx --yes @playwright/mcp "$@"
