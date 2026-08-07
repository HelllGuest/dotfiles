# ai-rules: one config for Cursor, Antigravity, Kiro, and Claude Code

## Why this works

* **`AGENTS.md`**: shared constitution (rules + command dictionary). Read by
  Cursor, Antigravity, Kiro, and (via bridge) Claude Code.
* **`skills/*/SKILL.md`**: Agent Skills slash commands for **Claude Code** and
  **Kiro**. Cursor / Antigravity use the same procedures from AGENTS.md
  Commands when you say `verify` / `double check` / etc. in chat.
* **`bin/agentsync`**: one command to wire a project (`AGENTS.md`,
  `CLAUDE.md` → `@AGENTS.md`, optional `.cursor/rules` pointer).
* **`git-hooks/`**: global hooks via `core.hooksPath` (strip AI trailers,
  Conventional Commits, branch-name prefill, pre-push lint).

## Layout

```
ai-rules/
├── AGENTS.md
├── bin/agentsync
├── skills/{verify,double-check,refactor,test,commit,security-review,rephrase,optimize,explain,docs,debug}/SKILL.md
├── cursor-mdc/00-agents-pointer.mdc
├── git-hooks/{commit-msg,prepare-commit-msg,pre-push}
├── claude-settings.json          # merged into ~/.claude/settings.json
├── vscode-family-telemetry.json  # merged into VS Code family settings.json
├── install.sh
└── README.md
```

## Install

```bash
chmod +x install.sh bin/agentsync
./install.sh                 # syncs to ~/dev/ai-rules, links skills, merges settings
```

Re-run anytime. `rsync` keeps `~/dev/ai-rules` identical to this tree.
Skills: whole-dir symlink if missing, else **per-skill merge** (keeps
`find-skills` / `caveman`). Claude settings: jq-merge kit `env` +
`includeCoAuthoredBy` without wiping hooks/plugins.

## Day to day

```bash
agentsync ~/Projects/my-app    # or: agentsync .   inside a repo
```

In any IDE / CLI chat:

| Say | Means |
|-----|--------|
| `verify` | Checklist PASS/FAIL/SKIPPED on session changes; no silent edits |
| `double check` | Adversarial review; findings only |
| `refactor` | Dead code/files cleanup; no behavior change |
| `test` | Run real project tests for last change |
| `debug` | Reproduce, isolate root cause, minimal fix, then verify |
| `optimize` | Improve performance/memory/readability/maintainability; no behavior change |
| `explain` | Explain only the last change |
| `docs` | Update README/inline docs only when wrong vs code |
| `security` | Diff security review |
| `commit` | Conventional Commit message only (no AI trailer; no auto-commit) |
| `rephrase` | Drop dash punctuation; rewrite with colon/period/semicolon |

Edit rules **only** in `~/dev/ai-rules` (or this repo's `ai-rules/` then
re-run `install.sh`).

## Tool matrix

| Tool | Rules | Skills | Telemetry |
|------|-------|--------|-----------|
| Cursor GUI / `agent` | `AGENTS.md` + `.cursor/rules` pointer | via Commands in AGENTS | merge vscode-family JSON |
| Antigravity GUI / `agy` | `AGENTS.md` | via Commands | GUI off + JSON merge |
| Kiro GUI / `kiro-cli` | `AGENTS.md` | `~/.kiro/skills` | CLI setting + JSON |
| Claude CLI | `CLAUDE.md` → `@AGENTS.md` | `~/.claude/skills` | merged `env` in settings |

## Notes

* Global `core.hooksPath` **replaces** repo `.git/hooks` (husky ignored).
  Kit hooks: `commit-msg` (strip then Conventional Commits),
  `prepare-commit-msg` (branch prefill; respects `commit.verbose` scissors),
  `pre-push` (tsc/lint/cargo/go/ruff when manifests exist).
  Unset: `git config --global --unset core.hooksPath`
* Prefer granular Claude env vars (in kit) over umbrella
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (breaks auto-update).
* Cursor Privacy Mode is not the same as crash reporting; the kit sets
  `crashReporting.enabled: false`.
