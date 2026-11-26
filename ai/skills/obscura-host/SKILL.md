---
name: obscura-host
description: >
  Host wiring for Obscura (Rust headless browser, CDP, MCP). Use when browsing,
  scraping, screenshots/PDF, Puppeteer/Playwright against a light Chrome-compatible
  engine, or when the user mentions Obscura / obscura mcp.
---

# Obscura host notes

Docs: https://docs.obscura.sh/ · Source: https://github.com/h4ckf0r0day/obscura

## Binaries

* `~/.local/bin/obscura` (+ `obscura-worker` beside it)
* Install/upgrade: `bash ~/dotfiles/ai/scripts/install-obscura.sh`
* Default archive: **stealth + render** (`OBSCURA_VARIANT=stealth`). Alternatives: empty / `no-render` / `no-render-stealth`.

## CLI

```bash
obscura --version
obscura fetch https://example.com --eval 'document.title'
obscura fetch https://example.com --screenshot /tmp/smoke.png
obscura serve          # CDP on :9222 (Puppeteer/Playwright)
obscura mcp            # stdio MCP for agents
```

Private/LAN URLs are blocked by default (SSRF). Opt in:

```bash
obscura --allow-private-network fetch http://127.0.0.1:8080/
# or OBSCURA_ALLOW_PRIVATE_NETWORK=1
```

Stealth: `obscura --stealth …` or MCP args `mcp` with `--stealth` (rebuild/install stealth variant).

## MCP (agents)

Wired automatically by `bash ~/dotfiles/ai/scripts/install-obscura.sh`:

* OpenCode: `mcp.obscura` → `["~/.local/bin/obscura","mcp"]` in `~/.config/opencode/opencode.json`
* Claude Code: `mcpServers.obscura` in `~/.claude.json` (`claude mcp add -s user obscura ~/.local/bin/obscura mcp`)
* Cursor: `mcpServers.obscura` in `~/.cursor/mcp.json`
* Kimi Code: `mcpServers.obscura` in `~/.kimi-code/mcp.json`
* Gemini CLI: `mcpServers.obscura` in `~/.gemini/settings.json`
* Antigravity: `mcpServers.obscura` in `~/.gemini/config/mcp_config.json`

**Session model:** navigate first (`browser_navigate`), then snapshot/interact. Element refs go stale after navigation/rerender — re-snapshot before acting.

Useful tools: `browser_navigate`, `browser_snapshot`, `browser_markdown`, `browser_click`, `browser_fill`, `browser_screenshot`, `browser_pdf`, `browser_evaluate`.

## Vs agent-browser / Chrome

Prefer Obscura when memory/startup matter or stealth is needed. Prefer system Chrome/Playwright when full Chrome fidelity is required.

## Verify

```bash
obscura --version
obscura fetch https://example.com --eval 'document.title'
# expect: Example Domain
```
