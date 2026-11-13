#!/usr/bin/env bash
# install-coding-agents.sh — OpenCode + Kimi Code CLI + shared MCP (X1 / P15 / fresh Arch)
#
# Idempotent. Installs npm CLIs, writes MCP configs, brand skill links, then
# refreshes Caveman's OpenCode plugin when the caveman installer is available.
#
# Env:
#   OPENCODE_NPM_SPEC     default opencode-ai@1.19.4
#   KIMI_NPM_SPEC         default @moonshot-ai/kimi-code@2.3.0
#   REA_AGENTS_VERSION    default 6.9.0 (MCP npx pin; match labs/lab-re)
#   SKIP_CAVEMAN_OPENCODE=1  skip caveman --only opencode
#   CAVEMAN_TAG           forwarded to install-caveman pins (default v4.1.0)
#
# Usage:
#   bash scripts/install-coding-agents.sh
#   ONLY_CAVEMAN_OPENCODE=1 bash scripts/install-coding-agents.sh   # plugin refresh only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENCODE_NPM_SPEC="${OPENCODE_NPM_SPEC:-opencode-ai@1.19.4}"
KIMI_NPM_SPEC="${KIMI_NPM_SPEC:-@moonshot-ai/kimi-code@2.3.0}"
REA_AGENTS_VERSION="${REA_AGENTS_VERSION:-6.9.0}"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
KIMI_CODE_HOME="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
JADX_JAR="${XDG_DATA_HOME:-$HOME/.local/share}/rea/jadx-headless-mcp-0.7.1-all.jar"
GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra}"
HOPPER_LAUNCHER_PATH="${HOPPER_LAUNCHER_PATH:-/opt/hopper/bin/Hopper}"
HEADROOM_BIN="${HOME}/.local/bin/headroom"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '>> %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

install_caveman_opencode() {
  say "caveman OpenCode plugin"
  mkdir -p "${OPENCODE_DIR}/skills"
  # Installer refuses to replace hub symlinks; clear only known caveman skill names.
  local s target
  for s in caveman ultracave megacave caveman-commit caveman-review caveman-help \
           caveman-stats caveman-compress cavecrew; do
    target="${OPENCODE_DIR}/skills/${s}"
    if [[ -L "$target" ]]; then
      rm -f "$target"
    fi
  done
  local tmp tag sha got caveman_dir
  caveman_dir="${XDG_DATA_HOME:-$HOME/.local/share}/caveman"
  tag="${CAVEMAN_TAG:-v4.1.0}"
  sha="${CAVEMAN_INSTALL_SHA256:-2e39b2a9b4ce47620757abc8a55ad33a23dd65217f8a998135108f92f83c00a1}"
  if [[ -f "$caveman_dir/installer/install.js" ]]; then
    CAVEMAN_REF="$tag" node "$caveman_dir/installer/install.js" --only opencode --non-interactive --force \
      || warn "caveman opencode local install failed"
    return 0
  fi
  tmp="$(mktemp)"
  curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp" \
    "https://raw.githubusercontent.com/JuliusBrussee/caveman/${tag}/install.sh"
  got="$(sha256sum "$tmp" | awk '{print $1}')"
  if [[ "$got" != "$sha" ]]; then
    rm -f "$tmp"
    warn "caveman install.sh SHA mismatch (got $got); skip OpenCode plugin"
    return 0
  fi
  chmod +x "$tmp"
  bash "$tmp" --only opencode --non-interactive --force || warn "caveman opencode install failed"
  rm -f "$tmp"
}

if [[ "${ONLY_CAVEMAN_OPENCODE:-0}" == "1" ]]; then
  command -v curl >/dev/null 2>&1 || die "curl required"
  install_caveman_opencode
  say "install-coding-agents (opencode plugin only) done"
  exit 0
fi

pick_jdk21() {
  local best="" best_ver=0 cand ver
  shopt -s nullglob
  for cand in /usr/lib/jvm/java-*-openjdk; do
    [[ -x "$cand/bin/javac" ]] || continue
    ver="${cand##*/java-}"
    ver="${ver%%-*}"
    [[ "$ver" =~ ^[0-9]+$ ]] || continue
    (( ver >= 21 )) || continue
    if (( ver > best_ver )); then
      best=$cand
      best_ver=$ver
    fi
  done
  shopt -u nullglob
  printf '%s\n' "$best"
}

command -v npm >/dev/null 2>&1 || die "npm required (fnm install 22 first)"
export PATH="${HOME}/.opencode/bin:${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"

# Prefer user-global prefix so install needs no root
if [[ "$(npm config get prefix 2>/dev/null)" == "/usr" ]] || [[ "$(npm config get prefix 2>/dev/null)" == "/usr/local" ]]; then
  mkdir -p "${HOME}/.npm-global"
  npm config set prefix "${HOME}/.npm-global" --location=user
  say "npm prefix → ${HOME}/.npm-global"
fi

say "npm install -g ${OPENCODE_NPM_SPEC}"
npm install -g --allow-scripts=opencode-ai "${OPENCODE_NPM_SPEC}" \
  || npm install -g "${OPENCODE_NPM_SPEC}"

say "npm install -g ${KIMI_NPM_SPEC}"
npm install -g --allow-scripts=@moonshot-ai/kimi-code,node-pty "${KIMI_NPM_SPEC}" \
  || npm install -g "${KIMI_NPM_SPEC}"

command -v opencode >/dev/null 2>&1 || warn "opencode not on PATH yet (add ~/.npm-global/bin)"
command -v kimi >/dev/null 2>&1 || warn "kimi not on PATH yet (add ~/.npm-global/bin)"

JAVA_HOME_JDK="$(pick_jdk21)"
[[ -n "$JAVA_HOME_JDK" ]] || JAVA_HOME_JDK="/usr/lib/jvm/java-21-openjdk"

mkdir -p "${OPENCODE_DIR}/skills" "${KIMI_CODE_HOME}/skills" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills" "${HOME}/.kimi"

# Brand links: -T so an existing real dir is not nested into (ln -sfn trap)
brand_symlink() {
  local target="$1" link="$2"
  if [[ -e "$link" || -L "$link" ]]; then
    if [[ -d "$link" && ! -L "$link" ]]; then
      warn "replace real dir with symlink: $link"
      rm -rf "$link"
    fi
  fi
  ln -sfnT "$target" "$link"
}
brand_symlink "${KIMI_CODE_HOME}/skills" "${HOME}/.kimi/skills"

say "merge OpenCode MCP (headroom + rea@${REA_AGENTS_VERSION})"
python3 - "$OPENCODE_DIR" "$HEADROOM_BIN" "$REA_AGENTS_VERSION" "$JAVA_HOME_JDK" \
  "$GHIDRA_INSTALL_DIR" "$HOPPER_LAUNCHER_PATH" "$JADX_JAR" <<'PY'
import json, sys
from pathlib import Path

opendir, headroom, rea_ver, java, ghidra, hopper, jadx = sys.argv[1:8]
path = Path(opendir) / "opencode.json"
data = {}
if path.is_file():
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise SystemExit(f"bad json {path}: {e}") from e

data.setdefault("$schema", "https://opencode.ai/config.json")
data.setdefault("plugin", [])
data["share"] = "disabled"
data["autoupdate"] = False
exp = data.setdefault("experimental", {})
if not isinstance(exp, dict):
    exp = {}
    data["experimental"] = exp
exp["openTelemetry"] = False
perm = data.setdefault("permission", {})
skill = perm.setdefault("skill", {})
skill.setdefault("*", "allow")

mcp = data.setdefault("mcp", {})
if Path(headroom).is_file():
    mcp["headroom"] = {
        "type": "local",
        "command": [headroom, "mcp", "serve"],
        "enabled": True,
    }
rea_env = {
    "GHIDRA_INSTALL_DIR": ghidra,
    "JAVA_HOME": java,
    "REA_JADX_MCP_JAR": jadx,
}
if Path(hopper).is_file():
    rea_env["HOPPER_LAUNCHER_PATH"] = hopper
mcp["rea"] = {
    "type": "local",
    "command": ["npx", "-y", f"rea-agents@{rea_ver}", "mcp"],
    "enabled": True,
    "environment": rea_env,
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"wrote {path}")
PY

say "merge Kimi MCP ${KIMI_CODE_HOME}/mcp.json (preserve other servers)"
python3 - "$KIMI_CODE_HOME" "$HEADROOM_BIN" "$REA_AGENTS_VERSION" "$JAVA_HOME_JDK" \
  "$GHIDRA_INSTALL_DIR" "$HOPPER_LAUNCHER_PATH" "$JADX_JAR" <<'PY'
import json, sys
from pathlib import Path

home, headroom, rea_ver, java, ghidra, hopper, jadx = sys.argv[1:8]
path = Path(home) / "mcp.json"
data = {"mcpServers": {}}
if path.is_file():
    try:
        loaded = json.loads(path.read_text())
        if isinstance(loaded, dict):
            servers = loaded.get("mcpServers")
            if isinstance(servers, dict):
                data["mcpServers"] = dict(servers)
            else:
                data = loaded
                data.setdefault("mcpServers", {})
    except json.JSONDecodeError as e:
        raise SystemExit(f"bad json {path}: {e}") from e

servers = data.setdefault("mcpServers", {})
if Path(headroom).is_file():
    servers["headroom"] = {
        "command": headroom,
        "args": ["mcp", "serve"],
        "enabled": True,
    }
env = {
    "GHIDRA_INSTALL_DIR": ghidra,
    "JAVA_HOME": java,
    "REA_JADX_MCP_JAR": jadx,
}
if Path(hopper).is_file():
    env["HOPPER_LAUNCHER_PATH"] = hopper
servers["rea"] = {
    "command": "npx",
    "args": ["-y", f"rea-agents@{rea_ver}", "mcp"],
    "env": env,
    "enabled": True,
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"merged {path} ({len(servers)} server(s))")
PY
brand_symlink "${KIMI_CODE_HOME}/mcp.json" "${HOME}/.kimi/mcp.json"

# Seed AGENTS.md once (do not clobber user edits)
if [[ ! -f "${KIMI_CODE_HOME}/AGENTS.md" ]]; then
  if [[ -f "${HOME}/dev/ai-rules/AGENTS.md" ]]; then
    cp -a "${HOME}/dev/ai-rules/AGENTS.md" "${KIMI_CODE_HOME}/AGENTS.md"
  elif [[ -f "${REPO_ROOT}/AGENTS.md" ]]; then
    cp -a "${REPO_ROOT}/AGENTS.md" "${KIMI_CODE_HOME}/AGENTS.md"
  fi
fi

if [[ "${SKIP_CAVEMAN_OPENCODE:-0}" != "1" ]]; then
  install_caveman_opencode
fi

say "install-coding-agents done"
echo "  opencode: $(command -v opencode || echo missing) $(opencode --version 2>/dev/null || true)"
echo "  kimi:     $(command -v kimi || echo missing) $(kimi --version 2>/dev/null || true)"
echo "  MCP:      ${OPENCODE_DIR}/opencode.json  ${KIMI_CODE_HOME}/mcp.json"
echo "  next:     kimi  # login once; then new opencode/kimi sessions"
