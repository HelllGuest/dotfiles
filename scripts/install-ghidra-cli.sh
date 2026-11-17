#!/usr/bin/env bash
# install-ghidra-cli.sh — akiselev/ghidra-cli (Rust) against system Ghidra
# https://github.com/akiselev/ghidra-cli

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHIDRA_CLI_GIT="${GHIDRA_CLI_GIT:-https://github.com/akiselev/ghidra-cli}"
GHIDRA_CLI_TAG="${GHIDRA_CLI_TAG:-v0.2.2}"
# Commit the tag must resolve to (a moved tag is refused).
GHIDRA_CLI_COMMIT="${GHIDRA_CLI_COMMIT:-10019ba1f3b54c9edcca8ec644a30e16fb7b7c79}"
# Local patch level: bump when patch_ghidra_cli changes, so an older build is replaced.
GHIDRA_CLI_PATCH=1
GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra}"
CLI_BIN="${HOME}/.cargo/bin/ghidra"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghidra-cli"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
AGENTS_SKILLS="${HOME}/.agents/skills"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }

if ! command -v cargo >/dev/null 2>&1; then
    die "cargo not found; install rust (pacman: rust)"
fi
if ! cargo --version >/dev/null 2>&1; then
    if command -v rustup >/dev/null 2>&1; then
        echo "No default Rust toolchain configured; running 'rustup default stable'..."
        rustup default stable
    else
        die "cargo is not functional; install rust toolchain"
    fi
fi

if [[ ! -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]]; then
    die "Ghidra not found at $GHIDRA_INSTALL_DIR (pacman: ghidra)"
fi

# Newest full JDK >= 21 (javac present). Avoid Android's JAVA_HOME=17.
pick_jdk() {
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
    [[ -n "$best" ]] || die "no JDK >= 21 with javac under /usr/lib/jvm"
    printf '%s\n' "$best"
}

JAVA_HOME_JDK="$(pick_jdk)"

export PATH="${HOME}/.cargo/bin:${PATH}"

# ghidra-cli v0.2.2 locks openssl-sys 0.9.111 (OpenSSL 1.x/3 only; resolving
# without --locked still lands on it), but Arch ships OpenSSL 4. Build against
# the openssl-3 compat package instead; its runtime libssl.so.3/libcrypto.so.3
# live in /usr/lib, so the binary needs no rpath.
OPENSSL3_INCLUDE_DIR="${OPENSSL3_INCLUDE_DIR:-/usr/include/openssl-3}"
OPENSSL3_LIB_DIR="${OPENSSL3_LIB_DIR:-/usr/lib/openssl-3}"
if [[ -d "$OPENSSL3_INCLUDE_DIR" && -d "$OPENSSL3_LIB_DIR" ]]; then
    export OPENSSL_INCLUDE_DIR="$OPENSSL3_INCLUDE_DIR" OPENSSL_LIB_DIR="$OPENSSL3_LIB_DIR"
else
    sys_ssl="$(pkg-config --modversion openssl 2>/dev/null || echo 0)"
    if [[ ${sys_ssl%%.*} =~ ^[0-9]+$ ]] && (( ${sys_ssl%%.*} >= 4 )); then
        die "OpenSSL ${sys_ssl} is too new for ghidra-cli's openssl-sys; install the compat package: sudo pacman -S openssl-3"
    fi
fi

# patch_ghidra_cli SRC: source fixes for the system Ghidra. Each must apply
# exactly once, otherwise the build stops (upstream changed: re-check).
#  1. Ghidra 12.2 removed DataTypeManager.remove(DataType, TaskMonitor), which
#     only called remove(DataType); the bridge script (compiled by Ghidra at
#     run time, embedded in the binary) failed to compile, so every command
#     died with "GhidraCliBridge not found". remove(DataType) exists in 12.1+.
patch_ghidra_cli() {
    local bridge="$1/src/ghidra/scripts/GhidraCliBridge.java"
    [[ -f $bridge ]] || die "ghidra-cli layout changed: $bridge missing"
    local n
    n="$(grep -c 'dtm\.remove(dataType, monitor)' "$bridge" || true)"
    [[ $n == 1 ]] || die "ghidra-cli patch 1 expected 1 match, found ${n:-0} — re-check against Ghidra's API"
    sed -i 's/dtm\.remove(dataType, monitor)/dtm.remove(dataType)/' "$bridge"
}

# Build stamp: version alone cannot tell an unpatched v0.2.2 from ours.
STAMP="${HOME}/.cargo/.ghidra-cli-dotfiles-build"
WANT_STAMP="${GHIDRA_CLI_TAG} ${GHIDRA_CLI_COMMIT} patch${GHIDRA_CLI_PATCH}"

echo "Installing ghidra-cli ${GHIDRA_CLI_TAG} (patched for system Ghidra) via cargo..."
# Only probe the cargo binary — never Arch /usr/bin/ghidra (GUI launcher).
if [[ -x "$CLI_BIN" && "$(cat "$STAMP" 2>/dev/null)" == "$WANT_STAMP" ]]; then
    echo "ghidra-cli ${GHIDRA_CLI_TAG} (patch${GHIDRA_CLI_PATCH}) already at $CLI_BIN; skipping cargo build"
else
    SRC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghidra-cli-src.XXXXXX")"
    trap 'rm -rf -- "$SRC_DIR"' EXIT   # build only; the smoke step sets its own trap
    git clone --quiet --depth 1 --branch "$GHIDRA_CLI_TAG" "$GHIDRA_CLI_GIT" "$SRC_DIR/src"
    got="$(git -C "$SRC_DIR/src" rev-parse HEAD)"
    [[ $got == "$GHIDRA_CLI_COMMIT" ]] || die "tag $GHIDRA_CLI_TAG is $got, expected $GHIDRA_CLI_COMMIT — refusing a moved tag"
    patch_ghidra_cli "$SRC_DIR/src"
    cargo install --path "$SRC_DIR/src" --locked --force \
        || cargo install --path "$SRC_DIR/src" --force
    printf '%s\n' "$WANT_STAMP" >"$STAMP"
    rm -rf -- "$SRC_DIR"
    trap - EXIT
fi

[[ -x "$CLI_BIN" ]] || die "expected binary missing: $CLI_BIN"

# Upsert install + java paths only. Keep user aliases / project dir / limits.
# ghidra config set java_home is broken upstream (Unknown config key).
mkdir -p "$CONFIG_DIR"
python3 - "$CONFIG_FILE" "$GHIDRA_INSTALL_DIR" "$JAVA_HOME_JDK" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
install_dir = sys.argv[2]
java_home = sys.argv[3]

defaults = {
    "ghidra_install_dir": install_dir,
    "ghidra_project_dir": "null",
    "java_home": java_home,
    "default_program": "null",
    "default_project": "null",
    "default_output_format": "auto",
    "default_limit": "1000",
    "launch_timeout_secs": "null",
    "aliases": "{}",
}
# Always refresh these two; never point install dir at a JDK.
force = {
    "ghidra_install_dir": install_dir,
    "java_home": java_home,
}

def upsert(text: str, key: str, value: str) -> str:
    line = f"{key}: {value}"
    pat = re.compile(rf"^{re.escape(key)}:\s*.*$", re.M)
    if pat.search(text):
        return pat.sub(line, text)
    if text and not text.endswith("\n"):
        text += "\n"
    return text + line + "\n"

if path.is_file():
    text = path.read_text(encoding="utf-8")
    for key, value in force.items():
        text = upsert(text, key, value)
else:
    text = "".join(f"{k}: {v}\n" for k, v in defaults.items())

path.write_text(text, encoding="utf-8")
print(f"config upserted: {path}")
PY

export GHIDRA_INSTALL_DIR
export GHIDRA_CLI_JAVA_HOME="$JAVA_HOME_JDK"

install_skills() {
    local dest skill_src
    mkdir -p "$AGENTS_SKILLS"

    skill_src="$REPO_ROOT/skills/ghidra-cli-host"
    [[ -f "$skill_src/SKILL.md" ]] || die "missing host skill: $skill_src/SKILL.md"
    rm -rf "${AGENTS_SKILLS:?}/ghidra-cli-host"
    cp -a "$skill_src" "${AGENTS_SKILLS}/ghidra-cli-host"

    if command -v npx >/dev/null 2>&1; then
        echo "Installing upstream ghidra-cli agent skill..."
        npx --yes skills add akiselev/ghidra-cli@ghidra-cli -g -y \
            || warn "npx skills add failed; host skill still installed"
    else
        warn "npx not found; skip upstream ghidra-cli skill"
    fi

    for dest in "${HOME}/.claude/skills" "${HOME}/.cursor/skills"; do
        [[ -L "$dest" ]] && rm -f "$dest"
        mkdir -p "$dest"
        ln -sfn "$AGENTS_SKILLS/ghidra-cli-host" "$dest/ghidra-cli-host"
        if [[ -d "$AGENTS_SKILLS/ghidra-cli" ]]; then
            ln -sfn "$AGENTS_SKILLS/ghidra-cli" "$dest/ghidra-cli"
        fi
    done
}

install_skills

echo "Running ghidra doctor..."
"$CLI_BIN" doctor

# Smoke: import only (no analysis). Program name is basename, not --program.
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghidra-cli-smoke.XXXXXX")"
SMOKE_BIN="$SMOKE_DIR/smokebin"
cp /usr/bin/true "$SMOKE_BIN"
PROJECT="dotfiles-smoke-$$"
cleanup() {
    "$CLI_BIN" stop --project "$PROJECT" >/dev/null 2>&1 || true
    "$CLI_BIN" project delete "$PROJECT" >/dev/null 2>&1 || true
    rm -rf "$SMOKE_DIR"
}
trap cleanup EXIT

echo "Smoke import..."
out="$("$CLI_BIN" import "$SMOKE_BIN" --project "$PROJECT" --no-analyze 2>&1)" || true
printf '%s\n' "$out"
if ! printf '%s' "$out" | grep -q '"status":"success"'; then
    if ! printf '%s' "$out" | grep -qi 'Successfully imported'; then
        die "smoke import failed (ghidra-cli often exits 0 on errors; check output above)"
    fi
fi

echo "✓ ghidra-cli $("$CLI_BIN" --version 2>/dev/null || echo installed)"
echo "  config: $CONFIG_FILE"
echo "  JDK:    $JAVA_HOME_JDK"
echo "  skills: $AGENTS_SKILLS/ghidra-cli-host (+ upstream ghidra-cli if npx ok)"
echo "  GUI:    ghidra-gui → $GHIDRA_INSTALL_DIR/ghidraRun (cargo bin shadows /usr/bin/ghidra)"
echo "  note:   check JSON status / stderr; process exit code is unreliable"
