#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ✗ probes set CHECK_FAILED; install.sh treats non-zero as fail_step.
CHECK_FAILED=0
check_fail() { printf '✗ %s\n' "$*"; CHECK_FAILED=$((CHECK_FAILED + 1)); }

echo "Running health check..."

# 1. Check for required binaries
REQUIRED_BINARIES=("stow" "zsh" "starship" "nvim" "ghostty" "fastfetch" "btop" "htop" "dconf" "jq")
SHELL_BINARIES=("atuin" "fzf" "fd" "rg" "bat" "eza" "zoxide" "direnv" "delta")
for bin in "${REQUIRED_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        check_fail "$bin is missing"
    fi
done

echo "--- System ownership ---"
etc_owner="$(stat -c '%U' /etc 2>/dev/null || echo unknown)"
if [[ "$etc_owner" == "root" ]]; then
    echo "✓ /etc owned by root"
else
    check_fail "/etc owned by $etc_owner (must be root — pacman hooks fail with unsafe path transition)"
    echo "  run: sudo chown root:root /etc && sudo chmod 755 /etc"
fi
# sudo -n when cached: plain find cannot enter 700 dirs (e.g. /etc/sudoers.d).
find_etc=(find)
sudo -n true 2>/dev/null && find_etc=(sudo -n find)
stowed_etc="$("${find_etc[@]}" /etc -type l -lname '*/stow/system/*' 2>/dev/null)"
if [[ -z "$stowed_etc" ]]; then
    echo "✓ no /etc symlinks into stow/system"
else
    check_fail "/etc symlinks into stow/system (dangle at early boot; user-writable root config):"
    echo "$stowed_etc" | sed 's/^/  /'
    echo "  run: bash scripts/system-setup.sh"
fi

echo "--- Shell productivity tools ---"
for bin in "${SHELL_BINARIES[@]}"; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "✓ $bin is installed"
    else
        check_fail "$bin is missing"
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
check_agent_skill ponytail "bash scripts/install-ponytail.sh"
check_agent_skill android-compose-design "bash scripts/install-android-ui-skills.sh"
check_agent_skill material-3 "bash scripts/install-android-ui-skills.sh"
check_agent_skill reverse-engineer-anything "lab-re (or optional: bash scripts/install-rea.sh)"
check_agent_skill leanrea "bash scripts/install-re-skills.sh"
check_agent_skill reverse-engineering "bash scripts/install-re-skills.sh"
check_agent_skill android-reverse-engineering "bash scripts/install-re-skills.sh"
check_agent_skill ghidra-iterative-re "bash scripts/install-re-skills.sh"
check_agent_skill firmware-extraction "bash scripts/install-re-skills.sh"
check_agent_skill firmware-static-analysis "bash scripts/install-re-skills.sh"
check_agent_skill firmware-emulation "bash scripts/install-re-skills.sh"
check_agent_skill firmware-security-reports "bash scripts/install-re-skills.sh"
check_agent_skill ghidra-re "bash scripts/install-re-skills.sh"
check_agent_skill firmware-pentest "bash scripts/install-re-skills.sh"
check_agent_skill malware-analysis "bash scripts/install-re-skills.sh"
check_agent_skill mobile-reverse "bash scripts/install-re-skills.sh"
check_agent_skill memory-forensics "bash scripts/install-re-skills.sh"
check_agent_skill meson "bash scripts/install-ecosystem-skills.sh"
check_agent_skill arch-linux-triage "bash scripts/install-ecosystem-skills.sh"
check_agent_skill agent-browser "bash scripts/install-ecosystem-skills.sh"

OPENCODE_SKILLS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
KIMI_SKILLS="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"
GEMINI_SKILLS="${HOME}/.gemini/skills"
AGY_SKILLS="${HOME}/.gemini/config/skills"
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
if [[ -f "${GEMINI_SKILLS}/caveman/SKILL.md" ]]; then
    echo "✓ Gemini CLI skills (caveman)"
else
    echo "○ Gemini CLI skills missing (bash scripts/sync-agent-skills.sh)"
fi
if [[ -f "${AGY_SKILLS}/caveman/SKILL.md" ]]; then
    echo "✓ Antigravity skills (caveman)"
else
    echo "○ Antigravity skills missing (bash scripts/sync-agent-skills.sh)"
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
if command -v obscura >/dev/null 2>&1; then
    echo "✓ obscura ($(obscura --version 2>/dev/null | head -1))"
else
    echo "○ obscura missing (bash scripts/install-obscura.sh)"
fi
if command -v foxcage >/dev/null 2>&1; then
    echo "✓ foxcage ($(foxcage --version 2>/dev/null | head -1))"
else
    echo "○ foxcage missing (bash scripts/install-foxcage.sh)"
fi
opencode_json="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
if [[ -f "$opencode_json" ]] && grep -q '"obscura"' "$opencode_json"; then
    echo "✓ OpenCode MCP obscura"
else
    echo "○ OpenCode MCP obscura missing (bash scripts/install-obscura.sh)"
fi
check_agent_skill obscura-host "bash scripts/install-obscura.sh"
if [[ -f "${KIMI_CODE_HOME:-$HOME/.kimi-code}/mcp.json" ]]; then
    echo "✓ Kimi MCP config"
else
    echo "○ Kimi MCP config missing"
fi

if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git" ]; then
    echo "✓ zinit is bootstrapped"
else
    check_fail "zinit not bootstrapped (launch zsh once)"
fi

# 2. Check for symlinks
check_link() {
    local path=$1
    if [ -L "$path" ]; then
        echo "✓ Symlink exists: $path"
    elif [ -L "$(dirname "$path")" ] && [ -f "$path" ]; then
        echo "✓ Stowed via $(dirname "$path") -> $(readlink "$(dirname "$path")")"
    else
        check_fail "Symlink missing: $path"
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
    check_fail "Nerd Fonts missing — run scripts/install-fonts.sh"
fi
if fc-list : family | grep -qi "JetBrainsMono"; then
    echo "✓ JetBrainsMono Nerd Font is installed"
else
    check_fail "JetBrainsMono Nerd Font is missing"
fi

echo "--- GDM login screen ---"
if systemctl is-enabled gdm.service >/dev/null 2>&1; then
    echo "✓ gdm.service enabled"
else
    check_fail "gdm.service not enabled (run scripts/gdm-setup.sh)"
fi
if grep -q 'WaylandEnable=true' /etc/gdm/custom.conf 2>/dev/null; then
    echo "✓ GDM WaylandEnable=true"
else
    check_fail "GDM WaylandEnable not set (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    echo "✓ GDM greeter dconf deployed"
else
    check_fail "GDM greeter dconf missing"
fi
if [ -f /etc/systemd/system/gdm.service.d/override.conf ]; then
    if grep -q 'WAYLAND_DISPLAY' /etc/systemd/system/gdm.service.d/override.conf 2>/dev/null; then
        check_fail "GDM override still sets WAYLAND_DISPLAY (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM override has no WAYLAND_DISPLAY"
    fi
else
    check_fail "GDM systemd override missing (run scripts/gdm-setup.sh)"
fi
if [ -e /etc/dconf/db/gdm.d/00-login-screen ]; then
    gdm_dconf_owner="$(stat -c '%U' /etc/dconf/db/gdm.d/00-login-screen 2>/dev/null || echo unknown)"
    if [ "$gdm_dconf_owner" = root ]; then
        echo "✓ GDM greeter dconf owned by root"
    else
        check_fail "GDM greeter dconf owned by $gdm_dconf_owner (run scripts/gdm-setup.sh)"
    fi
fi
if [ -e /etc/dconf/profile/gdm ]; then
    if [ -L /etc/dconf/profile/gdm ] && readlink /etc/dconf/profile/gdm 2>/dev/null | grep -qE "$HOME|dotfiles"; then
        check_fail "GDM dconf profile symlinks into home (run scripts/gdm-setup.sh)"
    elif [ -L /etc/dconf/profile/gdm ]; then
        check_fail "GDM dconf profile is symlink (run scripts/gdm-setup.sh)"
    else
        echo "✓ GDM dconf profile is real file in /etc"
    fi
else
    check_fail "GDM dconf profile missing (run scripts/gdm-setup.sh)"
fi
if systemctl show gdm.service -p DropInPaths --value 2>/dev/null | grep -q 'gdm.service.d/override.conf'; then
    echo "✓ GDM systemd drop-in loaded"
else
    check_fail "GDM systemd drop-in not loaded (sudo systemctl daemon-reload)"
fi

echo "--- Git ---"
if [ -f "$HOME/.config/git/config" ]; then
    echo "✓ Git XDG config deployed"
else
    check_fail "Git config missing (run scripts/git-setup.sh)"
fi
if command -v delta >/dev/null 2>&1; then
    echo "✓ delta is installed"
else
    check_fail "delta is missing"
fi
if git config --get user.email >/dev/null 2>&1; then
    echo "✓ Git identity: $(git config --get user.name) <$(git config --get user.email)>"
else
    # Not a failure: git-setup.sh deliberately ships no default identity.
    echo "⚠ Git identity not set (git config --global user.name/user.email, or GIT_USER_NAME/GIT_USER_EMAIL with git-setup.sh)"
fi

echo "--- Neovim ---"
if [ -f "$HOME/.config/nvim/init.lua" ]; then
    echo "✓ Neovim config deployed"
else
    check_fail "Neovim config missing (run scripts/nvim-setup.sh)"
fi
if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim" ]; then
    echo "✓ lazy.nvim bootstrapped"
else
    check_fail "lazy.nvim not bootstrapped (run scripts/nvim-setup.sh)"
fi

echo "--- GNOME session ---"
ENABLED_EXT=$(gnome-extensions list --enabled 2>/dev/null | wc -l || echo 0)
if [ "$ENABLED_EXT" -ge 4 ] 2>/dev/null; then
    echo "✓ GNOME extensions enabled ($ENABLED_EXT)"
else
    check_fail "Few GNOME extensions enabled ($ENABLED_EXT/4 — run scripts/gnome-session-setup.sh)"
fi

echo "--- Input / touchpad ---"
# shellcheck source=lib/input.sh
source "$REPO_ROOT/scripts/lib/input.sh"
# shellcheck source=lib/dmi.sh
source "$REPO_ROOT/scripts/lib/dmi.sh"
if phantom_syna_mouse_inhibited; then
    check_fail "synaptics Mouse node is inhibited (clicks will not work)"
    list_phantom_syna_mice | sed 's/^/  /'
    echo "  run: bash scripts/cleanup-input-overrides.sh && log out once"
else
    echo "✓ synaptics Mouse node not inhibited"
fi
if is_thinkpad_t14s; then
    for _tp_w in /sys/bus/i2c/devices/i2c-ELAN0678:*/power/wakeup /sys/bus/i2c/devices/i2c-SYNA8018:*/power/wakeup; do
        [[ -f "$_tp_w" ]] || continue
        if [[ "$(cat "$_tp_w" 2>/dev/null)" == "disabled" ]]; then
            echo "✓ T14s touchpad s2idle wakeup disabled (${_tp_w%/power/wakeup})"
        else
            check_fail "T14s touchpad s2idle wakeup enabled (${_tp_w%/power/wakeup} — run profiles/thinkpad-t14s.sh)"
        fi
    done
    unset _tp_w
    if grep -qx 'LIBVA_DRIVER_NAME=radeonsi' /etc/environment.d/99-wayland.conf 2>/dev/null; then
        echo "✓ /etc/environment.d/99-wayland.conf sets LIBVA_DRIVER_NAME=radeonsi"
    else
        check_fail "/etc/environment.d/99-wayland.conf missing LIBVA_DRIVER_NAME=radeonsi (run scripts/system-setup.sh)"
    fi
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
            check_fail "$app missing (run scripts/install-flatpaks.sh)"
        fi
    done < <(read_browser_flatpaks)
    if flatpak list --app 2>/dev/null | grep -q com.protonvpn.www; then
        echo "✓ com.protonvpn.www installed"
    else
        check_fail "com.protonvpn.www missing (run scripts/install-flatpaks.sh)"
    fi
else
    check_fail "flatpak not installed"
fi

echo "--- Browser policies ---"
for policy in /etc/opt/chrome/policies/managed/00-privacy.json /etc/brave/policies/managed/00-privacy.json; do
    if [[ -f "$policy" ]]; then
        echo "✓ $policy"
    else
        check_fail "$policy missing (run scripts/browser-hardening.sh)"
    fi
done
# Deployed Chromium policies must equal base + brand overlay from the repo.
check_chromium_policy() {
    local label=$1 extra=$2 dest=$3 want
    if [[ ! -f "$dest" ]]; then
        check_fail "$label policy file missing (bash scripts/browser-hardening.sh)"
    elif ! want="$(chromium_policy_json "$extra" 2>/dev/null | jq -S .)"; then
        check_fail "$label policy check needs jq + browsers/policies (bash scripts/browser-hardening.sh)"
    elif [[ "$(jq -S . "$dest" 2>/dev/null)" == "$want" ]]; then
        echo "✓ $label policies match repo ($(jq length "$dest") keys)"
    else
        check_fail "$label policies stale vs repo (bash scripts/browser-hardening.sh)"
    fi
}
check_chromium_policy Chrome "$CHROME_EXTRA" /etc/opt/chrome/policies/managed/00-privacy.json
check_chromium_policy Brave "$BRAVE_EXTRA" /etc/brave/policies/managed/00-privacy.json
if [[ -f /etc/firefox/policies/policies.json ]] \
  && grep -q '"DisableTelemetry": true' /etc/firefox/policies/policies.json; then
    echo "✓ /etc/firefox/policies/policies.json DisableTelemetry"
elif [[ -f /etc/firefox/policies/policies.json ]]; then
    check_fail "/etc/firefox/policies stale (bash scripts/browser-hardening.sh)"
else
    check_fail "/etc/firefox/policies/policies.json missing (bash scripts/browser-hardening.sh)"
fi
zen_pol="$(zen_systemconfig_dir)/policies/policies.json"
if [[ -f "$zen_pol" ]] && grep -q '"DisableTelemetry": true' "$zen_pol"; then
    echo "✓ Zen Flatpak systemconfig DisableTelemetry"
elif flatpak list --app 2>/dev/null | grep -q 'app\.zen_browser\.zen'; then
    check_fail "Zen Flatpak policies missing (run scripts/browser-hardening.sh)"
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
    check_fail "Zen user.js missing — launch Zen once, then run scripts/browser-hardening.sh"
fi
if [[ -f "${HOME}/.var/app/app.zen_browser.zen/.zen/Profile Groups/user.js" ]]; then
    check_fail "stray Zen user.js under Profile Groups (re-run browser-hardening.sh)"
fi
lw_ov="${HOME}/.var/app/io.gitlab.librewolf-community/.librewolf/librewolf.overrides.cfg"
if [[ -f "$lw_ov" ]] && grep -q 'toolkit.telemetry.enabled' "$lw_ov"; then
    echo "✓ LibreWolf librewolf.overrides.cfg"
elif flatpak list --app 2>/dev/null | grep -q 'io\.gitlab\.librewolf-community'; then
    check_fail "LibreWolf overrides missing (run scripts/browser-hardening.sh)"
else
    echo "○ LibreWolf Flatpak not installed"
fi

echo "--- Shell (bash/zsh) privacy ---"
if grep -q '90-telemetry-optout.conf' "${HOME}/.shell-exports" 2>/dev/null \
  || grep -q '90-telemetry-optout.conf' "$REPO_ROOT/stow/zsh/.shell-exports" 2>/dev/null; then
    echo "✓ shell-exports sources telemetry-optout.conf"
else
    check_fail "shell-exports missing telemetry-optout source"
fi
if grep -q 'umask 077' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q 'umask 077' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash umask 077"
else
    check_fail "bash umask 077 missing"
fi
if grep -q '\*--password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*--password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    echo "✓ bash HISTIGNORE secret filters (--flag / KEY=)"
else
    check_fail "bash HISTIGNORE secret filters missing"
fi
if grep -q '\*password\*' "${HOME}/.bashrc" 2>/dev/null \
  || grep -q '\*password\*' "$REPO_ROOT/stow/bash/.bashrc" 2>/dev/null; then
    check_fail "bash HISTIGNORE still has over-broad *password* (use *--password*)"
fi
if grep -q 'HISTORY_IGNORE' "${HOME}/.zsh-plugins" 2>/dev/null \
  || grep -q 'HISTORY_IGNORE' "$REPO_ROOT/stow/zsh/.zsh-plugins" 2>/dev/null; then
    echo "✓ zsh HISTORY_IGNORE secret filters"
else
    check_fail "zsh HISTORY_IGNORE missing"
fi
atuin_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/atuin/config.toml"
if [[ -f "$atuin_cfg" ]] \
  && grep -qE '^auto_sync\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^update_check\s*=\s*false' "$atuin_cfg" \
  && grep -qE '^secrets_filter\s*=\s*true' "$atuin_cfg" \
  && grep -q '(?i)--token' "$atuin_cfg"; then
    echo "✓ atuin privacy keys + secret history_filter"
else
    check_fail "atuin privacy keys/filters missing (stow atuin / bash scripts/privacy-hardener.sh)"
fi
# Bare "(?i)password" as whole pattern (not --password / password=)
if grep -qE '"\(\?i\)password"' "$atuin_cfg" 2>/dev/null \
  || grep -qE '"\(\?i\)password"' "$REPO_ROOT/stow/atuin/.config/atuin/config.toml" 2>/dev/null; then
    check_fail "atuin history_filter still has bare (?i)password (over-broad)"
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
    for key in DO_NOT_TRACK DISABLE_TELEMETRY OTEL_SDK_DISABLED HEADROOM_TELEMETRY GOTELEMETRY NEXT_TELEMETRY_DISABLED; do
        if grep -q "^${key}=" "$TELEMETRY_ENV_D"; then
            echo "✓ env $key"
        else
            check_fail "env $key missing in telemetry-optout.conf"
        fi
    done
else
    check_fail "telemetry-optout.conf missing (stow privacy / bash scripts/privacy-hardener.sh)"
fi
if command -v gsettings >/dev/null 2>&1; then
    if [[ "$(gsettings get org.gnome.desktop.privacy report-technical-problems 2>/dev/null)" == "false" ]]; then
        echo "✓ GNOME report-technical-problems=false"
    else
        check_fail "GNOME report-technical-problems not false (bash scripts/privacy-hardener.sh)"
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
    check_fail "cursor.general.* in non-Cursor settings: $_non_cursor (re-run privacy-hardener)"
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

echo "--- Tailscale / firewalld ---"
if command -v tailscale >/dev/null 2>&1; then
    echo "✓ tailscale installed"
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        if firewall-cmd --zone=trusted --list-interfaces 2>/dev/null | grep -qw tailscale0 \
          || firewall-cmd --get-active-zones 2>/dev/null | grep -A1 '^trusted' | grep -qw tailscale0; then
            echo "✓ firewalld trusted zone includes tailscale0"
        else
            echo "○ firewalld active but tailscale0 not in trusted — bash scripts/firewalld-tailscale.sh"
        fi
    else
        echo "○ firewalld inactive (run scripts/firewalld-lab-zones.sh)"
    fi
else
    echo "○ tailscale not installed"
fi
if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "✓ firewalld active (default=$(firewall-cmd --get-default-zone 2>/dev/null || echo ?))"
elif systemctl is-enabled --quiet firewalld 2>/dev/null; then
    check_fail "firewalld enabled but not active"
else
    check_fail "firewalld not enabled — pacman -S firewalld && bash scripts/firewalld-lab-zones.sh"
fi
if pacman -Q ufw >/dev/null 2>&1; then
    check_fail "ufw package still installed — remove with: bash scripts/firewalld-lab-zones.sh"
else
    echo "✓ ufw not installed"
fi
if systemctl is-active --quiet ufw 2>/dev/null; then
    check_fail "ufw.service is active — run bash scripts/firewalld-lab-zones.sh"
elif systemctl is-enabled ufw 2>&1 | grep -qi masked; then
    echo "✓ ufw masked"
elif systemctl is-enabled --quiet ufw 2>/dev/null; then
    check_fail "ufw.service is enabled — run bash scripts/firewalld-lab-zones.sh"
fi

echo "--- Podman (rootless) ---"
if command -v podman >/dev/null 2>&1; then
    # Image storage alone can auto-detect fuse-overlayfs; podman build's context
    # overlay only uses it via mount_program (stow containers → storage.conf).
    if _podman_err="$(podman info --format '{{.Store.GraphOptions}}' 2>&1 >/dev/null)"; then
        if podman info --format '{{.Store.GraphOptions}}' 2>/dev/null | grep -q 'mount_program'; then
            echo "✓ podman storage usable (overlay via fuse-overlayfs)"
        else
            check_fail "podman mount_program unset: podman build fails on linux-hardened (stow -R containers)"
        fi
    else
        check_fail "podman storage unusable: ${_podman_err%%$'\n'*}"
        echo "  linux-hardened has no unprivileged overlayfs: sudo pacman -S fuse-overlayfs, then stow -R containers"
    fi
    unset _podman_err
else
    echo "○ podman not installed"
fi

echo "--- Ops / privacy tools ---"
for _bin in paccache mat2 exiftool bleachbit usbguard dnscrypt-proxy; do
    if command -v "$_bin" >/dev/null 2>&1; then
        echo "✓ $_bin present"
    else
        echo "○ $_bin missing — pacman -S from packages/pacman.txt / ./install.sh"
    fi
done
unset _bin
if systemctl is-enabled --quiet paccache.timer 2>/dev/null; then
    echo "✓ paccache.timer enabled"
else
    echo "○ paccache.timer off — bash scripts/ops-hygiene.sh"
fi
if systemctl is-active --quiet usbguard 2>/dev/null; then
    echo "✓ usbguard active"
else
    echo "○ usbguard inactive — bash scripts/usbguard-setup.sh (allowlists plugged devices first)"
fi
if systemctl is-active --quiet dnscrypt-proxy 2>/dev/null; then
    echo "✓ dnscrypt-proxy active"
else
    echo "○ dnscrypt-proxy inactive — bash scripts/dnscrypt-setup.sh (Tailscale MagicDNS may override)"
fi

echo "--- Proton VPN ---"
if [ -f "$REPO_ROOT/scripts/proton-connectivity-check.sh" ]; then
    bash "$REPO_ROOT/scripts/proton-connectivity-check.sh" 2>/dev/null || echo "⚠ Proton API unreachable (run scripts/proton-connectivity-check.sh)"
else
    check_fail "proton-connectivity-check.sh missing"
fi

echo "--- ThinkPad charge thresholds ---"
_charge="$REPO_ROOT/scripts/thinkpad-charge-thresholds.sh"
if [[ -f "$_charge" ]]; then
    if bash -n "$_charge" 2>/dev/null; then
        echo "✓ thinkpad-charge-thresholds.sh (syntax OK)"
    else
        check_fail "thinkpad-charge-thresholds.sh bash -n failed"
    fi
    if [[ -r /sys/class/power_supply/BAT0/charge_control_start_threshold ]]; then
        _cs="$(cat /sys/class/power_supply/BAT0/charge_control_start_threshold 2>/dev/null || true)"
        _ce="$(cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || true)"
        echo "  BAT0 live: start=${_cs:-?} end=${_ce:-?}"
        unset _cs _ce
    else
        echo "  ○ no BAT0 charge_control_* (non-ThinkPad or module not loaded)"
    fi
    # Only nag about missing persistence on hosts that expose BAT charge controls.
    if [[ -r /sys/class/power_supply/BAT0/charge_control_start_threshold ]]; then
      if [[ -f /etc/tmpfiles.d/thinkpad-charge-thresholds.conf ]]; then
          echo "✓ /etc/tmpfiles.d/thinkpad-charge-thresholds.conf present"
      else
          echo "○ charge tmpfiles not installed (bash scripts/thinkpad-charge-thresholds.sh)"
      fi
      if [[ -f /etc/systemd/system/thinkpad-charge-thresholds.service ]]; then
          echo "✓ thinkpad-charge-thresholds.service unit present"
          if systemctl is-enabled thinkpad-charge-thresholds.service >/dev/null 2>&1; then
              echo "✓ thinkpad-charge-thresholds.service enabled"
          else
              echo "○ thinkpad-charge-thresholds.service not enabled (re-run helper)"
          fi
      else
          echo "○ charge late-boot unit missing (bash scripts/thinkpad-charge-thresholds.sh)"
      fi
      if [[ -x /usr/local/lib/thinkpad/apply-charge-thresholds.sh ]]; then
          echo "✓ /usr/local/lib/thinkpad/apply-charge-thresholds.sh present"
      else
          echo "○ apply-charge-thresholds.sh missing (re-run helper)"
      fi
    fi
else
    check_fail "thinkpad-charge-thresholds.sh missing"
fi
unset _charge

echo "Health check finished."
if [[ "$CHECK_FAILED" -ne 0 ]]; then
    echo "Health check failed ($CHECK_FAILED)."
    exit 1
fi
exit 0
