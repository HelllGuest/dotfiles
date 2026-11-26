#!/usr/bin/env bash
# install-rea.sh — REA (rea-agents) CLI + MCP for detected agents
#
# Prefer lab-re for Ghidra/JADX/JDK backends (bare-metal host stays minimal):
#   lab-re --check
#   lab-re   # then: rea / ghidraRun / jadx / rizin inside the container
#
# This host installer still wires MCP on the workstation when JDK>=21 + tools
# already exist; Slice 2 AI stack does NOT call it by default.
#
# * npm global rea-agents
# * jadx-headless-mcp 0.8.0 JAR (SHA-256 pinned; REA does not download engines itself)
# * rea setup --all-detected --yes (MCP + reverse-engineer-anything skill)
# * environment.d for JADX / Ghidra / Hopper paths (no JAVA_HOME — Android keeps 17)
# * MCP env: JAVA_HOME (JDK>=21), GHIDRA, JADX, HOPPER when present
#
# Optional: INSTALL_HOPPER=1 also runs setup --install-hopper (needs sudo/pkexec).
# Safe to re-run.
#
# Usage:
#   bash ai/scripts/install-rea.sh
#   INSTALL_HOPPER=1 bash ai/scripts/install-rea.sh


set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/jdk.sh
source "$REPO_ROOT/ai/lib/jdk.sh"

JADX_VER="0.8.0"
JADX_SHA256="4b9a01c23845c123c217840182d2b5f2c26a7ca20dec3d08810b310fc80a2372"
JADX_URL="https://github.com/1013503897/jadx-headless-mcp/releases/download/v${JADX_VER}/jadx-headless-mcp-${JADX_VER}-all.jar"
# Keep in sync with ai/scripts/install-coding-agents.sh (REA_AGENTS_VERSION)
REA_AGENTS_VERSION="${REA_AGENTS_VERSION:-6.10.1}"
REA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rea"
JADX_JAR="${REA_DIR}/jadx-headless-mcp-${JADX_VER}-all.jar"
GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra}"
HOPPER_LAUNCHER_PATH="${HOPPER_LAUNCHER_PATH:-/opt/hopper/bin/Hopper}"
ENV_D="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/rea.conf"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

command -v npm >/dev/null 2>&1 || die "npm not found (install fnm/node first)"
command -v curl >/dev/null 2>&1 || die "curl not found"

JAVA_HOME_JDK="$(pick_jdk21)" || die "need full JDK >= 21 under /usr/lib/jvm (for Ghidra/REA)"
say "JDK for REA/Ghidra: $JAVA_HOME_JDK"

say "npm install -g rea-agents@${REA_AGENTS_VERSION}"
npm install -g "rea-agents@${REA_AGENTS_VERSION}"

mkdir -p "$REA_DIR"
if [[ -f "$JADX_JAR" ]]; then
  echo "$JADX_SHA256  $JADX_JAR" | sha256sum -c -
else
  say "download jadx-headless-mcp ${JADX_VER}"
  curl -fL --proto '=https' --tlsv1.2 \
    -A "Mozilla/5.0 (compatible; dotfiles-install-rea/1.0)" \
    -o "$JADX_JAR" "$JADX_URL"
  echo "$JADX_SHA256  $JADX_JAR" | sha256sum -c -
fi

mkdir -p "$(dirname "$ENV_D")"
cat > "$ENV_D" <<EOF
REA_JADX_MCP_JAR=${JADX_JAR}
GHIDRA_INSTALL_DIR=${GHIDRA_INSTALL_DIR}
EOF
if [[ -x "$HOPPER_LAUNCHER_PATH" ]]; then
  echo "HOPPER_LAUNCHER_PATH=${HOPPER_LAUNCHER_PATH}" >> "$ENV_D"
fi
say "wrote $ENV_D (no JAVA_HOME — MCP sets JDK 21+; Android shell may keep 17)"

export JAVA_HOME="$JAVA_HOME_JDK"
export GHIDRA_INSTALL_DIR
export REA_JADX_MCP_JAR="$JADX_JAR"
[[ -x "$HOPPER_LAUNCHER_PATH" ]] && export HOPPER_LAUNCHER_PATH

SETUP=(npx -y "rea-agents@${REA_AGENTS_VERSION}" setup --all-detected --yes)
if [[ "${INSTALL_HOPPER:-0}" == "1" ]]; then
  SETUP+=(--install-hopper)
  say "INSTALL_HOPPER=1 — setup will try Hopper package install"
fi
say "rea setup --all-detected"
"${SETUP[@]}"

# Ensure VSCodium gets REA (setup targets VS Code path only)
VSCODIUM_MCP="${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/mcp.json"
if [[ -f "$VSCODIUM_MCP" ]] || [[ -d "$(dirname "$VSCODIUM_MCP")" ]]; then
  python3 - "$VSCODIUM_MCP" "$JAVA_HOME_JDK" "$GHIDRA_INSTALL_DIR" "$JADX_JAR" \
    "$HOPPER_LAUNCHER_PATH" "$REA_AGENTS_VERSION" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
java, ghidra, jadx, hopper, rea_ver = sys.argv[2:7]
env = {
    "JAVA_HOME": java,
    "GHIDRA_INSTALL_DIR": ghidra,
    "REA_JADX_MCP_JAR": jadx,
}
if Path(hopper).is_file():
    env["HOPPER_LAUNCHER_PATH"] = hopper
path.parent.mkdir(parents=True, exist_ok=True)
data = json.loads(path.read_text()) if path.is_file() else {"mcpServers": {}}
servers = data.setdefault("mcpServers", {})
rea = servers.setdefault("rea", {
    "command": "npx",
    "args": ["-y", f"rea-agents@{rea_ver}", "mcp"],
})
rea["args"] = ["-y", f"rea-agents@{rea_ver}", "mcp"]
rea_env = rea.setdefault("env", {})
rea_env.update(env)
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"VSCodium MCP rea env updated: {path}")
PY
fi

# Patch common MCP configs so ANDROID JAVA_HOME=17 cannot break Ghidra
python3 - "$JAVA_HOME_JDK" "$GHIDRA_INSTALL_DIR" "$JADX_JAR" "$HOPPER_LAUNCHER_PATH" <<'PY'
import json, re
from pathlib import Path
import sys

java, ghidra, jadx, hopper = sys.argv[1:5]
ENV = {
    "JAVA_HOME": java,
    "GHIDRA_INSTALL_DIR": ghidra,
    "REA_JADX_MCP_JAR": jadx,
}
if Path(hopper).is_file():
    ENV["HOPPER_LAUNCHER_PATH"] = hopper

home = Path.home()
json_paths = [
    home / ".cursor/mcp.json",
    home / ".config/Code/User/mcp.json",
    home / ".config/VSCodium/User/mcp.json",
    home / ".codeium/windsurf/mcp_config.json",
    home / ".config/devin/mcp_config.json",
    home / ".commandcode/mcp.json",
    home / ".pi/agent/mcp.json",
    home / ".factory/mcp.json",
    home / ".gemini/config/mcp_config.json",
    home / ".gemini/settings.json",
    home / ".qwen/settings.json",
    home / ".qoder/settings.json",
    home / ".claude.json",
    home / ".config/opencode/opencode.json",
    home / ".kimi-code/mcp.json",
    home / ".kimi/mcp.json",
]

def patch_entry(entry: dict) -> bool:
    if not isinstance(entry, dict):
        return False
    args = entry.get("args") or []
    cmd = entry.get("command")
    # OpenCode: command is a list
    if isinstance(cmd, list):
        if not any("rea-agents" in str(a) for a in cmd):
            return False
        env = entry.setdefault("environment", entry.setdefault("env", {}))
    else:
        if cmd != "npx" and not (isinstance(cmd, str) and "npx" in cmd):
            # still allow if args mention rea-agents
            if not any("rea-agents" in str(a) for a in args):
                return False
        env = entry.setdefault("env", {})
    changed = False
    for k, v in ENV.items():
        if env.get(k) != v:
            env[k] = v
            changed = True
    return changed

def walk(obj) -> bool:
    ch = False
    if isinstance(obj, dict):
        if "rea" in obj and isinstance(obj["rea"], dict) and patch_entry(obj["rea"]):
            ch = True
        for v in obj.values():
            if walk(v):
                ch = True
    elif isinstance(obj, list):
        for v in obj:
            if walk(v):
                ch = True
    return ch

for path in json_paths:
    if not path.is_file():
        continue
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        print(f"skip bad json {path}")
        continue
    if walk(data):
        path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"patched {path}")

lines = [
    "[mcp_servers.rea.env]",
    f'JAVA_HOME = "{ENV["JAVA_HOME"]}"',
    f'GHIDRA_INSTALL_DIR = "{ENV["GHIDRA_INSTALL_DIR"]}"',
    f'REA_JADX_MCP_JAR = "{ENV["REA_JADX_MCP_JAR"]}"',
]
if "HOPPER_LAUNCHER_PATH" in ENV:
    lines.append(f'HOPPER_LAUNCHER_PATH = "{ENV["HOPPER_LAUNCHER_PATH"]}"')
env_block = "\n".join(lines) + "\n"

for path in [home / ".codex/config.toml", home / ".grok/config.toml"]:
    if not path.is_file():
        continue
    text = path.read_text()
    if "[mcp_servers.rea]" not in text:
        continue
    text2, n = re.subn(
        r"\[mcp_servers\.rea\.env\][\s\S]*?(?=\n\[|\Z)",
        env_block,
        text,
        count=1,
    )
    if n == 0:
        # insert env table after the rea server block's first keys
        text2 = re.sub(
            r"(\[mcp_servers\.rea\]\n)",
            r"\1" + env_block,
            text,
            count=1,
        )
    if text2 != text:
        path.write_text(text2)
        print(f"patched {path}")
PY

say "rea doctor"
if command -v rea >/dev/null 2>&1; then
  doc_env=(
    "JAVA_HOME=$JAVA_HOME_JDK"
    "REA_JADX_MCP_JAR=$JADX_JAR"
    "GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR"
  )
  [[ -x "$HOPPER_LAUNCHER_PATH" ]] && doc_env+=("HOPPER_LAUNCHER_PATH=$HOPPER_LAUNCHER_PATH")
  env "${doc_env[@]}" rea doctor --format json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("healthy", d.get("healthy"), "env", d.get("environment_healthy"))
for c in d.get("checks",[]):
  if not c.get("ok"):
    print("FAIL", c.get("name"), c.get("classification"), (c.get("detail") or "")[:80])
' || warn "rea doctor failed"
else
  warn "rea not on PATH yet — open a new shell or ensure npm global bin is on PATH"
fi

say "install-rea done — restart agents to load MCP"
echo "  skill: ~/.agents/skills/reverse-engineer-anything"
echo "  then:  bash ai/scripts/sync-agent-skills.sh   # mirror REA skill to Cursor/Claude"
