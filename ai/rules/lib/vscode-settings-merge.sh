# shellcheck shell=bash
# ai-rules/lib/vscode-settings-merge.sh — single merge for AI & VS Code-family telemetry JSON
# Used by security/lib/telemetry.sh and ai-rules/install.sh (kit-portable).

VSCODE_TELEMETRY_FAMILY_KEYS=(
  telemetry.telemetryLevel
  telemetry.enableTelemetry
  telemetry.enableCrashReporter
  telemetry.feedback.enabled
  crashReporting.enabled
  workbench.enableExperiments
  workbench.settings.enableNaturalLanguageSearch
)

VSCODE_TELEMETRY_CURSOR_KEYS=(
  cursor.general.enableShadowWorkspace
  cursor.general.allowAnonymousUsage
  cursor.general.privacyMode
)

# True only for Cursor app trees (not paths that merely contain "cursor").
vscode_is_cursor_settings_path() {
  case "$1" in
    */Cursor/*|*/.cursor/*) return 0 ;;
    *) return 1 ;;
  esac
}

vscode_telemetry_keys_for_path() {
  local settings=$1
  local keys=("${VSCODE_TELEMETRY_FAMILY_KEYS[@]}")
  if vscode_is_cursor_settings_path "$settings"; then
    keys+=("${VSCODE_TELEMETRY_CURSOR_KEYS[@]}")
  fi
  printf '%s\n' "${keys[@]}"
}

# Write tmp to settings: no-op if identical, preserve symlinks, else chmod + mv.
_settings_write_atomic() {
  local tmp=$1 settings=$2 mode=$3
  if [[ -f "$settings" ]] && cmp -s "$tmp" "$settings"; then
    rm -f "$tmp"
  elif [[ -L "$settings" ]]; then
    cat "$tmp" > "$settings"
    rm -f "$tmp"
  else
    chmod "$mode" "$tmp" 2>/dev/null || true
    mv "$tmp" "$settings"
  fi
}

# Merge telemetry-related keys from kit into settings.json (jq required).
# Non-Cursor targets: also delete leftover cursor.general.* keys.
# Parent User/ must already exist (no orphan IDE trees).
vscode_merge_settings_telemetry() {
  local settings=$1
  local kit=$2
  [[ -f "$kit" ]] || return 1
  [[ -d "$(dirname "$settings")" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local tmp keys_json strip_json
  tmp="$(mktemp)"
  keys_json="$(vscode_telemetry_keys_for_path "$settings" | jq -R . | jq -s .)"
  strip_json='[]'
  if ! vscode_is_cursor_settings_path "$settings"; then
    strip_json="$(printf '%s\n' "${VSCODE_TELEMETRY_CURSOR_KEYS[@]}" | jq -R . | jq -s .)"
  fi
  if [[ ! -s "$settings" ]]; then
    jq --argjson keys "$keys_json" '
      . as $kit
      | reduce $keys[] as $k ({}; .[$k] = $kit[$k])
      | with_entries(select(.value != null))
    ' "$kit" > "$tmp"
  else
    jq --argjson keys "$keys_json" --argjson strip "$strip_json" -s '
      .[0] as $user | .[1] as $kit
      | ($user * (
          reduce $keys[] as $k ({}; if $kit[$k] != null then .[$k] = $kit[$k] else . end)
        ))
      | reduce $strip[] as $k (.; del(.[$k]))
    ' "$settings" "$kit" > "$tmp"
  fi
  _settings_write_atomic "$tmp" "$settings" 644
}

vscode_settings_targets() {
  cat <<EOF
${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json
$HOME/.cursor/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity IDE/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Kiro/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json
${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json
EOF
}

# Merge Gemini CLI telemetry opt-outs from kit JSON into settings.json (0600 on fresh install).
gemini_merge_settings_telemetry() {
  local settings=$1
  local kit=$2
  [[ -f "$kit" ]] || return 1
  if [[ ! -s "$settings" ]]; then
    if [[ -L "$settings" ]]; then
      cat "$kit" > "$settings"
    else
      install -m 0600 "$kit" "$settings"
    fi
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 1
  local tmp
  tmp="$(mktemp)"
  if jq -s --slurpfile k "$kit" '
    (if length == 0 then {}
     elif length == 1 and (.[0] | type == "object") then .[0]
     else error("expected JSON object") end) * $k[0]
  ' "$settings" > "$tmp"; then
    _settings_write_atomic "$tmp" "$settings" 600
  else
    rm -f "$tmp"
    return 1
  fi
}

# Merge Claude Code telemetry + co-author flags from kit JSON; keep user hooks/plugins/theme.
claude_merge_settings_telemetry() {
  local settings=$1
  local kit=$2
  [[ -f "$kit" ]] || return 1
  if [[ ! -s "$settings" ]]; then
    if [[ -L "$settings" ]]; then
      cat "$kit" > "$settings"
    else
      install -m 0600 "$kit" "$settings"
    fi
    return 0
  fi
  command -v jq >/dev/null 2>&1 || return 1
  local tmp
  tmp="$(mktemp)"
  if jq -s --slurpfile k "$kit" '
    (if length == 0 then {}
     elif length == 1 and (.[0] | type == "object") then .[0]
     else error("expected JSON object") end) as $user
    | $k[0] as $kit
    | $user * {
        includeCoAuthoredBy: $kit.includeCoAuthoredBy,
        skipWebFetchPreflight: ($kit.skipWebFetchPreflight // $user.skipWebFetchPreflight),
        env: (($user.env // {}) + ($kit.env // {}))
      }
  ' "$settings" > "$tmp"; then
    _settings_write_atomic "$tmp" "$settings" 600
  else
    rm -f "$tmp"
    return 1
  fi
}
