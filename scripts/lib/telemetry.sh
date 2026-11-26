# shellcheck shell=bash
# lib/telemetry.sh — shared paths + helpers for privacy / telemetry opt-out
# Sourced by privacy-hardener.sh (REPO_ROOT preferred; else inferred from this file).

# Prefer caller REPO_ROOT; if unset or missing kit lib, infer from this file
# (scripts/lib → repo root). Wrong REPO_ROOT must not break privacy-hardener.
_telemetry_infer_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(_telemetry_infer_root)"
fi

TELEMETRY_ENV_D="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/90-telemetry-optout.conf"
TELEMETRY_KIT_VS="${REPO_ROOT}/ai-rules/vscode-family-telemetry.json"
TELEMETRY_FLUTTER_CFG="${HOME}/.dart-tool/dart-flutter-telemetry.config"

# Single implementation: ai-rules/lib/vscode-settings-merge.sh (kit + privacy-hardener).
_TELEMETRY_MERGE_LIB="${REPO_ROOT}/ai-rules/lib/vscode-settings-merge.sh"
if [[ ! -f "$_TELEMETRY_MERGE_LIB" ]]; then
  REPO_ROOT="$(_telemetry_infer_root)"
  TELEMETRY_KIT_VS="${REPO_ROOT}/ai-rules/vscode-family-telemetry.json"
  _TELEMETRY_MERGE_LIB="${REPO_ROOT}/ai-rules/lib/vscode-settings-merge.sh"
fi
unset -f _telemetry_infer_root
# shellcheck source=../../ai-rules/lib/vscode-settings-merge.sh
[[ -f "$_TELEMETRY_MERGE_LIB" ]] || {
  echo "error: missing $_TELEMETRY_MERGE_LIB (dotfiles ai-rules/lib required)" >&2
  return 1 2>/dev/null || exit 1
}
# shellcheck disable=SC1090
source "$_TELEMETRY_MERGE_LIB"
unset _TELEMETRY_MERGE_LIB

# Stable aliases for callers / tests.
# shellcheck disable=SC2034 # read by callers/tests after sourcing this helper
TELEMETRY_CURSOR_KEYS=("${VSCODE_TELEMETRY_CURSOR_KEYS[@]}")
telemetry_is_cursor_settings_path() { vscode_is_cursor_settings_path "$@"; }
telemetry_keys_for_settings_path() { vscode_telemetry_keys_for_path "$@"; }

# Merge only telemetry-related keys into settings.json (jq required).
# Non-Cursor targets: also delete leftover cursor.general.* keys.
telemetry_merge_vscode_settings() {
  local settings="$1"
  local kit="${2:-$TELEMETRY_KIT_VS}"
  vscode_merge_settings_telemetry "$settings" "$kit"
}

telemetry_vscode_targets() {
  vscode_settings_targets
}

telemetry_ensure_flutter() {
  mkdir -p "${HOME}/.dart-tool"
  if [[ -f "$TELEMETRY_FLUTTER_CFG" ]] && grep -q '^reporting=0' "$TELEMETRY_FLUTTER_CFG"; then
    return 0
  fi
  cat > "$TELEMETRY_FLUTTER_CFG" <<'EOF'
# Flutter/Dart telemetry — reporting disabled (privacy).
# Managed via scripts/privacy-hardener.sh / stow/flutter
reporting=0
EOF
}

telemetry_ensure_headroom() {
  export HEADROOM_TELEMETRY="${HEADROOM_TELEMETRY:-off}"
  if ! command -v headroom >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f "$TELEMETRY_ENV_D" ]] && ! grep -q '^HEADROOM_TELEMETRY=off' "$TELEMETRY_ENV_D"; then
    echo "  warn: HEADROOM_TELEMETRY=off missing from $TELEMETRY_ENV_D" >&2
    return 1
  fi
  # Persistent service: unit may ExecStart a wrapper; accept --no-telemetry OR
  # HEADROOM_TELEMETRY=off in the unit or the script it runs.
  local unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/headroom-default.service"
  if [[ -f "$unit" ]]; then
    local ok=0
    if grep -qE -- '--no-telemetry|HEADROOM_TELEMETRY=off' "$unit"; then
      ok=1
    else
      local exec_line script
      exec_line="$(grep -E '^ExecStart=' "$unit" | head -1 || true)"
      script="${exec_line#ExecStart=}"
      script="${script%% *}"
      if [[ -n "$script" && -f "$script" ]] \
        && grep -qE -- '--no-telemetry|HEADROOM_TELEMETRY=off' "$script"; then
        ok=1
      fi
    fi
    if [[ "$ok" -ne 1 ]]; then
      echo "  warn: headroom-default.service has no telemetry opt-out (re-run headroom-setup / install apply --no-telemetry)" >&2
      return 1
    fi
  fi
  echo "  HEADROOM_TELEMETRY=off (env + service when present)"
  return 0
}

telemetry_ensure_claude_env() {
  local settings="${HOME}/.claude/settings.json"
  local kit="${REPO_ROOT:-}/ai-rules/claude-settings.json"
  [[ -f "$kit" ]] || return 0
  mkdir -p "${HOME}/.claude"
  [[ ! -s "$settings" ]] || command -v jq >/dev/null 2>&1 || return 0
  claude_merge_settings_telemetry "$settings" "$kit"
}

# Gemini CLI: usage stats off + OTel off (privacy.usageStatisticsEnabled / telemetry.enabled).
telemetry_ensure_gemini() {
  local settings="${HOME}/.gemini/settings.json"
  local kit="${REPO_ROOT:-}/ai-rules/gemini-settings.json"
  [[ -d "${HOME}/.gemini" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  gemini_merge_settings_telemetry "$settings" "$kit"
}

# OpenCode: no share, no autoupdate, OTel off (product has no master telemetry kill).
telemetry_ensure_opencode() {
  local settings="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  local tmp
  tmp="$(mktemp)"
  if jq '
    .share = "disabled"
    | .autoupdate = false
    | .experimental = ((.experimental // {}) + {openTelemetry: false})
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Atuin: no sync / update check / secrets_filter (+ secret history_filter canary).
# Never rewrite when cfg is the stow kit (dir-symlink makes config.toml a regular file).
telemetry_ensure_atuin() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml"
  local kit="${REPO_ROOT:-}/stow/atuin/.config/atuin/config.toml"
  [[ -f "$kit" ]] || return 1
  mkdir -p "$(dirname "$cfg")"

  local cfg_real kit_real
  kit_real="$(realpath "$kit" 2>/dev/null || readlink -f "$kit" 2>/dev/null || echo "$kit")"
  if [[ -e "$cfg" ]]; then
    cfg_real="$(realpath "$cfg" 2>/dev/null || readlink -f "$cfg" 2>/dev/null || echo "$cfg")"
  else
    cfg_real=""
  fi

  if [[ -z "$cfg_real" ]]; then
    cp -a "$kit" "$cfg"
  elif [[ "$cfg_real" == "$kit_real" ]]; then
    : # stow-backed — kit is source of truth; verify only
  else
    # Independent file: merge privacy keys + history_filter from kit (python/toml-safe-ish)
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$cfg" "$kit" <<'PY' || return 1
import re, sys
from pathlib import Path

cfg_path, kit_path = Path(sys.argv[1]), Path(sys.argv[2])
text = cfg_path.read_text(encoding="utf-8")
kit = kit_path.read_text(encoding="utf-8")

def set_bool(src: str, key: str, value: str) -> str:
    pat = re.compile(rf"(?m)^{re.escape(key)}\s*=\s*.*$")
    line = f"{key} = {value}"
    if pat.search(src):
        return pat.sub(line, src)
    return line + "\n" + src

for key, val in (("auto_sync", "false"), ("update_check", "false"), ("secrets_filter", "true")):
    text = set_bool(text, key, val)

# Copy history_filter array from kit when secret canary missing
canary = "(?i)--token"
if canary not in text and "history_filter" in kit:
    m = re.search(r"(?ms)^history_filter\s*=\s*\[.*?\]", kit)
    if m:
        block = m.group(0)
        if re.search(r"(?ms)^history_filter\s*=\s*\[.*?\]", text):
            text = re.sub(r"(?ms)^history_filter\s*=\s*\[.*?\]", block, text)
        else:
            text = text.rstrip() + "\n\n" + block + "\n"

cfg_path.write_text(text, encoding="utf-8")
PY
      chmod 600 "$cfg" 2>/dev/null || true
    else
      echo "WARN: python3 missing — cannot merge atuin privacy into $cfg" >&2
      return 1
    fi
  fi

  grep -qE '^auto_sync[[:space:]]*=[[:space:]]*false' "$cfg" \
    && grep -qE '^update_check[[:space:]]*=[[:space:]]*false' "$cfg" \
    && grep -qE '^secrets_filter[[:space:]]*=[[:space:]]*true' "$cfg" \
    && grep -q '(?i)--token' "$cfg"
}

# Drop leftover test MCP server from Kimi (custom-keep); keep real servers.
telemetry_ensure_kimi_mcp() {
  local settings="${KIMI_CODE_HOME:-$HOME/.kimi-code}/mcp.json"
  [[ -f "$settings" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  if ! jq -e '.mcpServers["custom-keep"]' "$settings" >/dev/null 2>&1; then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  if jq 'del(.mcpServers["custom-keep"])' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
  else
    rm -f "$tmp"
    return 1
  fi
}
