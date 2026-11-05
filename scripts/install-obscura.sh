#!/usr/bin/env bash
# install-obscura.sh — Obscura headless browser + MCP for OpenCode / Claude / Cursor
#
# Installs the GitHub release binary (render + stealth by default) into
# ~/.local/bin and merges MCP config for detected agents.
# Docs: https://docs.obscura.sh/
#
# Env:
#   OBSCURA_VERSION   release tag (default: latest)
#   OBSCURA_VARIANT   archive suffix: "" | stealth | no-render | no-render-stealth
#                     default: stealth (render + stealth)
#   OBSCURA_BIN_DIR   install dir (default: ~/.local/bin)
#   SKIP_MCP=1        skip agent MCP merges
#
# Usage:
#   bash scripts/install-obscura.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBSCURA_BIN_DIR="${OBSCURA_BIN_DIR:-$HOME/.local/bin}"
OBSCURA_VARIANT="${OBSCURA_VARIANT:-stealth}"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CURSOR_MCP="${HOME}/.cursor/mcp.json"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v curl >/dev/null 2>&1 || die "curl required"
command -v tar >/dev/null 2>&1 || die "tar required"
command -v python3 >/dev/null 2>&1 || die "python3 required"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch_tag=x86_64-linux ;;
  aarch64|arm64) arch_tag=aarch64-linux ;;
  *) die "unsupported arch: $arch" ;;
esac

suffix=""
case "$OBSCURA_VARIANT" in
  ""|render) suffix="" ;;
  stealth) suffix="-stealth" ;;
  no-render) suffix="-no-render" ;;
  no-render-stealth) suffix="-no-render-stealth" ;;
  *) die "OBSCURA_VARIANT must be empty|stealth|no-render|no-render-stealth (got $OBSCURA_VARIANT)" ;;
esac

if [[ -n "${OBSCURA_VERSION:-}" ]]; then
  tag="$OBSCURA_VERSION"
  [[ "$tag" == v* ]] || tag="v$tag"
else
  tag="$(curl -fsSL https://api.github.com/repos/h4ckf0r0day/obscura/releases/latest \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')"
fi

asset="obscura-${arch_tag}${suffix}.tar.gz"
url="https://github.com/h4ckf0r0day/obscura/releases/download/${tag}/${asset}"
say "download $url"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/obscura.tgz" "$url"
tar -xzf "$tmp/obscura.tgz" -C "$tmp"
[[ -x "$tmp/obscura" ]] || die "archive missing obscura binary"
mkdir -p "$OBSCURA_BIN_DIR"
install -m 755 "$tmp/obscura" "$OBSCURA_BIN_DIR/obscura"
[[ -f "$tmp/obscura-worker" ]] && install -m 755 "$tmp/obscura-worker" "$OBSCURA_BIN_DIR/obscura-worker"
ok_ver="$("$OBSCURA_BIN_DIR/obscura" --version 2>&1 || true)"
say "installed $ok_ver → $OBSCURA_BIN_DIR/obscura"

if [[ "${SKIP_MCP:-0}" != "1" ]]; then
  obscura_bin="$OBSCURA_BIN_DIR/obscura"
  say "merge OpenCode MCP ($OPENCODE_DIR/opencode.json)"
  python3 - "$OPENCODE_DIR" "$obscura_bin" <<'PY'
import json, sys
from pathlib import Path

opendir, binpath = sys.argv[1:3]
path = Path(opendir) / "opencode.json"
data = {}
if path.is_file():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise SystemExit(f"bad json {path}: {e}") from e
data.setdefault("$schema", "https://opencode.ai/config.json")
mcp = data.setdefault("mcp", {})
mcp["obscura"] = {
    "type": "local",
    "command": [binpath, "mcp"],
    "enabled": True,
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"wrote {path}")
PY

  if [[ -f "$CURSOR_MCP" ]] || [[ -d "$(dirname "$CURSOR_MCP")" ]]; then
    say "merge Cursor MCP ($CURSOR_MCP)"
    python3 - "$CURSOR_MCP" "$obscura_bin" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
binpath = sys.argv[2]
data = {"mcpServers": {}}
if path.is_file():
    try:
        loaded = json.loads(path.read_text())
        if isinstance(loaded, dict):
            if isinstance(loaded.get("mcpServers"), dict):
                data["mcpServers"] = dict(loaded["mcpServers"])
            else:
                data = loaded
                data.setdefault("mcpServers", {})
    except json.JSONDecodeError as e:
        raise SystemExit(f"bad json {path}: {e}") from e
servers = data.setdefault("mcpServers", {})
servers["obscura"] = {"command": binpath, "args": ["mcp"]}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"wrote {path}")
PY
  fi

  if command -v claude >/dev/null 2>&1; then
    say "claude mcp add obscura (best-effort)"
    claude mcp remove obscura >/dev/null 2>&1 || true
    claude mcp add obscura "$obscura_bin" mcp >/dev/null 2>&1 \
      || warn "claude mcp add failed; run: claude mcp add obscura $obscura_bin mcp"
  fi
fi

# Host skill → agents hub (+ cursor) via sync when available
skill_src="$REPO_ROOT/skills/obscura-host"
if [[ -f "$skill_src/SKILL.md" ]]; then
  mkdir -p "${HOME}/.agents/skills"
  rm -rf "${HOME}/.agents/skills/obscura-host"
  cp -a "$skill_src" "${HOME}/.agents/skills/obscura-host"
  say "hub skill obscura-host"
  if [[ -f "$REPO_ROOT/scripts/sync-agent-skills.sh" ]]; then
    bash "$REPO_ROOT/scripts/sync-agent-skills.sh" >/dev/null || true
  fi
fi

say "smoke"
"$OBSCURA_BIN_DIR/obscura" fetch https://example.com --eval 'document.title' | head -5
say "install-obscura done"
echo "  CLI:  obscura fetch URL | obscura serve | obscura mcp"
echo "  MCP:  restart OpenCode / Cursor / Claude to load obscura tools"
echo "  docs: https://docs.obscura.sh/"
