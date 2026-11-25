# 20-ai-tooling.sh — sourced by scripts/check.sh at top level, in name order:
# shares check_fail/CHECK_FAILED, MODE and REPO_ROOT with the other checks.
# shellcheck shell=bash
# AI CLIs, Headroom, agent skills, OpenCode/Kimi/Gemini/Antigravity, MCP configs.

echo "--- AI tooling (optional) ---"
for bin in claude cursor gemini agy codex kiro-cli rtk headroom; do
    if command -v "$bin" >/dev/null 2>&1; then
        ver="$($bin --version 2>/dev/null | head -1 || true)"
        echo "✓ $bin is installed${ver:+ ($ver)}"
    else
        echo "○ $bin not installed (optional)"
    fi
done
if command -v headroom >/dev/null 2>&1; then
    echo "  shell: hr-claude | hr-cursor | hr-opencode | hr-agy | hr-proxy"
    # Optional: hr-* wrappers start their own proxy. A persistent one is either
    # headroom's install preset (headroom-default) or the repo's hr-proxy unit.
    _hr_unit=""
    for _u in headroom-default.service hr-proxy.service; do
        systemctl --user is-enabled --quiet "$_u" 2>/dev/null && { _hr_unit=$_u; break; }
    done
    if [[ -n $_hr_unit ]]; then
        echo "✓ persistent Headroom proxy: $_hr_unit ($(systemctl --user is-active "$_hr_unit" 2>/dev/null))"
    else
        echo "○ no persistent Headroom proxy (optional; hr-* wrappers start one) — systemctl --user enable --now hr-proxy.service"
    fi
    unset _hr_unit _u
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
check_agent_skill android-cli "bash scripts/install-ecosystem-skills.sh"
check_agent_skill gemini-api-dev "bash scripts/install-ecosystem-skills.sh"
check_agent_skill unsafe-rust-review "bash scripts/install-ecosystem-skills.sh"
check_agent_skill ai-systems-security "bash scripts/install-ecosystem-skills.sh"
check_agent_skill reverse-engineer-anything "lab-re (or optional: bash scripts/install-rea.sh)"
check_agent_skill dwarf-expert "bash scripts/install-re-skills.sh"
check_agent_skill firebase-apk-scanner "bash scripts/install-re-skills.sh"
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
CODEX_SKILLS="${HOME}/.codex/skills"
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
if [[ -f "${CODEX_SKILLS}/caveman/SKILL.md" ]]; then
    echo "✓ Codex skills (caveman)"
else
    echo "○ Codex skills missing (bash scripts/sync-agent-skills.sh)"
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
