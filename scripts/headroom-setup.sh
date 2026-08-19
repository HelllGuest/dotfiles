#!/usr/bin/env bash
# headroom-setup.sh — install Headroom + MCP for Claude; print Cursor proxy steps

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${HEADROOM_PORT:-8787}"

bash "$REPO_ROOT/scripts/install-headroom.sh"

echo ""
echo "Registering Headroom MCP server for Claude Code..."
if command -v claude >/dev/null 2>&1; then
    headroom mcp install --force --proxy-url "http://127.0.0.1:${PORT}" \
        || true
else
    echo "  (claude not in PATH — run 'headroom mcp install --agent claude' after installing Claude Code)"
fi

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
