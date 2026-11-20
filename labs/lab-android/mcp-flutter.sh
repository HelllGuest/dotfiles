#!/usr/bin/env bash
# Flutter/Dart MCP inside lab-android (stdio).
set -euo pipefail
export PATH="${FLUTTER_HOME:-/opt/flutter}/bin:${PATH}"
if command -v flutter-mcp >/dev/null 2>&1; then
  exec flutter-mcp "$@"
fi
if npm ls -g @flutter/mcp-server >/dev/null 2>&1; then
  exec npx --offline --no @flutter/mcp-server "$@"
fi
echo "flutter MCP package missing — run labs-setup / rebuild lab-android" >&2
exit 1
