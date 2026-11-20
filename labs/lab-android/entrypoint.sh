#!/usr/bin/env bash
# First-boot SDK bootstrap (skipped when already present or non-interactive).
set -euo pipefail
# Keep stdout clean for stdio MCP commands (mcp-flutter / mcp-adb).
if [[ ! -x /opt/flutter/bin/flutter && -t 0 && -t 1 ]]; then
  echo "lab-android: cloning Flutter stable into /opt/flutter..." >&2
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git /opt/flutter >&2
fi
if [[ ! -d /opt/android-sdk/cmdline-tools/latest && -t 0 && -t 1 ]]; then
  echo "lab-android: Android cmdline-tools not present — install manually:" >&2
  echo "  sdkmanager --install 'platform-tools' 'platforms;android-35' 'build-tools;35.0.0'" >&2
fi
exec "$@"
