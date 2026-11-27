# ai-rules: shared config for AI coding agents

Single source of truth for **Cursor**, **Antigravity (`agy`)**, **Gemini CLI / Code Assist / Jules**, **Kiro**, **OpenAI Codex**, **OpenCode**, **Kimi**, and **Claude Code**.

## Layout

```text
ai/rules/
├── AGENTS.md                        # shared rules + chat command dictionary
├── bin/agentsync                    # wire a repo with AGENTS.md / CLAUDE.md / GEMINI.md / .cursor
├── lib/vscode-settings-merge.sh     # shared symlink-safe JSON telemetry merge
├── skills/*/SKILL.md                # verify, double-check, refactor, test, commit, security-review, …
├── cursor-mdc/00-agents-pointer.mdc
├── git-hooks/{commit-msg,prepare-commit-msg,pre-commit,pre-push}
├── {claude,gemini}-settings.json + vscode-family-telemetry.json
└── install.sh
```

## Install & Day-to-Day

```bash
cd ~/dotfiles/ai/rules
./install.sh                   # syncs kit to ~/dev/ai-rules, links rules/skills, merges telemetry
agentsync ~/Projects/my-app    # link rules & bridges into a project (uses $AI_RULES_HOME or ~/dev/ai-rules)
~/dotfiles/uninstall.sh --only ai   # unlink kit/hub symlinks and unset global core.hooksPath
```

Edit `ai/rules/` in this repo and re-run `./install.sh` (re-runnable anytime; uses `rsync` or `cp -a` fallback). `ai/scripts/sync-agent-skills.sh` mirrors the `~/.agents/skills` hub across all agent skill dirs without writing back into `~/dev/ai-rules/skills`.

### Chat Commands (defined in `AGENTS.md`)

| Command | Action |
|---------|--------|
| `verify` | PASS/FAIL/SKIPPED checklist on session changes; no silent edits |
| `double check` | Adversarial review; findings only |
| `refactor` | Dead code/files cleanup; no behavior change |
| `test` | Run real project tests; PASS/FAIL/SKIPPED per layer |
| `debug` | Reproduce, isolate root cause, minimal fix, verify |
| `optimize` | Improve performance/readability without changing behavior |
| `explain` | Explain last change or named target |
| `docs` | Update docs only where inaccurate or incomplete vs code |
| `security` | Diff security review |
| `commit` | Conventional Commit message (no AI attribution); runs git only if asked |
| `rephrase` | Strip em/en dashes and clause hyphens from prose |

## Tool Matrix

| Tool | Rules | Skills | Telemetry |
|------|-------|--------|-----------|
| Cursor / `agent` | `AGENTS.md` + `.cursor/rules` | `~/.cursor/skills` | `vscode-family-telemetry.json` |
| Antigravity / `agy` | `AGENTS.md`, `GEMINI.md`, `~/.gemini/config/` | `~/.gemini/config/skills` | Antigravity + `~/.gemini/settings.json` |
| Gemini CLI / Code Assist | `GEMINI.md` → `@AGENTS.md`, `~/.gemini/` | `~/.gemini/skills` | `~/.gemini/settings.json` |
| Kiro / `kiro-cli` | `AGENTS.md` | `~/.kiro/skills` | `kiro-cli` setting + JSON merge |
| OpenAI Codex | `AGENTS.md`, `~/.codex/AGENTS.md` | `~/.codex/skills` | host env (`DO_NOT_TRACK` / `OTEL_SDK_DISABLED`) |
| OpenCode | `AGENTS.md`, `~/.config/opencode/AGENTS.md` | `~/.config/opencode/skills` | `share: disabled` + host env |
| Kimi Code | `AGENTS.md`, `~/.kimi-code/AGENTS.md` | `~/.kimi-code/skills` | `KIMI_DISABLE_TELEMETRY` + host env |
| Claude Code | `CLAUDE.md` → `@AGENTS.md` | `~/.claude/skills` | `claude-settings.json` (`includeCoAuthoredBy: false`) |

## Global Git Hooks & Trust Model

`install.sh` sets global `core.hooksPath` (replaces per-repo `.git/hooks`; unset via `git config --global --unset core.hooksPath`):

* **`commit-msg` / `prepare-commit-msg`:** strips AI attribution trailers, enforces Conventional Commits, prefills branch prefix (preserves `commit.verbose` diffs).
* **`pre-commit` / `pre-push` (opt-in per repo):** execute repo-defined checks (stow inventory, `tsc`/lint, `cargo check`/`clippy`, `go vet`, `ruff`) **only** in `~/dotfiles` or repos explicitly marked trusted via `git config --local hooks.trusted true` (never cloned from untrusted remotes).
* **`agentsync` safety:** warns and refuses to overwrite an existing custom `CLAUDE.md` or `GEMINI.md`.
