#!/usr/bin/env bash
# Thin MCP-ish adb bridge: exposes logcat/devices over stdio JSON-lines for agents.
# Prefer real MCP when available; otherwise a small helper loop.
set -euo pipefail
export PATH="${ANDROID_HOME:-/opt/android-sdk}/platform-tools:${PATH}"

if npm ls -g adb-mcp >/dev/null 2>&1; then
  exec npx --yes adb-mcp "$@"
fi

# Fallback: simple request/response over stdin (list|logcat|shell).
echo '{"ok":true,"tools":["devices","logcat","shell"],"hint":"send: devices | logcat | shell <cmd>"}'
while IFS= read -r line; do
  case "$line" in
    devices) adb devices -l ;;
    logcat) adb logcat -d -t 100 ;;
    shell\ *) adb shell "${line#shell }" ;;
    *) echo "{\"error\":\"unknown:$line\"}" ;;
  esac
done
