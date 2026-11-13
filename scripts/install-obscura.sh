#!/usr/bin/env bash
# install-obscura.sh — Obscura headless browser + MCP for OpenCode / Claude / Cursor
#
# Installs the GitHub release binary (render + stealth by default) into
# ~/.local/bin and merges MCP config for detected agents.
# Docs: https://docs.obscura.sh/
#
# Env:
#   OBSCURA_VERSION   release tag (default: v0.2.6 pinned)
#   OBSCURA_SHA256    expected archive digest (required if version/variant not in map)
#   OBSCURA_VARIANT   archive suffix: "" | stealth | no-render | no-render-stealth
#                     default: stealth (render + stealth)
#   OBSCURA_BIN_DIR   install dir (default: ~/.local/bin)
#   SKIP_MCP=1        skip agent MCP merges
#
# Usage:
#   bash scripts/install-obscura.sh

set -euo pipefail

export PATH="${HOME}/.opencode/bin:${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBSCURA_BIN_DIR="${OBSCURA_BIN_DIR:-$HOME/.local/bin}"
OBSCURA_VARIANT="${OBSCURA_VARIANT:-stealth}"
# Pin by default; bump tag + digests together from GitHub release asset digests.
OBSCURA_VERSION="${OBSCURA_VERSION:-v0.2.6}"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CURSOR_MCP="${HOME}/.cursor/mcp.json"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v curl >/dev/null 2>&1 || die "curl required"
command -v tar >/dev/null 2>&1 || die "tar required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum required"
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

tag="$OBSCURA_VERSION"
[[ "$tag" == v* ]] || tag="v$tag"

# Digests for pinned v0.2.6 linux assets (GitHub release). Override with OBSCURA_SHA256.
obscura_expected_sha() {
  local key="$1"
  case "$key" in
    x86_64-linux) echo eed986e478c5ec5439f531f2d7fb6b0e36a356f1df7a6c44a8e8fd4f2486bd76 ;;
    x86_64-linux-stealth) echo ac8057374ec1b5cabb78ea2d08b2ed890d21d156a42b1ac23357fd049edc08c5 ;;
    x86_64-linux-no-render) echo f1188c1a3b1ef70d56d594beebbb34b693ff89c280fa073820ad019ed555a02c ;;
    x86_64-linux-no-render-stealth) echo 2b36b2d68d31d4430ccddd3c0d8a765a21bf91fb3c642fd9e551f360a98d6c83 ;;
    aarch64-linux) echo e12aff8bbe40326386a471060083e9cec5255b67048996b84f649efef10cac39 ;;
    aarch64-linux-stealth) echo 403b4c8e3bcf777748a870fbb32c9281e997a6c30c5f8377c17305287fc3811f ;;
    aarch64-linux-no-render) echo 5bd8a40e4ff9b35ae985e695f2445181b6d40a115c447f3bd2013fb7b77aeb69 ;;
    aarch64-linux-no-render-stealth) echo 9680c736db45fc7cad067cd20ea04ed032ab4701337fb7029c81bd2a6b9a8c79 ;;
    *) echo "" ;;
  esac
}

asset="obscura-${arch_tag}${suffix}.tar.gz"
url="https://github.com/h4ckf0r0day/obscura/releases/download/${tag}/${asset}"
expected_sha="${OBSCURA_SHA256:-}"
if [[ -z "$expected_sha" ]]; then
  if [[ "$tag" != "v0.2.6" ]]; then
    die "OBSCURA_SHA256 required when OBSCURA_VERSION is not v0.2.6 (got $tag)"
  fi
  expected_sha="$(obscura_expected_sha "${arch_tag}${suffix}")"
  [[ -n "$expected_sha" ]] || die "no pinned SHA for ${arch_tag}${suffix}; set OBSCURA_SHA256"
fi

say "download $url"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/obscura.tgz" "$url"
got="$(sha256sum "$tmp/obscura.tgz" | awk '{print $1}')"
[[ "$got" == "$expected_sha" ]] \
  || die "obscura SHA-256 mismatch (got $got want $expected_sha). Refusing to install."
say "SHA-256 ok"
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
    say "merge Cursor / Kimi / Gemini / Antigravity / Claude MCP"
    python3 - "$obscura_bin" <<'PY'
import json, sys
from pathlib import Path

binpath = sys.argv[1]
home = Path.home()
for path in [
    home / ".claude.json",
    home / ".cursor/mcp.json",
    home / ".kimi-code/mcp.json",
    home / ".gemini/settings.json",
    home / ".gemini/config/mcp_config.json",
]:
    if not (path.is_file() or path.parent.is_dir()):
        continue
    data = {"mcpServers": {}}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text())
            if isinstance(loaded, dict):
                data = loaded
                data.setdefault("mcpServers", {})
        except json.JSONDecodeError as e:
            print(f"skip bad json {path}: {e}")
            continue
    servers = data.setdefault("mcpServers", {})
    if isinstance(servers, dict):
        entry = {"command": binpath, "args": ["mcp"]}
        if path.name == ".claude.json":
            entry["type"] = "stdio"
            entry["env"] = {}
            projects = data.get("projects")
            if isinstance(projects, dict):
                for pdata in projects.values():
                    if isinstance(pdata, dict) and isinstance(pdata.get("mcpServers"), dict):
                        pdata["mcpServers"].pop("obscura", None)
        elif "kimi" in str(path):
            entry["enabled"] = True
        servers["obscura"] = entry
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"wrote {path}")
PY
  fi

  if command -v claude >/dev/null 2>&1; then
    say "claude mcp add -s user obscura (best-effort)"
    claude mcp remove -s local obscura >/dev/null 2>&1 || true
    claude mcp remove -s user obscura >/dev/null 2>&1 || true
    claude mcp add -s user obscura "$obscura_bin" mcp >/dev/null 2>&1 \
      || warn "claude mcp add failed; run: claude mcp add -s user obscura $obscura_bin mcp"
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
