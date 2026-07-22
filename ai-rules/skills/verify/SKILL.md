---
name: verify
description: Review every file modified in this session for build/test/lint correctness, regressions, dead code, and security issues, without changing anything. Use when the user says "verify" or asks to check recent work before moving on.
---

# Verify

Review every file modified in this session (git status + conversation edits).
Do **not** modify code unless the user explicitly asks you to fix findings.

## Required output format

For each item below, one line:

```text
PASS | FAIL | SKIPPED (reason): <item>
```

Never say "looks good" without this checklist. Mark anything you could not run
as SKIPPED with a reason; never invent confidence.

## Checklist
1. Build / compile
2. Typecheck (if the project has one)
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

End with a short Findings section only if any FAIL items exist.
