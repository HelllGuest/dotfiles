#!/usr/bin/env bash
# MCP stdio entry: Playwright tools inside lab-web (no host browser).
set -euo pipefail
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/home/lab/.cache/ms-playwright}"
exec npx --yes @playwright/mcp "$@"
