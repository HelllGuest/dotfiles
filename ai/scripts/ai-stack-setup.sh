#!/usr/bin/env bash
# ai-stack-setup.sh — Headroom + Continue + agent plugins (Slice 2).
#
# Full run (configure.sh SETUP_AI): Headroom + coding-agents + Ponytail + extras.
# AI_STACK_EXTRAS_ONLY=1 (install.sh): only Continue / OpenCode↔ollama / hr-proxy
#   — cores already installed earlier in install.sh (incl. Caveman).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../provision/lib/dmi.sh
source "$REPO_ROOT/provision/lib/dmi.sh"

if [[ ${AI_STACK_EXTRAS_ONLY:-0} != 1 ]]; then
  echo "→ Headroom install + MCP..."
  bash "$REPO_ROOT/ai/scripts/headroom-setup.sh"

  # Caveman (install.sh) and Ponytail are complementary: separate Claude plugins,
  # AGY plugin dirs, hub skills, and Cursor hooks (ponytail merge leaves caveman).
  # SETUP_AI runs Ponytail only; full ./install.sh also runs install-caveman.sh.
  echo "→ Coding agents / Ponytail (Caveman stays on full install.sh path)..."
  bash "$REPO_ROOT/ai/scripts/install-coding-agents.sh" || echo "WARN: coding-agents skipped"
  bash "$REPO_ROOT/ai/scripts/install-ponytail.sh" || echo "WARN: ponytail skipped"
  # REA + Ghidra/JADX/JDK live in lab-re (not bare metal). Rebuild: podman build -t localhost/lab-re labs/lab-re
  echo "○ REA backends: use lab-re (JDK21/Ghidra/jadx/rizin inside image) — host install-rea.sh skipped"
else
  echo "→ AI stack extras only (Continue / OpenCode↔ollama / hr-proxy)..."
fi

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

# OpenCode local ollama models on P15 (merge so prior MCP/plugin config is kept)
OLLAMA_ADDR="${OLLAMA_HOST:-127.0.0.1:11434}"
HR_PORT="${HEADROOM_PORT:-8787}"
if is_thinkpad_p15; then
  OC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  mkdir -p "$OC_DIR"
  OC_JSON="$OC_DIR/opencode.json"
  python3 - "$OC_JSON" "$OLLAMA_ADDR" <<'PY'
import json, sys
from pathlib import Path

path, ollama_addr = Path(sys.argv[1]), sys.argv[2]
data = {}
if path.is_file():
    try:
        loaded = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise SystemExit(f"bad json {path}: {e}") from e
    if isinstance(loaded, dict):
        data = loaded

data.setdefault("model", "ollama/qwen3.5:4b")
provider = data.setdefault("provider", {})
if not isinstance(provider, dict):
    provider = {}
    data["provider"] = provider
provider.setdefault("ollama", {
    "npm": "@ai-sdk/openai-compatible",
    "options": {"baseURL": f"http://{ollama_addr}/v1"},
    "models": {
        "qwen2.5-coder:3b": {"name": "qwen2.5-coder:3b"},
        "qwen3.5:4b": {"name": "qwen3.5:4b"},
    },
})
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"→ Merged local ollama provider into {path}")
PY
fi

# Hardened Headroom user unit bind 127.0.0.1:$HR_PORT (optional enable)
UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat >"$UNIT_DIR/hr-proxy.service" <<EOF
[Unit]
Description=Headroom proxy (127.0.0.1:${HR_PORT})
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/headroom proxy --host 127.0.0.1 --port ${HR_PORT}
Restart=on-failure
Environment=HEADROOM_TELEMETRY=off

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload 2>/dev/null || true
echo "○ enable with: systemctl --user enable --now hr-proxy.service"

echo "✓ AI stack setup finished"
echo "  wrappers: hr-claude hr-cursor hr-opencode hr-agy hr-proxy"
