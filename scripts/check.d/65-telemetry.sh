# 65-telemetry.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# Telemetry opt-outs (env, GNOME, editors, AI tools).

echo "--- Telemetry / privacy ---"
TELEMETRY_ENV_D="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/90-telemetry-optout.conf"
if [[ -f "$TELEMETRY_ENV_D" ]]; then
    echo "✓ $TELEMETRY_ENV_D"
    for key in DO_NOT_TRACK DISABLE_TELEMETRY OTEL_SDK_DISABLED HEADROOM_TELEMETRY GOTELEMETRY NEXT_TELEMETRY_DISABLED; do
        if grep -q "^${key}=" "$TELEMETRY_ENV_D"; then
            echo "✓ env $key"
        else
            check_fail "env $key missing in telemetry-optout.conf"
        fi
    done
else
    check_fail "telemetry-optout.conf missing (stow privacy / bash scripts/privacy-hardener.sh)"
fi
if command -v gsettings >/dev/null 2>&1; then
    if [[ "$(gsettings get org.gnome.desktop.privacy report-technical-problems 2>/dev/null)" == "false" ]]; then
        echo "✓ GNOME report-technical-problems=false"
    else
        check_fail "GNOME report-technical-problems not false (bash scripts/privacy-hardener.sh)"
    fi
fi
if [[ -f "${HOME}/.dart-tool/dart-flutter-telemetry.config" ]] \
  && grep -q '^reporting=0' "${HOME}/.dart-tool/dart-flutter-telemetry.config"; then
    echo "✓ Flutter/Dart reporting=0"
else
    echo "○ Flutter telemetry config missing (optional: bash scripts/privacy-hardener.sh)"
fi
if [[ -f "${HOME}/.claude/settings.json" ]] \
  && grep -q 'DISABLE_TELEMETRY' "${HOME}/.claude/settings.json"; then
    echo "✓ Claude settings DISABLE_TELEMETRY"
else
    echo "○ Claude settings telemetry flags missing (ai-rules install / privacy-hardener)"
fi
cursor_settings="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json"
if [[ -f "$cursor_settings" ]] \
  && grep -q '"telemetry.telemetryLevel": "off"' "$cursor_settings"; then
    echo "✓ Cursor telemetry.telemetryLevel=off"
else
    echo "○ Cursor telemetry off not confirmed"
fi
if [[ -f "$cursor_settings" ]] \
  && grep -q '"cursor.general.privacyMode": "enabled"' "$cursor_settings"; then
    echo "✓ Cursor privacyMode=enabled"
else
    echo "○ Cursor privacyMode not confirmed"
fi
# cursor.general.* belong only on Cursor; leftover keys on other IDEs are a bug.
for _non_cursor in \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity IDE/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Kiro/User/settings.json"
do
  if [[ -f "$_non_cursor" ]] && grep -q 'cursor\.general' "$_non_cursor"; then
    check_fail "cursor.general.* in non-Cursor settings: $_non_cursor (re-run privacy-hardener)"
  fi
done
unset _non_cursor
if [[ -f "${HOME}/.gemini/settings.json" ]] \
  && grep -q '"usageStatisticsEnabled": false' "${HOME}/.gemini/settings.json"; then
    echo "✓ Gemini usageStatisticsEnabled=false"
else
    echo "○ Gemini usage stats opt-out not confirmed"
fi
opencode_settings="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
if [[ -f "$opencode_settings" ]] \
  && grep -q '"share": "disabled"' "$opencode_settings"; then
    echo "✓ OpenCode share=disabled"
else
    echo "○ OpenCode share=disabled not confirmed"
fi
if [[ -f "$TELEMETRY_ENV_D" ]] && grep -q '^KIMI_DISABLE_TELEMETRY=' "$TELEMETRY_ENV_D"; then
    echo "✓ env KIMI_DISABLE_TELEMETRY"
else
    echo "○ env KIMI_DISABLE_TELEMETRY missing"
fi
if [[ -f "${HOME}/.claude/settings.json" ]] \
  && grep -q '"skipWebFetchPreflight": true' "${HOME}/.claude/settings.json"; then
    echo "✓ Claude skipWebFetchPreflight=true"
else
    echo "○ Claude skipWebFetchPreflight not confirmed"
fi
