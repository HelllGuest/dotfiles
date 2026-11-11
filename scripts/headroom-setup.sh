#!/usr/bin/env bash
# headroom-setup.sh — install Headroom + MCP for Claude; print Cursor proxy steps

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${HEADROOM_PORT:-8787}"
export PATH="${HOME}/.opencode/bin:${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

bash "$REPO_ROOT/scripts/install-headroom.sh"

echo ""
echo "Registering Headroom MCP server and proxy env for detected agents..."
headroom mcp install --force --proxy-url "http://127.0.0.1:${PORT}" || true

HEADROOM_BIN="$(command -v headroom || echo "${HOME}/.local/bin/headroom")"
python3 - "$HEADROOM_BIN" "$PORT" <<'PY'
import json, sys
from pathlib import Path

headroom_bin, port = sys.argv[1], sys.argv[2]
home = Path.home()

# 1. Merge ANTHROPIC_BASE_URL + ENABLE_TOOL_SEARCH into ~/.claude/settings.json
claude_settings = home / ".claude/settings.json"
if claude_settings.parent.is_dir():
    data = {}
    if claude_settings.is_file():
        try:
            data = json.loads(claude_settings.read_text())
        except json.JSONDecodeError:
            data = None
    if isinstance(data, dict):
        env = data.setdefault("env", {})
        if isinstance(env, dict):
            env["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{port}"
            env["ENABLE_TOOL_SEARCH"] = "true"
            claude_settings.write_text(json.dumps(data, indent=2) + "\n")
            print(f"updated {claude_settings} env (ANTHROPIC_BASE_URL)")

# 2. Ensure Headroom MCP server in Cursor, Gemini CLI, Antigravity, and Kimi Code
for mcp_path in [
    home / ".cursor/mcp.json",
    home / ".gemini/settings.json",
    home / ".gemini/config/mcp_config.json",
    home / ".kimi-code/mcp.json",
]:
    if not (mcp_path.is_file() or mcp_path.parent.is_dir()):
        continue
    data = {}
    if mcp_path.is_file():
        try:
            data = json.loads(mcp_path.read_text())
        except json.JSONDecodeError:
            continue
    if not isinstance(data, dict):
        continue
    servers = data.setdefault("mcpServers", {})
    if isinstance(servers, dict):
        entry = {
            "command": headroom_bin,
            "args": ["mcp", "serve"],
        }
        if mcp_path.name == "mcp.json" and "kimi" in str(mcp_path):
            entry["enabled"] = True
        servers["headroom"] = entry
        mcp_path.parent.mkdir(parents=True, exist_ok=True)
        mcp_path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"merged headroom MCP into {mcp_path}")
PY

cat <<EOF

Headroom is ready.

Always-on proxy (recommended):
  headroom install apply --preset persistent-service --runtime python --scope user \\
    --providers auto --profile default --port ${PORT} --backend anthropic --mode token --no-telemetry
  systemctl --user status headroom-default.service
  headroom doctor

Claude Code (one command — proxy + launch):
  hr-claude
  # or: headroom wrap claude

Cursor (paste Base URL into Settings → Models; IDE ignores shell env):
  hr-cursor
  # Override OpenAI Base URL with the URL printed by hr-cursor

One-shot proxy only:
  hr-proxy
  # or: ANTHROPIC_BASE_URL=http://127.0.0.1:${PORT} claude

MCP (Claude / Codex / OpenCode when detected):
  headroom mcp install --force

If doctor warns Base URL env is unset in this shell:
  source ~/.zshrc   # or open a new terminal

Note: Headroom 0.34+ no longer bundles RTK. Keep RTK separately
(rtk-ai/rtk) under e.g. ~/.local/share/rtk (not ~/.headroom/bin) so
headroom wrap/init does not purge it. Telemetry stays off.

EOF
