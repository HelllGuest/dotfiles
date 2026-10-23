#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Running health check..."

# 1. Check for required binaries
REQUIRED_BINARIES=("stow" "zsh" "starship" "nvim" "ghostty" "fastfetch" "dconf" "jq")
SHELL_BINARIES=("atuin" "fzf" "fd" "rg" "bat" "eza" "zoxide" "direnv" "delta")
for bin in "${REQUIRED_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        echo "✗ $bin is missing"
    fi
done

echo "--- System ownership ---"
etc_owner="$(stat -c '%U' /etc 2>/dev/null || echo unknown)"
if [[ "$etc_owner" == "root" ]]; then
    echo "✓ /etc owned by root"
else
    echo "✗ /etc owned by $etc_owner (must be root — pacman hooks fail with unsafe path transition)"
    echo "  run: sudo chown root:root /etc && sudo chmod 755 /etc"
fi
# sudo -n when cached: plain find cannot enter 700 dirs (e.g. /etc/sudoers.d).
find_etc=(find)
sudo -n true 2>/dev/null && find_etc=(sudo -n find)
stowed_etc="$("${find_etc[@]}" /etc -type l -lname '*/stow/system/*' 2>/dev/null)"
if [[ -z "$stowed_etc" ]]; then
    echo "✓ no /etc symlinks into stow/system"
else
    echo "✗ /etc symlinks into stow/system (dangle at early boot; user-writable root config):"
    echo "$stowed_etc" | sed 's/^/  /'
    echo "  run: bash scripts/system-setup.sh"
fi

echo "--- Shell productivity tools ---"
for bin in "${SHELL_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        echo "✗ $bin is missing"
    fi
done

echo "--- AI tooling (optional) ---"
for bin in claude cursor headroom; do
    if command -v "$bin" >/dev/null 2>&1; then
        ver="$($bin --version 2>/dev/null | head -1 || true)"
        echo "✓ $bin is installed${ver:+ ($ver)}"
    else
        echo "○ $bin not installed (optional)"
    fi
done
if command -v headroom >/dev/null 2>&1; then
    echo "  shell: hr-claude | hr-cursor | hr-proxy"
    echo "  service: systemctl --user status headroom-default.service"
    echo "  doctor: headroom doctor"
else
    echo "  install/upgrade: bash scripts/headroom-setup.sh"
fi

AGENTS_SKILLS="${HOME}/.agents/skills"
check_agent_skill() {
    local name=$1 hint=$2
    if [[ -f "${AGENTS_SKILLS}/${name}/SKILL.md" ]]; then
        echo "✓ skill $name"
    else
        echo "○ skill $name missing (optional: $hint)"
    fi
}
check_agent_skill caveman "bash scripts/install-caveman.sh"
check_agent_skill android-compose-design "bash scripts/install-android-ui-skills.sh"
check_agent_skill material-3 "bash scripts/install-android-ui-skills.sh"
check_agent_skill reverse-engineer-anything "bash scripts/install-rea.sh"
check_agent_skill leanrea "bash scripts/install-re-skills.sh"
check_agent_skill reverse-engineering "bash scripts/install-re-skills.sh"
check_agent_skill android-reverse-engineering "bash scripts/install-re-skills.sh"
check_agent_skill ghidra-iterative-re "bash scripts/install-re-skills.sh"
check_agent_skill firmware-extraction "bash scripts/install-re-skills.sh"
check_agent_skill firmware-static-analysis "bash scripts/install-re-skills.sh"
check_agent_skill firmware-emulation "bash scripts/install-re-skills.sh"
check_agent_skill ghidra-re "bash scripts/install-re-skills.sh"

OPENCODE_SKILLS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
KIMI_SKILLS="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"
if [[ -f "${OPENCODE_SKILLS}/caveman/SKILL.md" ]]; then
    echo "✓ OpenCode skills (caveman)"
else
    echo "○ OpenCode skills missing (bash scripts/sync-agent-skills.sh)"
fi
if [[ -f "${KIMI_SKILLS}/caveman/SKILL.md" ]]; then
    echo "✓ Kimi Code skills (caveman)"
else
    echo "○ Kimi Code skills missing (bash scripts/sync-agent-skills.sh)"
fi
if command -v kimi >/dev/null 2>&1; then
    echo "✓ kimi CLI ($(kimi --version 2>/dev/null | head -1))"
else
    echo "○ kimi CLI missing (npm i -g @moonshot-ai/kimi-code)"
fi
if command -v opencode >/dev/null 2>&1; then
    echo "✓ opencode CLI ($(opencode --version 2>/dev/null | head -1))"
else
    echo "○ opencode CLI missing"
fi
if [[ -f "${KIMI_CODE_HOME:-$HOME/.kimi-code}/mcp.json" ]]; then
    echo "✓ Kimi MCP config"
else
    echo "○ Kimi MCP config missing"
fi

if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git" ]; then
    echo "✓ zinit is bootstrapped"
else
    echo "✗ zinit not bootstrapped (launch zsh once)"
fi

# 2. Check for symlinks
check_link() {
    local path=$1
    if [ -L "$path" ]; then
        echo "✓ Symlink exists: $path"
    elif [ -L "$(dirname "$path")" ] && [ -f "$path" ]; then
        echo "✓ Stowed via $(dirname "$path") -> $(readlink "$(dirname "$path")")"
    else
        echo "✗ Symlink missing: $path"
    fi
}

CHECK_LINKS=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.inputrc" "$HOME/.shell-exports" "$HOME/.shell-aliases" "$HOME/.shell-git" "$HOME/.config/starship.toml" "$HOME/.config/atuin/config.toml" "$HOME/.config/nvim/init.lua" "$HOME/.config/fastfetch/config.jsonc")
for link in "${CHECK_LINKS[@]}"; do
    check_link "$link"
done

# 3. Check for fonts
NERD_FONT_COUNT=$(fc-list : family | grep -ci 'Nerd Font' || true)
if [ "$NERD_FONT_COUNT" -gt 0 ]; then
    echo "✓ Nerd Fonts installed ($NERD_FONT_COUNT families)"
else
    echo "✗ Nerd Fonts missing — run scripts/install-fonts.sh"
fi
if fc-list : family | grep -qi "JetBrainsMono"; then
    echo "✓ JetBrainsMono Nerd Font is installed"
else
    echo "✗ JetBrainsMono Nerd Font is missing"
fi

echo "--- GDM login screen ---"
if systemctl is-enabled gdm.service >/dev/null 2>&1; then
    echo "✓ gdm.service enabled"
else
    echo "✗ gdm.service not enabled (run scripts/gdm-setup.sh)"
fi
if grep -q 'WaylandEnable=true' /etc/gdm/custom.conf 2>/dev/null; then
    echo "✓ GDM WaylandEnable=true"
else
    echo "✗ GDM WaylandEnable not set (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    echo "✓ GDM greeter dconf deployed"
else
    echo "✗ GDM greeter dconf missing"
fi
if [ -f /etc/systemd/system/gdm.service.d/override.conf ]; then
    if grep -q 'WAYLAND_DISPLAY' /etc/systemd/system/gdm.service.d/override.conf 2>/dev/null; then
        echo "✗ GDM override still sets WAYLAND_DISPLAY (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM override has no WAYLAND_DISPLAY"
    fi
else
    echo "✗ GDM systemd override missing (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    gdm_dconf_owner="$(stat -c '%U' /etc/dconf/db/gdm.d/00-login-screen 2>/dev/null || echo unknown)"
    if [ "$gdm_dconf_owner" = root ]; then
        echo "✓ GDM greeter dconf owned by root"
    else
        echo "✗ GDM greeter dconf owned by $gdm_dconf_owner (run scripts/gdm-setup.sh)"
    fi
fi
if [ -e /etc/dconf/profile/gdm ]; then
    if [ -L /etc/dconf/profile/gdm ] && readlink /etc/dconf/profile/gdm 2>/dev/null | grep -qE "$HOME|dotfiles"; then
        echo "✗ GDM dconf profile symlinks into home (run scripts/gdm-setup.sh)"
    elif [ -L /etc/dconf/profile/gdm ]; then
        echo "✗ GDM dconf profile is symlink (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM dconf profile is real file in /etc"
    fi
else
    echo "✗ GDM dconf profile missing (run scripts/gdm-setup.sh)"
fi
if systemctl show gdm.service -p DropInPaths --value 2>/dev/null | grep -q 'gdm.service.d/override.conf'; then
    echo "✓ GDM systemd drop-in loaded"
else
    echo "✗ GDM systemd drop-in not loaded (sudo systemctl daemon-reload)"
fi

echo "--- Git ---"
if [ -f "$HOME/.config/git/config" ]; then
    echo "✓ Git XDG config deployed"
else
    echo "✗ Git config missing (run scripts/git-setup.sh)"
fi
if command -v delta >/dev/null 2>&1; then
    echo "✓ delta is installed"
else
    echo "✗ delta is missing"
fi
if git config --get user.email >/dev/null 2>&1; then
    echo "✓ Git identity: $(git config --get user.name) <$(git config --get user.email)>"
else
    echo "✗ Git identity not set"
fi

echo "--- Neovim ---"
if [ -f "$HOME/.config/nvim/init.lua" ]; then
    echo "✓ Neovim config deployed"
else
    echo "✗ Neovim config missing (run scripts/nvim-setup.sh)"
fi
if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim" ]; then
    echo "✓ lazy.nvim bootstrapped"
else
    echo "✗ lazy.nvim not bootstrapped (run scripts/nvim-setup.sh)"
fi

echo "--- GNOME session ---"
if [ -f "$HOME/.config/gnome-session/scripts/tablet-mode-handler.sh" ]; then
    echo "✓ Tablet mode handler stowed"
else
    echo "✗ Tablet mode handler missing"
fi
ENABLED_EXT=$(gnome-extensions list --enabled 2>/dev/null | wc -l || echo 0)
if [ "$ENABLED_EXT" -ge 4 ] 2>/dev/null; then
    echo "✓ GNOME extensions enabled ($ENABLED_EXT)"
else
    echo "✗ Few GNOME extensions enabled ($ENABLED_EXT/4 — run scripts/gnome-session-setup.sh)"
fi

echo "--- Input / touchpad ---"
# shellcheck source=lib/input.sh
source "$REPO_ROOT/scripts/lib/input.sh"
if phantom_syna_mouse_inhibited; then
    echo "✗ synaptics Mouse node is inhibited (clicks will not work)"
    list_phantom_syna_mice | sed 's/^/  /'
    echo "  run: bash scripts/cleanup-input-overrides.sh && log out once"
else
    echo "✓ synaptics Mouse node not inhibited"
fi

# shellcheck source=lib/browsers.sh
source "$REPO_ROOT/scripts/lib/browsers.sh"

echo "--- Flatpaks ---"
if command -v flatpak >/dev/null 2>&1; then
    while IFS= read -r app; do
        [[ -n "$app" ]] || continue
        if flatpak list --app 2>/dev/null | grep -q "$app"; then
            echo "✓ $app installed"
        else
            echo "✗ $app missing (run scripts/install-flatpaks.sh)"
        fi
    done < <(read_browser_flatpaks)
    if flatpak list --app 2>/dev/null | grep -q com.protonvpn.www; then
        echo "✓ com.protonvpn.www installed"
    else
        echo "✗ com.protonvpn.www missing (run scripts/install-flatpaks.sh)"
    fi
else
    echo "✗ flatpak not installed"
fi

echo "--- Browser policies ---"
for policy in /etc/opt/chrome/policies/managed/00-privacy.json /etc/brave/policies/managed/00-privacy.json; do
    if [[ -f "$policy" ]]; then
        echo "✓ $policy"
    else
        echo "✗ $policy missing (run scripts/browser-hardening.sh)"
    fi
done
if [[ -f /etc/opt/chrome/policies/managed/00-privacy.json ]] \
  && grep -q '"CloudReportingEnabled": false' /etc/opt/chrome/policies/managed/00-privacy.json; then
    echo "✓ Chrome CloudReportingEnabled=false"
elif [[ -f /etc/opt/chrome/policies/managed/00-privacy.json ]]; then
    echo "✗ Chrome CloudReportingEnabled missing (bash scripts/browser-hardening.sh)"
else
    echo "✗ Chrome policy file missing (bash scripts/browser-hardening.sh)"
fi
if [[ -f /etc/brave/policies/managed/00-privacy.json ]] \
  && grep -q '"CloudReportingEnabled": false' /etc/brave/policies/managed/00-privacy.json \
  && grep -q '"BraveP3AEnabled": false' /etc/brave/policies/managed/00-privacy.json; then
    echo "✓ Brave CloudReporting + P3A off"
elif [[ -f /etc/brave/policies/managed/00-privacy.json ]]; then
    echo "✗ Brave policies stale (bash scripts/browser-hardening.sh)"
else
    echo "✗ Brave policy file missing (bash scripts/browser-hardening.sh)"
fi
if [[ -f /etc/firefox/policies/policies.json ]] \
  && grep -q '"DisableTelemetry": true' /etc/firefox/policies/policies.json; then
    echo "✓ /etc/firefox/policies/policies.json DisableTelemetry"
elif [[ -f /etc/firefox/policies/policies.json ]]; then
    echo "✗ /etc/firefox/policies stale (bash scripts/browser-hardening.sh)"
else
    echo "✗ /etc/firefox/policies/policies.json missing (bash scripts/browser-hardening.sh)"
fi
zen_pol="$(zen_systemconfig_dir)/policies/policies.json"
if [[ -f "$zen_pol" ]] && grep -q '"DisableTelemetry": true' "$zen_pol"; then
    echo "✓ Zen Flatpak systemconfig DisableTelemetry"
elif flatpak list --app 2>/dev/null | grep -q 'app\.zen_browser\.zen'; then
    echo "✗ Zen Flatpak policies missing (run scripts/browser-hardening.sh)"
else
    echo "○ Zen Flatpak not installed"
fi
zen_userjs_ok=0
if [[ -d "${HOME}/.var/app/app.zen_browser.zen/.zen" ]]; then
    while IFS= read -r -d '' uj; do
        prof="$(dirname "$uj")"
        if [[ -f "$prof/prefs.js" ]]; then
            zen_userjs_ok=1
            break
        fi
    done < <(find "${HOME}/.var/app/app.zen_browser.zen/.zen" -mindepth 2 -maxdepth 2 -name user.js -print0 2>/dev/null)
fi
if [[ "$zen_userjs_ok" -eq 1 ]]; then
    echo "✓ Zen user.js deployed in profile(s)"
elif flatpak list --app 2>/dev/null | grep -qE 'app\.zen_browser\.zen|io\.github\.zen_browser\.zen'; then
    echo "✗ Zen user.js missing — launch Zen once, then run scripts/browser-hardening.sh"
fi
if [[ -f "${HOME}/.var/app/app.zen_browser.zen/.zen/Profile Groups/user.js" ]]; then
    echo "✗ stray Zen user.js under Profile Groups (re-run browser-hardening.sh)"
fi
lw_ov="${HOME}/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg"
if [[ -f "$lw_ov" ]] && grep -q 'toolkit.telemetry.enabled' "$lw_ov"; then
    echo "✓ LibreWolf librewolf.overrides.cfg"
elif flatpak list --app 2>/dev/null | grep -q 'io\.gitlab\.librewolf-community'; then
    echo "✗ LibreWolf overrides missing (run scripts/browser-hardening.sh)"
else
    echo "○ LibreWolf Flatpak not installed"
fi

echo "--- Shell (bash/zsh) privacy ---"
if grep -q '90-telemetry-optout.conf' "${HOME}/.shell-exports" 2>/dev/null \
  || grep -q '90-telemetry-optout.conf' "$REPO_ROOT/stow/zsh/.shell-exports" 2>/dev/null; then
    echo "✓ shell-exports sources telemetry-optout.conf"
else
    echo "✗ shell-exports missing telemetry-optout source"
fi
if grep -q 'umask 077' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q 'umask 077' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash umask 077"
else
    echo "✗ bash umask 077 missing"
fi
if grep -q '\*--password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*--password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash HISTIGNORE secret filters (--flag / KEY=)"
else
    echo "✗ bash HISTIGNORE secret filters missing"
fi
if grep -q '\*password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✗ bash HISTIGNORE still has over-broad *password* (use *--password*)"
fi
if grep -q 'HISTORY_IGNORE' "${HOME}/.zsh-plugins" 2>/dev/null \
  || grep -q 'HISTORY_IGNORE' "$REPO_ROOT/stow/zsh/.zsh-plugins" 2>/dev/null; then
    echo "✓ zsh HISTORY_IGNORE secret filters"
else
    echo "✗ zsh HISTORY_IGNORE missing"
fi
atuin_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml"
if [[ -f "$atuin_cfg" ]] \
  && grep -qE '^auto_sync\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^update_check\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^secrets_filter\s*=\s*true' "$atuin_cfg" \
  && grep -q '(?i)--token' "$atuin_cfg"; then
    echo "✓ atuin privacy keys + secret history_filter"
else
    echo "✗ atuin privacy keys/filters missing (stow atuin / bash scripts/privacy-hardener.sh)"
fi
# Bare "(?i)password" as whole pattern (not --password / password=)
if grep -qE '"\(\?i\)password"' "$atuin_cfg" 2>/dev/null \
  || grep -qE '"\(\?i\)password"' "$REPO_ROOT/stow/atuin/.config/atuin/config.toml" 2>/dev/null; then
    echo "✗ atuin history_filter still has bare (?i)password (over-broad)"
fi
if grep -q 'LESSHISTFILE=-' "${HOME}/.shell-exports" 2>/dev/null \
  || grep -q 'LESSHISTFILE=-' "$REPO_ROOT/stow/zsh/.shell-exports" 2>/dev/null; then
    echo "✓ LESSHISTFILE=- (no less history file)"
else
    echo "○ LESSHISTFILE not disabled"
fi

echo "--- Telemetry / privacy ---"
TELEMETRY_ENV_D="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/90-telemetry-optout.conf"
if [[ -f "$TELEMETRY_ENV_D" ]]; then
    echo "✓ $TELEMETRY_ENV_D"
    for key in DO_NOT_TRACK DISABLE_TELEMETRY HEADROOM_TELEMETRY GOTELEMETRY NEXT_TELEMETRY_DISABLED; do
        if grep -q "^${key}=" "$TELEMETRY_ENV_D"; then
            echo "✓ env $key"
        else
            echo "✗ env $key missing in telemetry-optout.conf"
        fi
    done
else
    echo "✗ telemetry-optout.conf missing (stow privacy / bash scripts/privacy-hardener.sh)"
fi
if command -v gsettings >/dev/null 2>&1; then
    if [[ "$(gsettings get org.gnome.desktop.privacy report-technical-problems 2>/dev/null)" == "false" ]]; then
        echo "✓ GNOME report-technical-problems=false"
    else
        echo "✗ GNOME report-technical-problems not false (bash scripts/privacy-hardener.sh)"
    fi
fi
if [[ -f "${HOME}/.dart-tool/dart-flutter-telemetry.config" ]] \
  && grep -q '^reporting=0' "${HOME}/.dart-tool/dart-flutter-telemetry.config"; then
    echo "✓ Flutter/Dart reporting=0"
else
    echo "○ Flutter telemetry config missing (optional: bash scripts/privacy-hardener.sh)"
fi
if [[ -f "${HOME}/.claude/settings.json" ]] \
  && grep -q 'DISABLE_TELEMETRY' "${HOME}/.claude/settings.json"; then
    echo "✓ Claude settings DISABLE_TELEMETRY"
else
    echo "○ Claude settings telemetry flags missing (ai-rules install / privacy-hardener)"
fi
cursor_settings="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json"
if [[ -f "$cursor_settings" ]] \
  && grep -q '"telemetry.telemetryLevel": "off"' "$cursor_settings"; then
    echo "✓ Cursor telemetry.telemetryLevel=off"
else
    echo "○ Cursor telemetry off not confirmed"
fi
if [[ -f "$cursor_settings" ]] \
  && grep -q '"cursor.general.privacyMode": "enabled"' "$cursor_settings"; then
    echo "✓ Cursor privacyMode=enabled"
else
    echo "○ Cursor privacyMode not confirmed"
fi
# cursor.general.* belong only on Cursor; leftover keys on other IDEs are a bug.
for _non_cursor in \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity IDE/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/User/settings.json" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/Kiro/User/settings.json"
do
  if [[ -f "$_non_cursor" ]] && grep -q 'cursor\.general' "$_non_cursor"; then
    echo "✗ cursor.general.* in non-Cursor settings: $_non_cursor (re-run privacy-hardener)"
  fi
done
unset _non_cursor
if [[ -f "${HOME}/.gemini/settings.json" ]] \
  && grep -q '"usageStatisticsEnabled": false' "${HOME}/.gemini/settings.json"; then
    echo "✓ Gemini usageStatisticsEnabled=false"
else
    echo "○ Gemini usage stats opt-out not confirmed"
fi
opencode_settings="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
if [[ -f "$opencode_settings" ]] \
  && grep -q '"share": "disabled"' "$opencode_settings"; then
    echo "✓ OpenCode share=disabled"
else
    echo "○ OpenCode share=disabled not confirmed"
fi
if [[ -f "$TELEMETRY_ENV_D" ]] && grep -q '^KIMI_DISABLE_TELEMETRY=' "$TELEMETRY_ENV_D"; then
    echo "✓ env KIMI_DISABLE_TELEMETRY"
else
    echo "○ env KIMI_DISABLE_TELEMETRY missing"
fi
if [[ -f "${HOME}/.claude/settings.json" ]] \
  && grep -q '"skipWebFetchPreflight": true' "${HOME}/.claude/settings.json"; then
    echo "✓ Claude skipWebFetchPreflight=true"
else
    echo "○ Claude skipWebFetchPreflight not confirmed"
fi

echo "--- Proton VPN ---"
if [ -f "$REPO_ROOT/scripts/proton-connectivity-check.sh" ]; then
    bash "$REPO_ROOT/scripts/proton-connectivity-check.sh" 2>/dev/null || echo "⚠ Proton API unreachable (run scripts/proton-connectivity-check.sh)"
else
    echo "✗ proton-connectivity-check.sh missing"
fi

echo "Health check finished."
