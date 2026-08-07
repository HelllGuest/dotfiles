# AGENTS.md: shared rules for every coding agent

This file is the single source of truth for how any AI coding agent (Cursor,
Antigravity, Kiro, Claude Code, or anything else that reads AGENTS.md) should
behave in this repository. Projects usually link it from the kit
(`~/dev/ai-rules/AGENTS.md` or `./ai-rules/AGENTS.md`). Edit the kit copy, not
a per-project fork.

For Claude Code: also keep a project `CLAUDE.md` whose first line is
`@AGENTS.md` (or symlink `CLAUDE.md` → `AGENTS.md`). Claude prefers
`CLAUDE.md`; without that bridge, these rules are weaker in Claude sessions.

## Code quality
* Prefer readability over cleverness. No unnecessary abstractions.
* Reuse existing utilities before writing new ones. Never duplicate logic.
* Follow the project's existing style and naming conventions, not your defaults.
* Remove obsolete code immediately instead of leaving it "just in case."

## Error handling & robustness
* Handle errors explicitly at boundaries. Never suppress or swallow exceptions without logging or handling.
* Prefer typed/structured errors over generic error strings or any-type catches.
* Ensure resources (file handles, network sockets, database connections) are reliably cleaned up (RAII / try-finally).

## Testing best practices
* Write tests for behavior and public contracts, not implementation details.
* Keep unit tests isolated, fast, and deterministic; mock external network and I/O.
* Ensure tests clean up side effects and temporary files after completion.

## Security hardening
* Validate and sanitize all external inputs at system boundaries.
* Never log, store, or hardcode secrets, API keys, tokens, or PII.
* Avoid dangerous functions (e.g. unsafe string manipulation, raw shell execution without escaping).

## Shell / token hygiene
* Prefer `rtk <cmd>` for noisy CLI output when the project/dotfiles use RTK.
* Do not dump huge logs into chat; quote the shortest decisive lines.

## Before editing
Read and understand the existing architecture, patterns, dependencies, and
naming conventions in the affected area before writing any code. Do not start
editing on the first read.

## After every edit
Run, in order, and report anything you skipped and why:
1. Lint
2. Format
3. Compile / typecheck
4. Run affected tests
5. Search for regressions in dependent code
6. Check imports (no unused, no missing)
7. Check for dead code / unused variables introduced
8. Check for TODOs you introduced
9. Update documentation if behavior changed

## Never
* Never disable or skip a failing test to make a run pass.
* Never ignore compiler/linter warnings without flagging them explicitly.
* Never leave commented-out code, debug prints, or unused imports.
* Never create a duplicate helper/util that already exists.
* Never invent confidence when you could not run a check; mark it SKIPPED.

## Commands

These words, said in plain chat, mean the specific checklist below, not a
generic "sure, I'll look into it." Every agent must treat them as fixed
procedures. Required report format for `verify`, `double check`, and `test`:

```text
PASS | FAIL | SKIPPED (reason): <item>
```

Never reply "looks good" without the checklist. Scope equals files touched this
session (git status + conversation edits) unless the user widens scope.

### `verify`
Review every file modified in this session. Do **not** modify code unless
explicitly asked to fix findings.

Checklist (each line PASS / FAIL / SKIPPED):
1. Build / compile
2. Typecheck (if applicable)
3. Lint
4. Format
5. Affected tests
6. Imports (no unused, none missing)
7. Dead code / unused variables introduced
8. Regressions in dependents
9. Edge cases
10. Security (injection, secrets, unsafe I/O/shell)
11. Performance implications
12. Documentation still matches behavior

### `double check`
Independent review of the previous work. **Assume mistakes exist.** Look for:
logic bugs, missed files, wrong imports, API misuse, bad assumptions, edge
cases, races, error-handling gaps, missing tests. **Findings only**; no
silent fixes. Use the same PASS/FAIL/SKIPPED checklist where applicable, plus
a Findings list.

### `refactor`
Cleanup only: unused code/files, dead functions/vars, duplicates,
commented-out code, obsolete tests/configs/assets. **Do not change behavior.**
If behavior would change, stop and ask. After cleanup, run `verify`.

### `test`
Run tests relevant to the last change (unit → integration → build →
typecheck → lint) using the project's real commands (Makefile / package.json /
pyproject / cargo / justfile; do not guess). Report each layer as
PASS / FAIL / SKIPPED. No suite for the change → say so and recommend concrete
cases; do not invent confidence. Quote real failure output.

### `debug`
Reproduce the failure, isolate the root cause, apply a minimal fix, then
verify with affected tests and edge cases. Prefer root-cause fixes over
symptom patches.

### `optimize`
Improve performance, memory, readability, maintainability **without** changing
behavior. Prefer coverage or a quick regression check before risky changes; do
not invent large speculative suites.

### `explain`
Explain the last change or a named target. Do not narrate unrelated code.

### `docs`
Update README and inline docs only when current docs are wrong or incomplete
relative to the code. No fluff; verify links and formatting.

### `security`
Review the diff for SQL/XSS/command injection, unsafe file access, authz gaps,
secret leakage, unsafe logging, unsafe shell execution. Severity + file:line +
concrete fix.

### `commit`
Write a concise Conventional Commit message: `type(scope): summary`.
Run `git commit` / push / PR only when the user explicitly asked for that
action this turn; otherwise produce the message only. **Never** include AI
attribution trailers (see Git rules).

### `rephrase`
Rewrite prose to drop em dashes, en dashes, and clause-separating hyphens.
Prefer periods, colons, or semicolons; prefer `*` list markers over `-`.
Keep hyphens inside tokens (paths, flags, `Co-authored-by`, code). Default
scope is the last reply or files the user names; do not change code logic.

## Git rules (hard constraints, not preferences)
* Never commit, push, amend, force-push, or rewrite history automatically;
  only when explicitly told to for that specific action.
* Never open a PR automatically.
* **Never add AI attribution to commits or PRs**: no `Co-authored-by`, no
  `Generated by Claude / Cursor / Kiro / Antigravity / Copilot`, no
  "Generated with..." footer, in any form, ever, regardless of tool
  defaults. If a tool adds this automatically, strip it before presenting the
  commit message. A global `commit-msg` hook should also strip these.

## Review checklist (ask yourself before calling anything done)
Did I miss a file? Break a test? Leave dead code? Duplicate logic? Follow
project style? Verify imports and dependencies? Leave debug output? Update
docs? Could this be simpler? Did I mark every unchecked item SKIPPED?
