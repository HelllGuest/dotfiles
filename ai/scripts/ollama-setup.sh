#!/usr/bin/env bash
# ollama-setup.sh — P15 local LLM (Quadro T1000 4GB). Bind localhost only.
# Models: qwen2.5-coder:3b (FIM) + qwen3.5:4b (agent/triage).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../provision/lib/dmi.sh
source "$REPO_ROOT/provision/lib/dmi.sh"

if ! is_thinkpad_p15; then
  echo "ollama-setup: skip (not ThinkPad P15 / 20SU)"
  exit 0
fi

echo "→ Installing ollama (CUDA build preferred)..."
if ! pacman -Q ollama-cuda >/dev/null 2>&1 && ! pacman -Q ollama >/dev/null 2>&1; then
  if ! sudo pacman -S --needed --noconfirm ollama-cuda 2>/dev/null; then
    sudo pacman -S --needed --noconfirm ollama
  fi
fi

echo "→ Writing hardened ollama systemd override (127.0.0.1:11434)..."
sudo install -d -m 0755 /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_FLASH_ATTENTION=1
Environment=OLLAMA_KV_CACHE_TYPE=q8_0
Environment=OLLAMA_KEEP_ALIVE=5m
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ollama.service

if command -v ollama >/dev/null 2>&1; then
  echo "→ Pulling models (fits 4GB VRAM with q8_0 KV)..."
  ollama pull qwen2.5-coder:3b || echo "WARN: qwen2.5-coder:3b pull failed — retry later"
  ollama pull qwen3.5:4b || echo "WARN: qwen3.5:4b pull failed — retry later"
fi

echo "✓ ollama listening on 127.0.0.1:11434 (Optimus can D3cold when idle)"
