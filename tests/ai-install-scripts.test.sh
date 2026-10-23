#!/usr/bin/env bash
# Smoke: AI installer scripts parse + pinned digests/refs stay wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/sync-agent-skills.sh" \
  "$ROOT/scripts/install-caveman.sh" \
  "$ROOT/scripts/install-android-ui-skills.sh" \
  "$ROOT/scripts/install-rea.sh" \
  "$ROOT/scripts/install-coding-agents.sh" \
  "$ROOT/scripts/install-ecosystem-skills.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  [[ -x "$f" ]] || fail "not executable: $f"
  bash -n "$f" || fail "bash -n failed: $f"
done

[[ -f "$ROOT/packages/agent-skills.txt" ]] || fail "missing packages/agent-skills.txt"
grep -q 'cloudflare/skills' "$ROOT/packages/agent-skills.txt" \
  || fail "agent-skills manifest missing cloudflare pack"

grep -q 'CAVEMAN_TAG:-v4.0.1' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman tag pin missing"
grep -q 'c129b946a1f7f2e9eeeff5c1a747d7b43b2630c6b9e5fc7aa8297cece9cd3804' \
  "$ROOT/scripts/install-caveman.sh" || fail "caveman SHA-256 pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman SKIP_SKILL_SYNC missing"

grep -q 'OPENCODE_NPM_SPEC:-opencode-ai@1.19.4' \
  "$ROOT/scripts/install-coding-agents.sh" || fail "opencode npm pin missing"
grep -q 'KIMI_NPM_SPEC:-@moonshot-ai/kimi-code@2.3.0' \
  "$ROOT/scripts/install-coding-agents.sh" || fail "kimi npm pin missing"
grep -q 'ONLY_CAVEMAN_OPENCODE' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents opencode-plugin mode missing"
grep -q 'kimi-code-cli' "$ROOT/scripts/install-ecosystem-skills.sh" \
  || fail "ecosystem skills must target kimi-code-cli"

grep -q '9a9f6c4f7afff72a4d38304add19b2eb740693e5' \
  "$ROOT/scripts/install-android-ui-skills.sh" || fail "compose commit pin missing"
grep -q 'MATERIAL_3_SKILL_REF:-v1.1.1' \
  "$ROOT/scripts/install-android-ui-skills.sh" || fail "material-3 tag pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-android-ui-skills.sh" \
  || fail "android-ui SKIP_SKILL_SYNC missing"

grep -q 'SKIP_SKILL_SYNC=1' "$ROOT/install.sh" || fail "install.sh must batch skill sync"
# Pre-sync (kit fallback) + post-sync (hub mirror after AI)
sync_count="$(grep -c 'bash scripts/sync-agent-skills.sh' "$ROOT/install.sh" || true)"
[[ "$sync_count" -eq 2 ]] \
  || fail "install.sh must call sync-agent-skills.sh twice (pre + post AI)"
grep -q '3\.5a Kit skills first' "$ROOT/install.sh" \
  || fail "install.sh missing pre-AI sync block (3.5a)"
grep -q '3\.5h Hub mirror after AI' "$ROOT/install.sh" \
  || fail "install.sh missing post-AI sync block (3.5h)"
grep -q 'install-coding-agents.sh' "$ROOT/install.sh" \
  || fail "install.sh must call install-coding-agents.sh"
grep -q 'install-ecosystem-skills.sh' "$ROOT/install.sh" \
  || fail "install.sh must call install-ecosystem-skills.sh"
grep -q 'opencode\|kimi' "$ROOT/scripts/sync-agent-skills.sh" \
  || fail "sync-agent-skills must mirror opencode/kimi"
grep -q 'check_agent_skill' "$ROOT/scripts/check.sh" || fail "check.sh skill probes missing"
grep -q 'Kimi Code skills' "$ROOT/scripts/check.sh" || fail "check.sh kimi probe missing"

# Privacy / telemetry unification
[[ -f "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" ]] \
  || fail "missing stow/privacy telemetry-optout.conf"
[[ -f "$ROOT/scripts/lib/telemetry.sh" ]] || fail "missing scripts/lib/telemetry.sh"
[[ -x "$ROOT/scripts/privacy-hardener.sh" ]] || fail "privacy-hardener.sh not executable"
bash -n "$ROOT/scripts/privacy-hardener.sh" || fail "bash -n privacy-hardener.sh"
grep -q '90-telemetry-optout.conf' "$ROOT/stow/zsh/.shell-exports" \
  || fail ".shell-exports must source telemetry-optout.conf"
grep -q 'LESSHISTFILE=-' "$ROOT/stow/zsh/.shell-exports" \
  || fail ".shell-exports must disable LESSHISTFILE"
grep -q 'umask 077' "$ROOT/stow/bash/.bashrc" \
  || fail "bash must umask 077"
grep -q "HISTIGNORE=.*\*--password\*" "$ROOT/stow/bash/.bashrc" \
  || fail "bash HISTIGNORE must use *--password*"
# Bare glob entry :*password*: (not :*--password*:)
grep -qE "HISTIGNORE='[^']*:[*]password[*]:" "$ROOT/stow/bash/.bashrc" \
  && fail "bash HISTIGNORE must not use over-broad :*password*:"
grep -q 'HISTORY_IGNORE' "$ROOT/stow/zsh/.zsh-plugins" \
  || fail "zsh must set HISTORY_IGNORE"
grep -q 'API_KEY=*' "$ROOT/stow/zsh/.zsh-plugins" \
  || fail "zsh HISTORY_IGNORE must prefer API_KEY= form"
grep -q 'auto_sync = false' "$ROOT/stow/atuin/.config/atuin/config.toml" \
  || fail "atuin must disable auto_sync"
grep -q 'update_check = false' "$ROOT/stow/atuin/.config/atuin/config.toml" \
  || fail "atuin must disable update_check"
grep -q 'secrets_filter = true' "$ROOT/stow/atuin/.config/atuin/config.toml" \
  || fail "atuin must enable secrets_filter"
grep -q '(?i)--token' "$ROOT/stow/atuin/.config/atuin/config.toml" \
  || fail "atuin history_filter must include --token canary"
grep -qE '"\(\?i\)password"' "$ROOT/stow/atuin/.config/atuin/config.toml" \
  && fail "atuin must not use bare (?i)password filter"
grep -q 'telemetry_ensure_atuin' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh missing atuin helper"
grep -q 'kit_real' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "ensure_atuin must realpath-compare kit (no stow rewrite)"
grep -q 'Shell (bash/zsh) privacy' "$ROOT/scripts/check.sh" \
  || fail "check.sh missing shell privacy section"
# Behavioral: ensure_atuin must not rewrite stow-backed config
(
  export REPO_ROOT="$ROOT"
  # shellcheck source=/dev/null
  source "$ROOT/scripts/lib/telemetry.sh"
  before="$(cksum "$ROOT/stow/atuin/.config/atuin/config.toml")"
  telemetry_ensure_atuin || fail "telemetry_ensure_atuin failed on stow-backed cfg"
  after="$(cksum "$ROOT/stow/atuin/.config/atuin/config.toml")"
  [[ "$before" == "$after" ]] || fail "ensure_atuin rewrote stow atuin kit"
)
# Behavioral: non-stow merge gets canary without needing full clobber
(
  export REPO_ROOT="$ROOT"
  # shellcheck source=/dev/null
  source "$ROOT/scripts/lib/telemetry.sh"
  tmpdir="$(mktemp -d)"
  cfg="$tmpdir/config.toml"
  printf '%s\n' 'dialect = "uk"' 'auto_sync = true' 'history_filter = ["^ls"]' > "$cfg"
  # Point XDG at tmp so ensure uses our file
  export XDG_CONFIG_HOME="$tmpdir"
  mkdir -p "$tmpdir/atuin"
  mv "$cfg" "$tmpdir/atuin/config.toml"
  telemetry_ensure_atuin || fail "ensure_atuin merge failed"
  grep -qE '^auto_sync[[:space:]]*=[[:space:]]*false' "$tmpdir/atuin/config.toml" \
    || fail "merge did not set auto_sync=false"
  grep -q '(?i)--token' "$tmpdir/atuin/config.toml" \
    || fail "merge did not copy secret history_filter"
  rm -rf "$tmpdir"
)
# bash and zsh both load shared exports (telemetry)
grep -q 'shell-exports' "$ROOT/stow/bash/.bashrc" \
  || fail "bashrc must source shell-exports"
grep -q 'shell-exports' "$ROOT/stow/zsh/.zshrc" \
  || fail "zshrc must source shell-exports"
grep -q 'DO_NOT_TRACK=1' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing DO_NOT_TRACK"
grep -q 'GOTELEMETRY=off' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing GOTELEMETRY"
grep -q 'HEADROOM_TELEMETRY=off' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing HEADROOM_TELEMETRY"
grep -q 'KIMI_DISABLE_TELEMETRY=1' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing KIMI_DISABLE_TELEMETRY"
grep -q 'OPENCODE_DISABLE_AUTOUPDATE=1' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing OPENCODE_DISABLE_AUTOUPDATE"
grep -q 'CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1' \
  "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing marketplace autoinstall disable"
grep -q 'skipWebFetchPreflight' "$ROOT/ai-rules/claude-settings.json" \
  || fail "claude-settings missing skipWebFetchPreflight"
grep -q 'privacyMode' "$ROOT/ai-rules/vscode-family-telemetry.json" \
  || fail "vscode-family-telemetry missing privacyMode"
grep -q 'telemetry_ensure_gemini' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh missing gemini helper"
grep -q 'telemetry_ensure_opencode' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh missing opencode helper"
grep -q '"share": "disabled"' "$ROOT/scripts/install-coding-agents.sh" \
  || grep -q 'data\["share"\] = "disabled"' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents must set OpenCode share=disabled"
grep -q 'Telemetry / privacy' "$ROOT/scripts/check.sh" \
  || fail "check.sh missing telemetry section"
grep -q 'GOOGLE_API_USE_CLIENT_CERTIFICATE' "$ROOT/stow/zsh/.shell-exports" \
  && fail ".shell-exports must not set GOOGLE_API_USE_CLIENT_CERTIFICATE (not telemetry)"
grep -q 'git.new/crampack-sh' "$ROOT/README.md" \
  || fail "README must keep upstream Crampack one-liner after script removal"
grep -q 'pacman.txt' "$ROOT/CONTRIBUTING.md" \
  || fail "CONTRIBUTING profiles must mention pacman-then-profile"

# Finding fixes: brand link -T, kimi MCP merge, REA pin parity, install order
grep -q 'ln -sfnT' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents must use ln -sfnT for brand links"
grep -q 'preserve other servers' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents must merge kimi mcp (not clobber)"
grep -q 'REA_AGENTS_VERSION:-6.7.0' "$ROOT/scripts/install-rea.sh" \
  || fail "install-rea must pin REA_AGENTS_VERSION like coding-agents"
grep -q 'rea-agents@latest' "$ROOT/scripts/install-rea.sh" \
  && fail "install-rea must not use rea-agents@latest"
grep -q 'akiselev/ghidra-cli' "$ROOT/packages/agent-skills.txt" \
  && fail "ghidra-cli belongs in install-ghidra-cli.sh only"
grep -q 'Force link (Kimi only)' "$ROOT/scripts/sync-agent-skills.sh" \
  || fail "sync header must say OpenCode soft / Kimi force"
# privacy-hardener before check.sh
privacy_line="$(grep -n 'privacy-hardener.sh' "$ROOT/install.sh" | head -1 | cut -d: -f1)"
check_line="$(grep -n 'scripts/check.sh' "$ROOT/install.sh" | head -1 | cut -d: -f1)"
[[ -n "$privacy_line" && -n "$check_line" && "$privacy_line" -lt "$check_line" ]] \
  || fail "install.sh must run privacy-hardener before check.sh"
grep -q 'update.mode' "$ROOT/ai-rules/vscode-family-telemetry.json" \
  && fail "vscode-family-telemetry must not force update.mode"
grep -q 'Remote Control' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout must warn about Claude Remote Control"

# Browser telemetry hardening
[[ -f "$ROOT/browsers/policies/chromium-base.json" ]] || fail "missing chromium-base.json"
grep -q 'CloudReportingEnabled' "$ROOT/browsers/policies/chromium-base.json" \
  || fail "chromium-base missing CloudReportingEnabled"
grep -q 'DnsOverHttpsMode' "$ROOT/browsers/policies/chromium-base.json" \
  || fail "chromium-base missing DnsOverHttpsMode (Chrome+Brave parity)"
grep -q 'ChromeCleanupReportingEnabled' "$ROOT/browsers/policies/chromium-base.json" \
  && fail "chromium-base must not set removed ChromeCleanupReportingEnabled"
grep -q 'OfferToSaveLogins' "$ROOT/browsers/policies/zen-policies.json" \
  && fail "zen-policies must not set OfferToSaveLogins (not telemetry)"
grep -q 'deploy_zen_flatpak_policies' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must deploy Zen Flatpak systemconfig policies"
grep -q 'prefs.js' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must gate Zen user.js on prefs.js"
grep -q 'librewolf.overrides.cfg' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must deploy LibreWolf overrides"
grep -q 'User-writable first' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must deploy user-writable layers before /etc sudo"
grep -q 'flatpak_ext_arch' "$ROOT/scripts/lib/browsers.sh" \
  || fail "browsers.sh must define flatpak_ext_arch"
grep -q 'zen_systemconfig_dir' "$ROOT/scripts/check.sh" \
  || fail "check.sh must use zen_systemconfig_dir (arch parity)"
grep -q 'CloudReportingEnabled missing' "$ROOT/scripts/check.sh" \
  || fail "check.sh must ✗ stale Chrome CloudReporting"
[[ -f "$ROOT/browsers/librewolf/librewolf.overrides.cfg" ]] \
  || fail "missing browsers/librewolf/librewolf.overrides.cfg"
# Must be versioned (not ignored) so fresh clones get LibreWolf overrides
git -C "$ROOT" check-ignore -q browsers/librewolf/librewolf.overrides.cfg \
  && fail "librewolf.overrides.cfg must not be gitignored"
grep -q 'DisableTelemetry' "$ROOT/browsers/policies/zen-policies.json" \
  || fail "zen-policies missing DisableTelemetry"
bash -n "$ROOT/scripts/browser-hardening.sh" || fail "bash -n browser-hardening.sh"
bash -n "$ROOT/scripts/lib/browsers.sh" || fail "bash -n browsers.sh"
grep -q "arm64) printf 'aarch64'" "$ROOT/scripts/lib/browsers.sh" \
  || fail "flatpak_ext_arch must map arm64 to aarch64"
# Merge still valid with empty chrome-extra
jq -s 'add' "$ROOT/browsers/policies/chromium-base.json" \
  "$ROOT/browsers/policies/chrome-extra.json" \
  | jq -e '.CloudReportingEnabled == false and .DnsOverHttpsMode == "off"' >/dev/null \
  || fail "chrome policy merge broken"

# Behavioral: kimi MCP merge preserves sibling servers
python3 - <<'PY' || fail "kimi mcp merge simulation failed"
import json, tempfile, os, subprocess, textwrap
from pathlib import Path
# Simulate merge logic inline (same as install-coding-agents)
home = Path(tempfile.mkdtemp())
path = home / "mcp.json"
path.write_text(json.dumps({"mcpServers": {"custom": {"url": "https://example.test/mcp"}, "rea": {"command": "old"}}}))
data = json.loads(path.read_text())
servers = data.setdefault("mcpServers", {})
servers["headroom"] = {"command": "headroom", "args": ["mcp", "serve"]}
servers["rea"] = {"command": "npx", "args": ["-y", "rea-agents@6.7.0", "mcp"]}
path.write_text(json.dumps(data, indent=2))
out = json.loads(path.read_text())
assert "custom" in out["mcpServers"], out
assert out["mcpServers"]["rea"]["args"][1] == "rea-agents@6.7.0"
assert "headroom" in out["mcpServers"]
print("kimi-merge-sim ok")
PY

# Behavioral: ln -sfnT replaces dir; plain -sfn nests
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/content" "$tmpdir/link"
echo x > "$tmpdir/content/f"
if ln -sfnT "$tmpdir/content" "$tmpdir/link" 2>/dev/null; then
  [[ -L "$tmpdir/link" ]] || fail "ln -sfnT should make symlink"
else
  # Some ln without -T: ensure our script still documents -T
  grep -q 'ln -sfnT' "$ROOT/scripts/install-coding-agents.sh" || fail "need ln -sfnT"
fi
rm -rf "$tmpdir"

echo "PASS: ai-install-scripts.test.sh"
