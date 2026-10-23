#!/usr/bin/env bash
# privacy-hardener.sh — unified telemetry / reporting opt-out (OS + apps + user tools)
#
# Layers (idempotent, safe to re-run):
#   1) GNOME desktop privacy (gsettings)
#   2) Browsers (browser-hardening.sh → Chrome/Brave/Zen/LibreWolf)
#   3) Session env (stow/privacy → environment.d; shell sources same file)
#   4) IDE / editor telemetry (VS Code family + Claude settings)
#   5) Flutter/Dart reporting=0
#   6) Headroom / AI CLI env sanity
#   7) Optional: kiro-cli telemetry off
#
# Usage:
#   bash scripts/privacy-hardener.sh
#   SKIP_BROWSER_HARDENING=1 bash scripts/privacy-hardener.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/telemetry.sh
source "$REPO_ROOT/scripts/lib/telemetry.sh"

say() { printf '→ %s\n' "$*"; }
warn() { echo "warning: $*" >&2; }

echo "Applying privacy hardening (telemetry / reporting off)..."

# ── 1. GNOME (desktop OS) ───────────────────────────────────────────
gset() {
  # gset SCHEMA KEY VALUE — skip missing keys (schema drift across GNOME versions)
  local schema="$1" key="$2" value="$3"
  gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key" || return 0
  gsettings set "$schema" "$key" "$value"
}
if command -v gsettings >/dev/null 2>&1; then
  say "GNOME privacy (gsettings)"
  gset org.gnome.desktop.privacy report-technical-problems false
  gset org.gnome.desktop.privacy send-software-usage-stats false
  gset org.gnome.desktop.privacy connectivity-checking false
  gset org.gnome.desktop.privacy remember-recent-files false
  gset org.gnome.desktop.privacy remember-app-usage false
  gset org.gnome.desktop.privacy remove-old-trash-files true
  gset org.gnome.desktop.privacy remove-old-temp-files true
  # GNOME Software auto-download (not telemetry, but remote phone-home-ish)
  gset org.gnome.Software download-updates false
  # Location stays enabled for Night Light; static GeoClue via location-setup.sh
else
  warn "gsettings missing — skip GNOME layer"
fi

# ── 2. Browsers ─────────────────────────────────────────────────────
if [[ "${SKIP_BROWSER_HARDENING:-0}" != "1" && -f "$REPO_ROOT/scripts/browser-hardening.sh" ]]; then
  say "Browsers (Chrome / Brave / Zen / LibreWolf)"
  bash "$REPO_ROOT/scripts/browser-hardening.sh" || warn "browser-hardening failed"
else
  say "Browsers skipped (SKIP_BROWSER_HARDENING=1 or script missing)"
fi

# ── 3. Session environment (CLI + GUI apps under systemd user) ──────
say "Session env (environment.d telemetry opt-out)"
if telemetry_env_d_ok; then
  echo "  ok $TELEMETRY_ENV_D"
else
  # Stow may not have run yet — copy from repo
  src="$REPO_ROOT/stow/privacy/.config/environment.d/90-telemetry-optout.conf"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$TELEMETRY_ENV_D")"
    cp -a "$src" "$TELEMETRY_ENV_D"
    echo "  installed $TELEMETRY_ENV_D (run stow privacy / install.sh to keep in sync)"
  else
    warn "missing $src — re-check out stow/privacy"
  fi
fi

# ── 4. IDEs / editors ───────────────────────────────────────────────
say "IDE telemetry (Cursor / Antigravity / Kiro / VS Code / VSCodium / Claude)"
TELEMETRY_KIT_VS="$REPO_ROOT/ai-rules/vscode-family-telemetry.json"
if [[ -f "$TELEMETRY_KIT_VS" ]]; then
  while IFS= read -r spath; do
    [[ -n "$spath" ]] || continue
    # Only merge when User/ already exists (no orphan IDE trees)
    if [[ -d "$(dirname "$spath")" ]]; then
      if telemetry_merge_vscode_settings "$spath" "$TELEMETRY_KIT_VS"; then
        echo "  merged $spath"
      fi
    fi
  done < <(telemetry_vscode_targets)
else
  warn "missing ai-rules/vscode-family-telemetry.json"
fi
telemetry_ensure_claude_env && echo "  Claude settings env opt-out merged" || true

# Stow-managed copies (repo trees already present)
for stow_settings in \
  "$REPO_ROOT/stow/cursor/.config/Cursor/User/settings.json" \
  "$REPO_ROOT/stow/antigravity/.config/Antigravity IDE/User/settings.json" \
  "$REPO_ROOT/stow/vscode/.config/Code/User/settings.json" \
  "$REPO_ROOT/stow/vscode/.config/VSCodium/User/settings.json"
do
  if [[ -f "$stow_settings" ]]; then
    telemetry_merge_vscode_settings "$stow_settings" "$TELEMETRY_KIT_VS" 2>/dev/null \
      && echo "  stow aligned $stow_settings" \
      || true
  fi
done

if command -v kiro-cli >/dev/null 2>&1; then
  kiro-cli settings telemetry.enabled false >/dev/null 2>&1 \
    && echo "  kiro-cli telemetry.enabled=false" \
    || warn "kiro-cli telemetry setting failed"
fi

# ── 5. Flutter / Dart ───────────────────────────────────────────────
say "Flutter/Dart reporting=0"
telemetry_ensure_flutter
echo "  $TELEMETRY_FLUTTER_CFG"

# ── 5b. Shell history tools (bash/zsh atuin) ─────────────────────────
say "Shell history (atuin privacy)"
if telemetry_ensure_atuin; then
  echo "  atuin auto_sync=false update_check=false secrets_filter=true"
else
  warn "atuin privacy keys missing (stow atuin / check ~/.config/atuin/config.toml)"
fi

# ── 6. Headroom / AI CLIs ───────────────────────────────────────────
say "Headroom / AI CLI"
if telemetry_ensure_headroom; then
  :
else
  warn "Headroom telemetry checks failed (see above)"
fi
if telemetry_ensure_gemini; then
  echo "  Gemini privacy.usageStatisticsEnabled=false + telemetry.enabled=false"
else
  [[ -d "${HOME}/.gemini" ]] && warn "Gemini settings merge failed" || true
fi
if telemetry_ensure_opencode; then
  echo "  OpenCode share=disabled autoupdate=false openTelemetry=false"
fi
if telemetry_ensure_kimi_mcp; then
  echo "  Kimi MCP cleaned (no custom-keep test server)"
fi
echo "  env: DO_NOT_TRACK / DISABLE_TELEMETRY / HEADROOM_TELEMETRY / KIMI_DISABLE_TELEMETRY"
echo "  note: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC + DO_NOT_TRACK may block Claude Remote Control"

# ── 7. Summary ──────────────────────────────────────────────────────
cat <<EOF

Privacy hardening complete.
  OS:      GNOME privacy keys + Software download-updates
  Browsers: Chrome/Brave managed policies; Zen user.js; LibreWolf upstream
  Session:  ~/.config/environment.d/90-telemetry-optout.conf
  Shell:    .shell-exports sources the same file; atuin sync/update off
  IDEs:     vscode-family-telemetry.json merged; Claude env flags
  Mobile:   ~/.dart-tool/dart-flutter-telemetry.config reporting=0

Re-login (or reboot) so environment.d applies to GUI apps.
Verify: bash scripts/check.sh | grep -i telemetry
EOF
