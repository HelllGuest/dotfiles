---
name: refactor
description: Clean the codebase of dead code, unused files, duplicate implementations, and obsolete artifacts without changing behavior. Use when the user says "refactor" or asks for a cleanup pass.
---

# Refactor (cleanup, not redesign)

Clean without changing behavior. If a removal would change behavior, **stop and
ask** instead of guessing.

## Remove
* Unused code, functions, and variables
* Unused files and assets
* Dead code paths (unreachable branches; flags stuck on one value)
* Duplicate implementations: keep one, update call sites
* Commented-out code
* Obsolete tests (for code that no longer exists)
* Obsolete configs

## After cleanup
1. Run the full `verify` checklist.
2. Report what was removed and why (short list).
