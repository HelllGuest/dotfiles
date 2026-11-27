#!/usr/bin/env bash
# uninstall.test.sh — unit tests for ./uninstall.sh in an isolated fake HOME + SYSTEM_ROOT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNINSTALL="$ROOT/uninstall.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "$UNINSTALL" ]] || fail "uninstall.sh must be executable"
bash -n "$UNINSTALL" || fail "bash -n uninstall.sh"

# CLI help, list, and invalid flags
"$UNINSTALL" --help | grep -q -- '--dry-run' || fail "--help must document --dry-run"
"$UNINSTALL" --list | grep -q '^stow ' || fail "--list must include stow section"
rc=0; "$UNINSTALL" --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown flag must exit 2 (got $rc)"
rc=0; "$UNINSTALL" --only stow --skip ai >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "--only + --skip must exit 2 (got $rc)"
rc=0; "$UNINSTALL" --only nonexistent >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown section must exit 2 (got $rc)"

# Non-interactive safety gate: refuse to mutate without --yes or --dry-run
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
FAKE_HOME="$T/home"
FAKE_ROOT="$T/sysroot"
FAKE_KIT="$FAKE_HOME/dev/ai-rules"
mkdir -p "$T/bin" "$FAKE_HOME" "$FAKE_ROOT" "$FAKE_KIT/skills/verify" "$FAKE_KIT/git-hooks"
printf '# rules\n' >"$FAKE_KIT/AGENTS.md"
printf '#!/bin/sh\n' >"$FAKE_KIT/bin_agentsync"

# Isolate systemctl so tests never touch the live host systemd --user session,
# and verify unit symlinks STILL exist when disable runs (units before stow).
cat >"$T/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >>"$T/systemctl.log"
if [ "\$1" = "--user" ] && [ "\$2" = "disable" ] && [ "\$4" = "tmp-semgrep-cleanup.timer" ]; then
    [ -L "$FAKE_HOME/.config/systemd/user/tmp-semgrep-cleanup.timer" ] && echo "unit-present-at-disable" >>"$T/systemctl.log"
fi
exit 0
EOF
chmod +x "$T/bin/systemctl"
export PATH="$T/bin:$PATH"
# Isolate XDG so OpenCode/agents paths resolve under FAKE_HOME, not the host.
export XDG_CONFIG_HOME="$FAKE_HOME/.config"
export XDG_DATA_HOME="$FAKE_HOME/.local/share"
unset DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR

rc=0; HOME="$FAKE_HOME" "$UNINSTALL" </dev/null >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 ]] || fail "non-interactive run without --yes must fail closed (got $rc)"

# Populate fake HOME with stowed links + user files that MUST NOT be deleted
mkdir -p "$FAKE_HOME/.config/kitty" "$FAKE_HOME/.config/ghostty" "$FAKE_HOME/.config/systemd/user" "$FAKE_HOME/.local/bin" \
    "$FAKE_HOME/.claude/skills/vendor-real" "$FAKE_HOME/.gemini" \
    "$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof1" \
    "$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof2" \
    "$FAKE_HOME/.var/app/io.gitlab.librewolf-community/.librewolf" \
    "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/x86_64/stable/policies"

# Stowed links (real repo targets + folded dir + dangling theme link) + non-symlink user file + foreign symlink
ln -s "$ROOT/stow/zsh/.zshrc" "$FAKE_HOME/.zshrc"
ln -s "$ROOT/stow/kitty/.config/kitty/kitty.conf" "$FAKE_HOME/.config/kitty/kitty.conf"
ln -s "$ROOT/stow/nvim/.config/nvim" "$FAKE_HOME/.config/nvim"
ln -s "$ROOT/stow/tmp-cleanup/.config/systemd/user/tmp-semgrep-cleanup.timer" \
    "$FAKE_HOME/.config/systemd/user/tmp-semgrep-cleanup.timer"
printf 'keep-me\n' >"$FAKE_HOME/.bashrc"
printf 'foreign\n' >"$T/foreign-file"
ln -s "$T/foreign-file" "$FAKE_HOME/.inputrc"
ln -s "$ROOT/stow/ghostty/.config/ghostty/themes/deleted-dangling.conf" "$FAKE_HOME/.config/ghostty/theme.local.conf"
ln -s "$ROOT/stow/kitty/.config/kitty/themes/deleted-dangling.conf" "$FAKE_HOME/.config/kitty/theme.local.conf"
mkdir -p "$FAKE_HOME/.local/state/dotfiles/theme"
printf 'secops\n' >"$FAKE_HOME/.local/state/dotfiles/theme/starship"
printf 'colors: secops\n' >"$FAKE_HOME/.local/state/dotfiles/theme/contour.yml"

# AI symlinks + unmodified/modified rule copies + real vendor dir + global git config
mkdir -p "$FAKE_HOME/.kimi-code" "$FAKE_HOME/.kiro/steering" \
    "$FAKE_HOME/.claude" "$FAKE_HOME/.config/opencode"
ln -s "$FAKE_KIT/bin_agentsync" "$FAKE_HOME/.local/bin/agentsync"
ln -s "$FAKE_KIT/AGENTS.md" "$FAKE_HOME/.gemini/AGENTS.md"
ln -s "$FAKE_KIT/skills/verify" "$FAKE_HOME/.claude/skills/verify"
cp "$FAKE_KIT/AGENTS.md" "$FAKE_HOME/.kimi-code/AGENTS.md"
cp "$FAKE_KIT/AGENTS.md" "$FAKE_HOME/.config/opencode/AGENTS.md"
printf '@AGENTS.md\n' >"$FAKE_HOME/.claude/CLAUDE.md"
printf '# custom kiro rules\n' >"$FAKE_HOME/.kiro/steering/agents.md"
printf 'vendor\n' >"$FAKE_HOME/.claude/skills/vendor-real/SKILL.md"
export GIT_CONFIG_GLOBAL="$FAKE_HOME/.gitconfig"
git config --global core.hooksPath "$FAKE_KIT/git-hooks"

# Browsers: repo-tagged user.js vs hand-written user.js, plus /etc policies
printf '// Zen Browser — privacy defaults (deployed by browser-hardening.sh)\n' \
    >"$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof1/user.js"
printf '// custom user prefs\n' \
    >"$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof2/user.js"
printf '// Deployed by security/scripts/browser-hardening.sh\n' \
    >"$FAKE_HOME/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg"
mkdir -p \
    "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/x86_64/stable/policies" \
    "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/custom/stable/policies"
cp "$ROOT/security/browsers/policies/zen-policies.json" \
    "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/x86_64/stable/policies/policies.json"
printf '{"policies":{"custom":true}}\n' \
    >"$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/custom/stable/policies/policies.json"
mkdir -p "$FAKE_ROOT/etc/opt/chrome/policies/managed" "$FAKE_ROOT/etc/brave/policies/managed" "$FAKE_ROOT/etc/firefox/policies"
printf '{}\n' >"$FAKE_ROOT/etc/opt/chrome/policies/managed/00-privacy.json"
printf '{}\n' >"$FAKE_ROOT/etc/brave/policies/managed/00-privacy.json"
printf '{}\n' >"$FAKE_ROOT/etc/firefox/policies/policies.json"

# Location files
ln -s "$ROOT/security/scripts/vpn-location-sync.sh" "$FAKE_HOME/.local/bin/vpn-location-sync"
mkdir -p "$FAKE_ROOT/usr/local/bin" "$FAKE_ROOT/usr/local/share/vpn-location-sync" \
    "$FAKE_ROOT/etc/geoclue/conf.d" "$FAKE_ROOT/etc/NetworkManager/dispatcher.d" "$FAKE_ROOT/etc/polkit-1/rules.d"
printf '#!/bin/sh\n' >"$FAKE_ROOT/usr/local/bin/vpn-location-sync"
printf '0\n' >"$FAKE_ROOT/usr/local/share/vpn-location-sync/home.geolocation"
printf '51.48\n0.0\n' >"$FAKE_ROOT/etc/geolocation"
printf 'home-local\n' >"$FAKE_ROOT/etc/geolocation.local"
printf '[static]\n' >"$FAKE_ROOT/etc/geoclue/conf.d/99-static-location.conf"
printf '#!/bin/sh\n' >"$FAKE_ROOT/etc/NetworkManager/dispatcher.d/99-vpn-location"
printf 'polkit\n' >"$FAKE_ROOT/etc/polkit-1/rules.d/50-vpn-location-sync.rules"

# System files + zram backup + GDM custom.conf without backup
mkdir -p "$FAKE_ROOT/etc/sysctl.d" "$FAKE_ROOT/etc/systemd" "$FAKE_ROOT/etc/gdm" "$FAKE_ROOT/etc/dconf/db/gdm.d"
printf 'vm.swappiness=10\n' >"$FAKE_ROOT/etc/sysctl.d/99-perf.conf"
printf 'new-zram\n' >"$FAKE_ROOT/etc/systemd/zram-generator.conf"
printf 'old-zram\n' >"$FAKE_ROOT/etc/systemd/zram-generator.conf.bak.20260101"
printf '[daemon]\n' >"$FAKE_ROOT/etc/gdm/custom.conf"
printf 'greeter\n' >"$FAKE_ROOT/etc/dconf/db/gdm.d/00-login-screen"

# 1) --dry-run --all must not delete anything or disable units
HOME="$FAKE_HOME" SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" UNINSTALL_NO_STOW=1 \
    "$UNINSTALL" --all --dry-run </dev/null >/dev/null
[[ -L "$FAKE_HOME/.zshrc" && -f "$FAKE_ROOT/etc/sysctl.d/99-perf.conf" ]] \
    || fail "--dry-run must not remove any files"
! grep -q 'disable' "$T/systemctl.log" 2>/dev/null \
    || fail "--dry-run must not invoke systemctl disable"

# 2) Default --yes removes user-level (units -> stow -> ai) ONLY; leaves system/browsers/location alone
HOME="$FAKE_HOME" XDG_STATE_HOME="$FAKE_HOME/.local/state" \
    SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" UNINSTALL_NO_STOW=1 \
    "$UNINSTALL" --yes </dev/null >/dev/null
[[ ! -L "$FAKE_HOME/.zshrc" && ! -L "$FAKE_HOME/.config/kitty/kitty.conf" \
   && ! -L "$FAKE_HOME/.config/nvim" && ! -L "$FAKE_HOME/.config/ghostty/theme.local.conf" \
   && ! -L "$FAKE_HOME/.config/kitty/theme.local.conf" \
   && ! -L "$FAKE_HOME/.config/systemd/user/tmp-semgrep-cleanup.timer" ]] \
    || fail "default uninstall must remove stowed, folded, and dangling theme symlinks"
[[ ! -e "$FAKE_HOME/.local/state/dotfiles/theme" ]] \
    || fail "default uninstall must remove rice theme state dir"
[[ -f "$FAKE_HOME/.bashrc" && -L "$FAKE_HOME/.inputrc" ]] \
    || fail "default uninstall must never remove non-symlink files or foreign symlinks"
[[ ! -L "$FAKE_HOME/.local/bin/agentsync" && ! -L "$FAKE_HOME/.gemini/AGENTS.md" && ! -L "$FAKE_HOME/.claude/skills/verify" ]] \
    || fail "ai section must remove kit symlinks"
[[ ! -e "$FAKE_HOME/.kimi-code/AGENTS.md" && -f "$FAKE_HOME/.kiro/steering/agents.md" ]] \
    || fail "ai section must remove unmodified rule copies and preserve edited copies"
[[ ! -e "$FAKE_HOME/.config/opencode/AGENTS.md" ]] \
    || fail "ai section must remove unmodified OpenCode AGENTS.md copy"
[[ ! -e "$FAKE_HOME/.claude/CLAUDE.md" ]] \
    || fail "ai section must remove stock @AGENTS.md CLAUDE.md stub"
[[ -f "$FAKE_HOME/.claude/skills/vendor-real/SKILL.md" ]] \
    || fail "ai section must preserve real vendor skill directories"
[[ -z "$(git config --global --get core.hooksPath || true)" ]] \
    || fail "ai section must unset kit core.hooksPath"
[[ -f "$FAKE_ROOT/etc/sysctl.d/99-perf.conf" && -f "$FAKE_ROOT/etc/opt/chrome/policies/managed/00-privacy.json" ]] \
    || fail "default uninstall must NOT touch system or browser /etc files"
[[ -f "$FAKE_ROOT/etc/geolocation" && -f "$FAKE_ROOT/etc/geolocation.local" ]] \
    || fail "default uninstall must NOT touch /etc/geolocation*"
grep -qF 'systemctl --user disable --now tmp-semgrep-cleanup.timer' "$T/systemctl.log" \
    || fail "units section must disable tmp-semgrep-cleanup.timer"
grep -qF 'unit-present-at-disable' "$T/systemctl.log" \
    || fail "units section must disable timers BEFORE stow removes the unit symlink"

# --skip flag: skipping ai keeps a kit symlink intact
ln -s "$FAKE_KIT/AGENTS.md" "$FAKE_HOME/.gemini/AGENTS.md"
HOME="$FAKE_HOME" SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" UNINSTALL_NO_STOW=1 \
    "$UNINSTALL" --skip units,ai --yes </dev/null >/dev/null
[[ -L "$FAKE_HOME/.gemini/AGENTS.md" ]] || fail "--skip ai must preserve AI symlinks"
rm -f "$FAKE_HOME/.gemini/AGENTS.md"

# Real GNU stow -D path (when stow is installed)
if command -v stow >/dev/null 2>&1; then
    mkdir -p "$FAKE_HOME/.config"
    stow -d "$ROOT/stow" -t "$FAKE_HOME" -R starship
    [[ -L "$FAKE_HOME/.config/starship.toml" ]] || fail "precondition: stow starship failed"
    HOME="$FAKE_HOME" SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" \
        "$UNINSTALL" --only stow --yes </dev/null >/dev/null
    [[ ! -L "$FAKE_HOME/.config/starship.toml" && -f "$FAKE_HOME/.bashrc" ]] \
        || fail "real stow -D must remove starship.toml and keep .bashrc"
fi

# System section must disable systemd services BEFORE deleting unit files
_sys_dis="$(grep -n 'systemctl disable "\$_svc"' "$UNINSTALL" | cut -d: -f1)"
_sys_rm="$(grep -n 'rm_root_path "\$dest"' "$UNINSTALL" | cut -d: -f1)"
[[ -n $_sys_dis && -n $_sys_rm ]] && (( _sys_dis < _sys_rm )) \
    || fail "system section must disable services before deleting /etc unit files"
grep -q 'root_path_exists' "$UNINSTALL" \
    || fail "uninstall.sh must use root_path_exists for restricted /etc dirs like 0750 polkit-1/rules.d"

# Custom core.hooksPath must NOT be unset; merged OpenCode + custom CLAUDE.md kept
git config --global core.hooksPath "/custom/hooks"
mkdir -p "$FAKE_HOME/.config/opencode" "$FAKE_HOME/.claude"
printf '# rules\n\n<!-- caveman-begin -->\nx\n<!-- caveman-end -->\n' \
    >"$FAKE_HOME/.config/opencode/AGENTS.md"
printf '@AGENTS.md\n# local notes\n' >"$FAKE_HOME/.claude/CLAUDE.md"
HOME="$FAKE_HOME" SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" \
    "$UNINSTALL" --only ai --yes </dev/null >/dev/null
[[ "$(git config --global --get core.hooksPath)" == "/custom/hooks" ]] \
    || fail "ai section must preserve non-kit core.hooksPath"
[[ -f "$FAKE_HOME/.config/opencode/AGENTS.md" ]] \
    || fail "ai section must preserve caveman-merged OpenCode AGENTS.md"
[[ -f "$FAKE_HOME/.claude/CLAUDE.md" ]] \
    || fail "ai section must preserve customized CLAUDE.md"

# 3) --only browsers,location,system --yes cleans privileged layers safely
HOME="$FAKE_HOME" SYSTEM_ROOT="$FAKE_ROOT" AI_RULES_TARGET="$FAKE_KIT" \
    "$UNINSTALL" --only browsers,location,system --yes </dev/null >/dev/null
[[ ! -e "$FAKE_ROOT/etc/opt/chrome/policies/managed/00-privacy.json" \
   && ! -e "$FAKE_ROOT/etc/brave/policies/managed/00-privacy.json" \
   && ! -e "$FAKE_ROOT/etc/firefox/policies/policies.json" ]] \
    || fail "browsers section must remove /etc policies"
[[ ! -e "$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof1/user.js" ]] \
    || fail "browsers section must remove repo-tagged Zen user.js"
[[ -f "$FAKE_HOME/.var/app/app.zen_browser.zen/.zen/prof2/user.js" ]] \
    || fail "browsers section must preserve hand-written Zen user.js"
[[ ! -e "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/x86_64/stable/policies/policies.json" ]] \
    || fail "browsers section must remove unmodified Zen Flatpak policies.json"
[[ -f "$FAKE_HOME/.local/share/flatpak/extension/app.zen_browser.zen.systemconfig/custom/stable/policies/policies.json" ]] \
    || fail "browsers section must preserve edited Zen Flatpak policies.json"
[[ ! -e "$FAKE_HOME/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg" ]] \
    || fail "browsers section must remove repo-tagged LibreWolf overrides"
[[ ! -L "$FAKE_HOME/.local/bin/vpn-location-sync" && ! -e "$FAKE_ROOT/usr/local/bin/vpn-location-sync" ]] \
    || fail "location section must remove vpn-location-sync files"
[[ ! -e "$FAKE_ROOT/etc/geolocation" && ! -e "$FAKE_ROOT/etc/geolocation.local" ]] \
    || fail "location section must remove /etc/geolocation and geolocation.local"
[[ ! -e "$FAKE_ROOT/etc/sysctl.d/99-perf.conf" && ! -e "$FAKE_ROOT/etc/dconf/db/gdm.d/00-login-screen" ]] \
    || fail "system section must remove managed /etc files"
[[ "$(cat "$FAKE_ROOT/etc/systemd/zram-generator.conf")" == "old-zram" ]] \
    || fail "system section must restore zram-generator.conf backup"
[[ -f "$FAKE_ROOT/etc/gdm/custom.conf" ]] \
    || fail "system section must keep /etc/gdm/custom.conf when no backup exists"

echo "PASS: uninstall.test.sh"
