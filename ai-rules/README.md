# ai-rules: one config for Cursor, Antigravity, Kiro, and Claude Code

## Why this works

* **`AGENTS.md`**: shared constitution (rules + command dictionary). Read by
  Cursor, Antigravity, Kiro, and (via bridge) Claude Code.
* **`skills/*/SKILL.md`**: Agent Skills for **Claude Code** and **Kiro**.
  Cursor / Antigravity use the same procedures from AGENTS.md Commands when you
  say `verify` / `double check` / etc. in chat.
* **`bin/agentsync`**: wire a project (`AGENTS.md`, `CLAUDE.md` → `@AGENTS.md`,
  and `.cursor/rules` pointer when the project has `.git` or `.cursor`).
* **`git-hooks/`**: global hooks via `core.hooksPath` (strip AI trailers,
  Conventional Commits, branch-name prefill, pre-push checks).

## Layout

```text
ai-rules/
├── AGENTS.md
├── bin/agentsync
├── lib/vscode-settings-merge.sh
├── skills/{verify,double-check,refactor,test,commit,security-review,rephrase,optimize,explain,docs,debug}/SKILL.md
├── cursor-mdc/00-agents-pointer.mdc
├── git-hooks/{commit-msg,prepare-commit-msg,pre-commit,pre-push}
├── claude-settings.json          # create/merge into ~/.claude/settings.json
├── vscode-family-telemetry.json  # create/merge into VS Code family settings.json
├── install.sh
└── README.md
```

## Install

From this tree (usually `~/dotfiles/ai-rules` or a clone):

```bash
chmod +x install.sh bin/agentsync
./install.sh                 # syncs to ~/dev/ai-rules, links skills, merges settings
# optional: ./install.sh /other/kit/path
```

Re-run anytime. Prefer **rsync** (`rsync -a --delete --exclude '.git/'
--exclude '*.bak'`). Without rsync, install uses `cp -a` plus orphan cleanup
with the **same excludes** (does not delete destination `*.bak` or `.git/`;
does remove other orphan files and empty dirs).

Skills: if `~/.claude/skills` or `~/.kiro/skills` is missing, symlink the whole
kit `skills/` dir; if it is already a symlink, retarget it; if it is a real
directory, add per-skill symlinks (existing non-symlink entries such as
`find-skills` / `caveman` are left alone). Cursor's mixed
`~/.cursor/skills` tree gets the kit skill names force-retargeted to
`~/dev/ai-rules/skills/<name>` (other third-party skills stay). When run via
`scripts/sync-agent-skills.sh`, `~/.claude/skills` and `~/.kiro/skills` are
ensured to be real directories first so mirroring the full `~/.agents/skills`
hub across Claude, Cursor, OpenCode, Kimi, Gemini CLI, Antigravity, and Kiro
never writes hub symlinks back into `~/dev/ai-rules/skills`.

Claude settings: if `~/.claude/settings.json` is missing, copy the kit file;
else jq-merge so kit wins on `includeCoAuthoredBy` and kit `env.*` keys, without
removing user hooks/plugins/theme. VS Code family: create or jq-merge
`vscode-family-telemetry.json` into common `User/settings.json` paths (Cursor,
Antigravity, Kiro, Code, VSCodium, plus stow vscode settings when that path
exists) via `lib/vscode-settings-merge.sh`, preserving symlinks (such as GNU
Stow links) and stripping `cursor.general.*` keys from non-Cursor editors. Kiro
CLI: `kiro-cli settings telemetry.enabled false` when `kiro-cli` is on PATH.

Canonical live kit after install: **`~/dev/ai-rules`** (override install target
with `./install.sh /path`). Edit there, or edit this repo's `ai-rules/` and
re-run `install.sh` to publish. `agentsync` resolves the kit via
`$AI_RULES_HOME` or default `~/dev/ai-rules`.

## Day to day

```bash
# After editing this tree (or ~/dev/ai-rules), publish + refresh IDE skills:
./install.sh
agentsync ~/Projects/my-app    # or: agentsync .   inside a repo
```

`docs` skill / AGENTS `docs` command: keep one canonical howto (usually the
project README); link from other docs; delete obsolete sections.

In any IDE / CLI chat:

| Say | Means |
|-----|--------|
| `verify` | Checklist PASS/FAIL/SKIPPED on session changes; no silent edits |
| `double check` | Adversarial review; findings only |
| `refactor` | Dead code/files cleanup; no behavior change |
| `test` | Run real project tests for last change; PASS/FAIL/SKIPPED per layer |
| `debug` | Reproduce, isolate root cause, minimal fix, then verify |
| `optimize` | Improve performance/memory/readability/maintainability; no behavior change |
| `explain` | Explain the last change or a named target |
| `docs` | Update README/inline docs only when wrong vs code |
| `security` | Diff security review |
| `commit` | Conventional Commit message; run git only if explicitly asked |
| `rephrase` | Drop em/en dashes and clause hyphens; keep hyphens inside tokens |

## Tool matrix

| Tool | Rules | Skills | Telemetry |
|------|-------|--------|-----------|
| Cursor GUI / `agent` | `AGENTS.md` + `.cursor/rules` pointer (via `agentsync`) | via Commands in AGENTS | create/merge vscode-family JSON |
| Antigravity GUI / `agy` | `AGENTS.md` | via Commands in AGENTS | create/merge vscode-family JSON |
| Kiro GUI / `kiro-cli` | `AGENTS.md` | `~/.kiro/skills` | `kiro-cli` telemetry off + JSON merge |
| Claude CLI | `CLAUDE.md` → `@AGENTS.md` | `~/.claude/skills` | create/merge kit `env` + `includeCoAuthoredBy: false` |

## Notes

* Global `core.hooksPath` **replaces** repo `.git/hooks` (tools that only
  install into `.git/hooks`, including typical husky setups, are skipped).
  Kit hooks: `commit-msg` (strip AI trailers, then Conventional Commits;
  skips format check for Merge/Revert/fixup!/squash! and empty messages),
  `prepare-commit-msg` (branch-name prefill; ignores text below
  `commit.verbose` scissors),
  `pre-commit` (if `stow/` + `all_stow_files.txt` exist **in `~/dotfiles` or a
  trusted repo**: refresh or fail when inventory is stale vs
  `scripts/list-stow-files.sh`),
  `pre-push` (**trusted repos only**; only if `package.json` or `pnpm-workspace.yaml` exists: with
  `tsconfig.json`, hard-fail `tsc` when a `"tsc"` script exists via pnpm/npm;
  else soft `pnpm exec tsc --noEmit || true` when pnpm is present; hard-fail
  lint when a `"lint"` script exists; with `Cargo.toml`: `cargo check` +
  clippy `-D warnings`; with `go.mod`: `go vet`; with `pyproject.toml` or
  `setup.py` and `ruff` on PATH: `ruff check`).
  Unset: `git config --global --unset core.hooksPath`
* **Trusted repos:** these hooks are global, and `pre-push` / `pre-commit` run
  repo-defined code (npm/pnpm scripts, cargo build scripts, the repo's
  `list-stow-files.sh`). They only do so where you opted in:
  `git config --local hooks.trusted true` (local config is never cloned, so an
  untrusted repo cannot set it). Elsewhere `pre-push` prints a skip note.
  After updating the kit, re-run `bash ai-rules/install.sh` to refresh the
  installed copy.
* Prefer granular Claude env vars (in kit) over umbrella
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (breaks auto-update).
* Cursor Privacy Mode is not the same as crash reporting; the kit sets
  `crashReporting.enabled: false` and related telemetry keys off in
  `vscode-family-telemetry.json`.
* `agentsync` prefers in-repo `./ai-rules/AGENTS.md` when present; otherwise
  links `$AI_RULES_HOME/AGENTS.md` (default `~/dev/ai-rules/AGENTS.md`).
  For an existing `CLAUDE.md` that is not a symlink and does not start with
  `@AGENTS.md`, it warns and does not overwrite.
