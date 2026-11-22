#!/usr/bin/env bash
# Smoke: AI installer scripts parse + pinned digests/refs stay wired.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/scripts/sync-agent-skills.sh" \
  "$ROOT/scripts/install-caveman.sh" \
  "$ROOT/scripts/install-ponytail.sh" \
  "$ROOT/scripts/install-android-ui-skills.sh" \
  "$ROOT/scripts/install-rea.sh" \
  "$ROOT/scripts/install-coding-agents.sh" \
  "$ROOT/scripts/install-ecosystem-skills.sh" \
  "$ROOT/scripts/install-re-skills.sh" \
  "$ROOT/scripts/install-re-extras.sh" \
  "$ROOT/scripts/install-ghidra-cli.sh" \
  "$ROOT/scripts/install-obscura.sh" \
  "$ROOT/scripts/kali-disposable.sh"
do
  [[ -f "$f" ]] || fail "missing $f"
  [[ -x "$f" ]] || fail "not executable: $f"
  bash -n "$f" || fail "bash -n failed: $f"
done

[[ -f "$ROOT/packages/agent-skills.txt" ]] || fail "missing packages/agent-skills.txt"
[[ -f "$ROOT/packages/agent-skills-re.txt" ]] || fail "missing packages/agent-skills-re.txt"
grep -q 'cloudflare/skills' "$ROOT/packages/agent-skills.txt" \
  || fail "agent-skills manifest missing cloudflare pack"

grep -q 'CAVEMAN_TAG:-v4.1.0' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman tag pin missing"
grep -q '2e39b2a9b4ce47620757abc8a55ad33a23dd65217f8a998135108f92f83c00a1' \
  "$ROOT/scripts/install-caveman.sh" || fail "caveman SHA-256 pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-caveman.sh" \
  || fail "caveman SKIP_SKILL_SYNC missing"

grep -q 'PONYTAIL_TAG:-v5.3.3' "$ROOT/scripts/install-ponytail.sh" \
  || fail "ponytail tag pin missing"
grep -q 'SKIP_SKILL_SYNC' "$ROOT/scripts/install-ponytail.sh" \
  || fail "ponytail SKIP_SKILL_SYNC missing"
grep -q 'agy plugin install' "$ROOT/scripts/install-ponytail.sh" \
  || fail "ponytail must use agy plugin install when agy is available"
grep -q 'install-ponytail.sh' "$ROOT/install.sh" \
  || fail "install.sh must call install-ponytail.sh"
grep -q 'claude mcp add -s user obscura' "$ROOT/scripts/install-obscura.sh" \
  || fail "install-obscura.sh must register obscura at Claude user scope (-s user)"
grep -q 'OBSCURA_VERSION:-v0.2.6' "$ROOT/scripts/install-obscura.sh" \
  || fail "install-obscura.sh must pin OBSCURA_VERSION"
grep -q 'ac8057374ec1b5cabb78ea2d08b2ed890d21d156a42b1ac23357fd049edc08c5' \
  "$ROOT/scripts/install-obscura.sh" || fail "install-obscura.sh missing stealth x86_64 SHA-256 pin"
grep -q 'sha256sum' "$ROOT/scripts/install-obscura.sh" \
  || fail "install-obscura.sh must verify SHA-256 before install"
grep -q '^install_ego_zip "blur-my-shell@aunetx"' "$ROOT/scripts/fetch-gnome-extensions.sh" \
  || fail "fetch-gnome-extensions must fetch Blur My Shell from EGO"
grep -q 'GIT_SETUP_NONINTERACTIVE' "$ROOT/scripts/git-setup.sh" \
  || fail "git-setup must support GIT_SETUP_NONINTERACTIVE"
grep -q 'CONFIGURE_UI' "$ROOT/scripts/configure.sh" \
  || fail "configure.sh must honor CONFIGURE_UI"
grep -q 'fail_step "configure.sh failed' "$ROOT/install.sh" \
  || fail "install.sh CONFIGURE=1 must fail_step when configure.sh fails"
grep -q 'PASS_HEADLESS' "$ROOT/scripts/vm-stageb-guest.sh" \
  || fail "vm-stageb-guest must emit PASS_HEADLESS for headless-only install failures"
grep -q 'PASS_CONFIGURE' "$ROOT/scripts/vm-stageb-guest.sh" "$ROOT/scripts/vm-stageb-run.sh" \
  && fail "PASS_CONFIGURE (passes any install failure) must be gone" || true
grep -q 'sudo firewall-cmd --permanent --get-zones' "$ROOT/scripts/lib/lab-malware-zone.sh" \
  || fail "lab-malware-zone must query permanent zones with sudo"
grep -q '192.168.200.0/24' "$ROOT/scripts/lib/lab-malware-zone.sh" \
  || fail "lab-malware-zone must bind source 192.168.200.0/24"
grep -q 'fail_step' "$ROOT/install.sh" \
  || fail "install.sh must track critical failures via fail_step"
grep -q 'INSTALL_FAILED' "$ROOT/install.sh" \
  || fail "install.sh must exit non-zero when critical steps fail"
grep -q 'opencode/AGENTS.md' "$ROOT/scripts/sync-agent-skills.sh" \
  || fail "sync-agent-skills.sh must sync shared AGENTS.md into opencode/AGENTS.md"

grep -q 'OPENCODE_NPM_SPEC:-opencode-ai@1.19.4' \
  "$ROOT/scripts/install-coding-agents.sh" || fail "opencode npm pin missing"
grep -q 'KIMI_NPM_SPEC:-@moonshot-ai/kimi-code@2.3.0' \
  "$ROOT/scripts/install-coding-agents.sh" || fail "kimi npm pin missing"
grep -q 'ONLY_CAVEMAN_OPENCODE' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents opencode-plugin mode missing"
grep -q 'owner/repo:skill1,skill2' "$ROOT/scripts/install-ecosystem-skills.sh" \
  || fail "install-ecosystem-skills must document selective skill filter"
grep -q 'mohitmishra786/low-level-dev-skills' "$ROOT/packages/agent-skills.txt" \
  || fail "agent-skills must include low-level (Meson/QEMU) pack"
grep -q 'vercel-labs/agent-browser' "$ROOT/packages/agent-skills.txt" \
  || fail "agent-skills must include agent-browser"
grep -q 'wshobson/agents:memory-forensics' "$ROOT/packages/agent-skills-re.txt" \
  || fail "agent-skills-re must include memory-forensics"
# Selective filter parse (same as install-ecosystem / install-re)
_parse_entry() {
  local entry=$1 pack skills_spec
  pack="${entry%%:*}"
  skills_spec=""
  [[ "$entry" == *:* ]] && skills_spec="${entry#*:}"
  printf '%s\t%s\n' "$pack" "$skills_spec"
}
[[ "$(_parse_entry 'owner/repo')" == $'owner/repo\t' ]] \
  || fail "ecosystem parse: bare owner/repo"
[[ "$(_parse_entry 'owner/repo:a,b')" == $'owner/repo\ta,b' ]] \
  || fail "ecosystem parse: owner/repo:skill1,skill2"
[[ "$(_parse_entry 'owner/repo@v1:a')" == $'owner/repo@v1\ta' ]] \
  || fail "ecosystem parse: owner/repo@ref:skill"
unset -f _parse_entry
grep -q 'malware-analysis' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must probe malware-analysis"
grep -q 'memory-forensics' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must probe memory-forensics"
grep -q 'vscode-settings-merge.sh' "$ROOT/ai-rules/install.sh" \
  || fail "ai-rules/install.sh must source shared vscode-settings-merge.sh"
grep -q 'vscode_is_cursor_settings_path' "$ROOT/ai-rules/lib/vscode-settings-merge.sh" \
  || fail "vscode-settings-merge must gate Cursor-only keys"
[[ -f "$ROOT/scripts/lib/agent-skills.sh" ]] \
  || fail "missing scripts/lib/agent-skills.sh (must be committed)"
[[ -f "$ROOT/ai-rules/lib/vscode-settings-merge.sh" ]] \
  || fail "missing ai-rules/lib/vscode-settings-merge.sh (must be committed)"
grep -q 'lib/agent-skills.sh' "$ROOT/scripts/install-ecosystem-skills.sh" \
  || fail "ecosystem installer must source lib/agent-skills.sh"
grep -q 'lib/agent-skills.sh' "$ROOT/scripts/install-re-skills.sh" \
  || fail "RE skills installer must source lib/agent-skills.sh"
# Wrong REPO_ROOT must still load merge lib via BASH_SOURCE fallback
_bad_root="$(
  REPO_ROOT=/tmp bash -c "
    source '$ROOT/scripts/lib/telemetry.sh'
    echo \"\$REPO_ROOT\"
    type telemetry_merge_vscode_settings >/dev/null
  "
)" || fail "telemetry.sh must recover from wrong REPO_ROOT"
[[ "$_bad_root" == "$ROOT" ]] \
  || fail "telemetry fallback REPO_ROOT want $ROOT got $_bad_root"
unset _bad_root
# Shared parse helper (source lib; avoid nameref-self names)
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/agent-skills.sh"
parsed_pack=""; parsed_args=()
agent_skills_parse_entry 'owner/repo:a,b' parsed_pack parsed_args
[[ "$parsed_pack" == "owner/repo" && "${parsed_args[*]}" == "--skill a --skill b" ]] \
  || fail "agent_skills_parse_entry failed for owner/repo:a,b"
unset parsed_pack parsed_args
grep -q 'kimi-code-cli' "$ROOT/scripts/lib/agent-skills.sh" \
  || fail "agent-skills lib must target kimi-code-cli"

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
grep -q 'check_agent_skill' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh || fail "check.sh skill probes missing"
grep -q 'Kimi Code skills' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh || fail "check.sh kimi probe missing"

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
grep -q 'Shell (bash/zsh) privacy' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
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
grep -q 'OTEL_SDK_DISABLED=true' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing OTEL_SDK_DISABLED"
grep -q 'GOTELEMETRY=off' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing GOTELEMETRY"
grep -q 'HEADROOM_TELEMETRY=off' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing HEADROOM_TELEMETRY"
grep -q 'TERRAFORM_TELEMETRY_DISABLED=1' "$ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf" \
  || fail "telemetry-optout missing TERRAFORM_TELEMETRY_DISABLED"
grep -q 'synced \$TELEMETRY_ENV_D from stow/privacy\|synced.*stow/privacy' "$ROOT/scripts/privacy-hardener.sh" \
  || fail "privacy-hardener must sync environment.d from stow kit"
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
grep -q 'TELEMETRY_CURSOR_KEYS' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh must keep Cursor keys separate from VS family"
# Non-Cursor stow settings must not ship cursor.general.*
for _ide in \
  "$ROOT/stow/vscode/.config/Code/User/settings.json" \
  "$ROOT/stow/vscode/.config/VSCodium/User/settings.json" \
  "$ROOT/stow/antigravity/.config/Antigravity IDE/User/settings.json"
do
  grep -q 'cursor.general' "$_ide" \
    && fail "non-Cursor settings must not contain cursor.general: $_ide"
done
unset _ide
# Path gating: Cursor trees only; substring "cursor" must not qualify
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/telemetry.sh"
_ck() { telemetry_keys_for_settings_path "$1" | grep -c 'cursor\.general' || true; }
[[ "$(_ck "$HOME/.config/Cursor/User/settings.json")" -eq 3 ]] \
  || fail "Cursor path must include TELEMETRY_CURSOR_KEYS"
[[ "$(_ck "$HOME/.cursor/User/settings.json")" -eq 3 ]] \
  || fail ".cursor path must include TELEMETRY_CURSOR_KEYS"
[[ "$(_ck "$ROOT/stow/cursor/.config/Cursor/User/settings.json")" -eq 3 ]] \
  || fail "stow Cursor path must include TELEMETRY_CURSOR_KEYS"
[[ "$(_ck "$HOME/.config/Code/User/settings.json")" -eq 0 ]] \
  || fail "Code path must not include TELEMETRY_CURSOR_KEYS"
[[ "$(_ck "/tmp/my-cursor-theme/Code/User/settings.json")" -eq 0 ]] \
  || fail "substring 'cursor' must not unlock Cursor keys"
unset -f _ck
grep -q 'telemetry_is_cursor_settings_path' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh must define telemetry_is_cursor_settings_path"
grep -q 'cursor\.general' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must flag cursor.general in non-Cursor settings"
# Merge strips leftover cursor.general.* on non-Cursor settings
_strip_dir="$(mktemp -d)"
_strip_settings="$_strip_dir/User/settings.json"
mkdir -p "$_strip_dir/User"
printf '%s\n' '{
  "editor.fontSize": 14,
  "cursor.general.privacyMode": "enabled",
  "cursor.general.allowAnonymousUsage": true,
  "cursor.general.enableShadowWorkspace": true
}' > "$_strip_settings"
REPO_ROOT="$ROOT" telemetry_merge_vscode_settings "$_strip_settings" \
  "$ROOT/ai-rules/vscode-family-telemetry.json" \
  || fail "telemetry_merge_vscode_settings failed on strip fixture"
grep -q 'cursor\.general' "$_strip_settings" \
  && fail "merge must strip cursor.general.* from non-Cursor settings"
grep -q '"editor.fontSize": 14' "$_strip_settings" \
  || fail "merge must keep unrelated user keys when stripping"
# Symlinked settings.json (stow): merge must preserve the symlink, not replace with a regular file
_sym_target="$_strip_dir/stow_settings.json"
mv "$_strip_settings" "$_sym_target"
ln -s "$_sym_target" "$_strip_settings"
REPO_ROOT="$ROOT" telemetry_merge_vscode_settings "$_strip_settings" \
  "$ROOT/ai-rules/vscode-family-telemetry.json" \
  || fail "telemetry_merge_vscode_settings failed on symlink fixture"
[[ -L "$_strip_settings" ]] \
  || fail "merge must preserve symlink on stow-backed settings.json"
rm -rf "$_strip_dir"
unset _strip_dir _strip_settings _sym_target
grep -q 'telemetry_ensure_gemini' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh missing gemini helper"
grep -q 'telemetry_ensure_opencode' "$ROOT/scripts/lib/telemetry.sh" \
  || fail "telemetry.sh missing opencode helper"
grep -q '"share": "disabled"' "$ROOT/scripts/install-coding-agents.sh" \
  || grep -q 'data\["share"\] = "disabled"' "$ROOT/scripts/install-coding-agents.sh" \
  || fail "coding-agents must set OpenCode share=disabled"
grep -q 'Telemetry / privacy' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
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
grep -q 'REA_AGENTS_VERSION:-6.9.0' "$ROOT/scripts/install-rea.sh" \
  || fail "install-rea must pin REA_AGENTS_VERSION like coding-agents / lab-re"
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
# CloudReportingEnabled is cloud_only (ignored in local JSON); removed/misspelled keys are no-ops.
for _bad in CloudReportingEnabled SafeBrowsingExtendedReportingEnabled SpellcheckServiceEnabled \
  AutofillAddressEnabled AutofillCreditCardEnabled PromotionalTabsEnabled; do
  grep -q "\"$_bad\"" "$ROOT/browsers/policies/chromium-base.json" \
    && fail "chromium-base must not set removed/deprecated/misspelled $_bad"
done
unset _bad
# WebRTC must not reveal the ISP/LAN address behind the VPN.
python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1])).get("WebRtcIPHandling") != "default_public_interface_only")' \
  "$ROOT/browsers/policies/chromium-base.json" || fail "chromium-base must set WebRtcIPHandling=default_public_interface_only"
for _k in media.peerconnection.ice.default_address_only media.peerconnection.ice.no_host; do
  grep -qF "user_pref(\"$_k\", true);" "$ROOT/browsers/zen/user.js" || fail "zen user.js must set $_k=true"
done
unset -v _k
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
grep -q 'zen_systemconfig_dir' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must use zen_systemconfig_dir (arch parity)"
grep -q 'policies stale vs repo' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must ✗ deployed Chromium policies that differ from the repo"
grep -q 'check_fail()' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must define check_fail for ✗ probes"
grep -q 'CHECK_FAILED' "$ROOT/scripts/check.sh" "$ROOT"/scripts/check.d/*.sh \
  || fail "check.sh must exit non-zero when ✗ probes fire"
grep -qF 'fail_step "stow failed' "$ROOT/install.sh" \
  || fail "install.sh must fail_step on stow errors"
grep -qF 'fail_step "Health check reported failures' "$ROOT/install.sh" \
  || fail "install.sh must fail_step when check.sh exits non-zero"
grep -qF 'fail_step "Profile application failed' "$ROOT/install.sh" \
  || fail "install.sh must fail_step when apply-profile fails"
grep -q 'AI_STACK_EXTRAS_ONLY=1' "$ROOT/install.sh" \
  || fail "install.sh must seed Continue/OpenCode/hr-proxy via ai-stack extras"
grep -q 'scripts/ollama-setup.sh' "$ROOT/install.sh" \
  || fail "install.sh must call ollama-setup.sh for P15 local LLM"
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
jq -e '.MetricsReportingEnabled == false and .DnsOverHttpsMode == "off"
  and .SpellCheckServiceEnabled == false and .PromotionsEnabled == false
  and (.AutofillSettings[0].url_pattern == "*")' \
  "$ROOT/browsers/policies/chromium-base.json" >/dev/null \
  || fail "chromium-base missing core privacy keys"
# Brand overlays merge over base (Chrome: Google AI features; Brave: Brave services).
jq -s 'add' "$ROOT/browsers/policies/chromium-base.json" \
  "$ROOT/browsers/policies/chrome-extra.json" \
  | jq -e '.AIModeSettings == 1 and .HelpMeWriteSettings == 2 and .MetricsReportingEnabled == false' >/dev/null \
  || fail "chrome policy merge broken"
jq -s 'add' "$ROOT/browsers/policies/chromium-base.json" \
  "$ROOT/browsers/policies/brave-extra.json" \
  | jq -e '.BraveP3AEnabled == false and .BraveStatsPingEnabled == false and .MetricsReportingEnabled == false' >/dev/null \
  || fail "brave policy merge broken"
for _bad in BraveStatsUsagePingEnabled BraveLeoEnabled; do
  grep -q "\"$_bad\"" "$ROOT/browsers/policies/brave-extra.json" \
    && fail "brave-extra must not set nonexistent $_bad"
done
unset _bad

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
servers["rea"] = {"command": "npx", "args": ["-y", "rea-agents@6.9.0", "mcp"]}
path.write_text(json.dumps(data, indent=2))
out = json.loads(path.read_text())
assert "custom" in out["mcpServers"], out
assert out["mcpServers"]["rea"]["args"][1] == "rea-agents@6.9.0"
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

# ghidra-cli installer: rustup default stable bootstrap + unlocked cargo fallback
# headroom proxies all API traffic (sees keys): pinned, never auto-upgraded.
_hr="$ROOT/scripts/install-headroom.sh"
grep -qE '^HEADROOM_VERSION="\$\{HEADROOM_VERSION:-[0-9]+\.[0-9]+\.[0-9]+\}"' "$_hr" || fail "headroom must pin HEADROOM_VERSION"
grep -q 'pipx install --force "\$HEADROOM_SPEC"' "$_hr" || fail "headroom must install the pinned spec"
! grep -qE 'headroom update|pipx upgrade|pipx install "headroom-ai\[all\]"$' "$_hr" || fail "headroom must not auto-upgrade or install unpinned"
unset -v _hr
# Arch OpenSSL 4 vs ghidra-cli's locked openssl-sys (≤3): build against openssl-3.
grep -qx 'openssl-3' "$ROOT/packages/pacman.txt" || fail "pacman.txt must include openssl-3 (ghidra-cli build)"
_gc="$ROOT/scripts/install-ghidra-cli.sh"
_ssl_line="$(grep -n 'export OPENSSL_INCLUDE_DIR=' "$_gc" | cut -d: -f1)"
_cargo_line="$(grep -n 'cargo install --path' "$_gc" | head -1 | cut -d: -f1)"
[[ -n $_ssl_line && -n $_cargo_line ]] && (( _ssl_line < _cargo_line )) \
  || fail "install-ghidra-cli must export OPENSSL_{INCLUDE,LIB}_DIR before cargo install"
_sslblk="$(awk '/^OPENSSL3_INCLUDE_DIR=/{f=1} f; f&&/^fi$/{exit}' "$_gc")"
_T="$(mktemp -d)"; mkdir -p "$_T/inc" "$_T/lib" "$_T/bin"
printf '#!/bin/sh\necho "${FAKE_SSL_VER:-4.1.0}"\n' >"$_T/bin/pkg-config"; chmod +x "$_T/bin/pkg-config"
_sslrun() { PATH="$_T/bin:$PATH" bash -c 'die() { echo "DIE: $*"; exit 7; }; '"$_sslblk"'
  echo "INC=${OPENSSL_INCLUDE_DIR:-} LIB=${OPENSSL_LIB_DIR:-}"' 2>&1; }
[[ $(OPENSSL3_INCLUDE_DIR="$_T/inc" OPENSSL3_LIB_DIR="$_T/lib" _sslrun) == "INC=$_T/inc LIB=$_T/lib" ]] \
  || fail "compat openssl-3 present: must point the build at it"
_o="$(OPENSSL3_INCLUDE_DIR="$_T/none" OPENSSL3_LIB_DIR="$_T/none" _sslrun)" && fail "OpenSSL 4 without compat must stop: $_o" || true
grep -q 'sudo pacman -S openssl-3' <<<"$_o" || fail "missing compat must say how to fix: $_o"
[[ $(FAKE_SSL_VER=3.5.9 OPENSSL3_INCLUDE_DIR="$_T/none" OPENSSL3_LIB_DIR="$_T/none" _sslrun) == "INC= LIB=" ]] \
  || fail "OpenSSL 3 system without compat: build against system OpenSSL"
rm -rf "$_T"; unset -v _gc _ssl_line _cargo_line _sslblk _o; unset -f _sslrun
grep -q 'ensure_rust_toolchain' "$ROOT/scripts/install-ghidra-cli.sh" \
  || fail "install-ghidra-cli must bootstrap rustup default stable when unconfigured (ensure_rust_toolchain)"
grep -q 'cargo install --path "\$SRC_DIR/src" --force' "$ROOT/scripts/install-ghidra-cli.sh" \
  || fail "install-ghidra-cli must fall back to unlocked cargo install"
# Ghidra 12.2 dropped DataTypeManager.remove(DataType, TaskMonitor): the bridge
# is patched to remove(DataType); exactly one site, else the build stops.
_gc="$ROOT/scripts/install-ghidra-cli.sh"
_pblk="$(awk '/^patch_ghidra_cli\(\) \{$/{f=1} f; f&&/^}$/{exit}' "$_gc")"
[[ -n $_pblk ]] || fail "patch_ghidra_cli not found"
_T="$(mktemp -d)"; mkdir -p "$_T/s/src/ghidra/scripts"
_br="$_T/s/src/ghidra/scripts/GhidraCliBridge.java"
_prun() { bash -c 'die() { echo "DIE: $*"; exit 7; }; '"$_pblk"'
patch_ghidra_cli "$1"' _ "$_T/s" 2>&1; }
printf '%s\n' 'x' '                boolean removed = dtm.remove(dataType, monitor);' 'y' >"$_br"
_prun >/dev/null || fail "patch must apply to the v0.2.2 bridge"
grep -qF 'boolean removed = dtm.remove(dataType);' "$_br" && ! grep -q 'dataType, monitor' "$_br" \
  || fail "patch must call remove(DataType): $(cat "$_br")"
_o="$(_prun)" && fail "re-patching (0 matches) must stop: $_o" || true
grep -q 'expected 1 match, found 0' <<<"$_o" || fail "0 matches must say so: $_o"
printf '%s\n' 'dtm.remove(dataType, monitor);' 'dtm.remove(dataType, monitor);' >"$_br"
_o="$(_prun)" && fail "2 matches must stop: $_o" || true
grep -q 'GHIDRA_CLI_COMMIT="${GHIDRA_CLI_COMMIT:-[0-9a-f]\{40\}}"' "$_gc" || fail "ghidra-cli tag must be pinned to a commit"
grep -q 'refusing a moved tag' "$_gc" || fail "a moved tag must be refused"
grep -q 'STAMP' "$_gc" || fail "an unpatched v0.2.2 build must be replaced (build stamp)"
grep -q '"$WANT_STAMP $(bin_hash)"' "$_gc" || fail "stamp must include the binary hash (hand-installed builds are replaced)"
rm -rf "$_T"; unset -v _gc _pblk _br _o; unset -f _prun

# sync-agent-skills + ai-rules/install.sh: prevent writing hub symlinks back into kit
grep -q 'if \[\[ -L "\$CLAUDE" \]\]; then' "$ROOT/scripts/sync-agent-skills.sh" \
  || fail "sync-agent-skills must replace whole-dir symlink \$CLAUDE before install.sh"
grep -q '\-type l' "$ROOT/ai-rules/install.sh" \
  || fail "ai-rules/install.sh sync_kit_cp must clean up orphan symlinks (-type l)"

echo "PASS: ai-install-scripts.test.sh"
