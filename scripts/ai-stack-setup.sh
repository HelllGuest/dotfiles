#!/usr/bin/env bash
# ai-stack-setup.sh — Headroom + Continue + agent plugins (Slice 2).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"

echo "→ Headroom install + MCP..."
bash "$REPO_ROOT/scripts/install-headroom.sh"
bash "$REPO_ROOT/scripts/headroom-setup.sh"

echo "→ Coding agents / Ponytail (best-effort; Ponytail owns /caveman — no separate caveman install)..."
bash "$REPO_ROOT/scripts/install-coding-agents.sh" || echo "WARN: coding-agents skipped"
bash "$REPO_ROOT/scripts/install-ponytail.sh" || echo "WARN: ponytail skipped"
bash "$REPO_ROOT/scripts/install-rea.sh" || echo "WARN: rea skipped"


# Continue.dev FIM → local ollama (P15 only; harmless stub elsewhere)
CONT_DIR="${HOME}/.continue"
mkdir -p "$CONT_DIR"
if [[ -f "$REPO_ROOT/stow/continue/.continue/config.yaml" ]]; then
  if [[ ! -e "$CONT_DIR/config.yaml" ]]; then
    cp -a "$REPO_ROOT/stow/continue/.continue/config.yaml" "$CONT_DIR/config.yaml"
    echo "→ Wrote ~/.continue/config.yaml"
  else
    echo "○ ~/.continue/config.yaml exists — leave in place"
  fi
fi

# OpenCode local ollama models on P15
if is_thinkpad_p15; then
  OC_DIR="${HOME}/.config/opencode"
  mkdir -p "$OC_DIR"
  OC_JSON="$OC_DIR/opencode.json"
  if [[ ! -f $OC_JSON ]]; then
    cat >"$OC_JSON" <<'EOF'
{
  "model": "ollama/qwen3.5:4b",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:11434/v1"
      },
      "models": {
        "qwen2.5-coder:3b": { "name": "qwen2.5-coder:3b" },
        "qwen3.5:4b": { "name": "qwen3.5:4b" }
      }
    }
  }
}
EOF
    echo "→ Wrote $OC_JSON (local ollama)"
  else
    echo "○ $OC_JSON exists — leave in place"
  fi
fi

# Hardened Headroom user unit bind 127.0.0.1:8787 (optional enable)
UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat >"$UNIT_DIR/hr-proxy.service" <<EOF
[Unit]
Description=Headroom proxy (127.0.0.1:8787)
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/headroom proxy --host 127.0.0.1 --port 8787
Restart=on-failure
Environment=HEADROOM_TELEMETRY=off

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload 2>/dev/null || true
echo "○ enable with: systemctl --user enable --now hr-proxy.service"

echo "✓ AI stack setup finished"
echo "  wrappers: hr-claude hr-cursor hr-opencode hr-agy hr-proxy"
