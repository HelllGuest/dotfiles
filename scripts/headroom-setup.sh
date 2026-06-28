#!/usr/bin/env bash
# headroom-setup.sh — install Headroom + MCP for Claude; print Cursor proxy steps

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${HEADROOM_PORT:-8787}"

bash "$REPO_ROOT/scripts/install-headroom.sh"

echo ""
echo "Registering Headroom MCP server for Claude Code..."
if command -v claude >/dev/null 2>&1; then
    headroom mcp install --agent claude --proxy-url "http://127.0.0.1:${PORT}" \
        || headroom mcp install --agent claude --proxy-url "http://127.0.0.1:${PORT}" --force \
        || true
else
    echo "  (claude not in PATH — run 'headroom mcp install --agent claude' after installing Claude Code)"
fi

cat <<EOF

Headroom is ready.

Claude Code (one command — proxy + launch):
  hr-claude
  # or: headroom wrap claude

Cursor (proxy stays in foreground; open Cursor in another terminal):
  hr-cursor
  # then in Cursor: Settings → Models → OpenAI API Key → Override OpenAI Base URL
  # paste the Base URL printed by hr-cursor (project-scoped, e.g. http://127.0.0.1:${PORT}/p/<project>/v1)

Proxy only (any OpenAI/Anthropic client):
  hr-proxy
  # ANTHROPIC_BASE_URL=http://127.0.0.1:${PORT} claude

MCP tools (compress / retrieve / stats):
  headroom mcp install --agent claude

Stop proxy: Ctrl+C in the hr-cursor / hr-proxy terminal.

EOF
