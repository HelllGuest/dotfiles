---
name: double-check
description: Independent adversarial review of the previous work, assuming mistakes exist. Use when the user says "double check" after a change has been made.
---

# Double check

Independent review of the previous work. **Assume mistakes exist** — find them;
do not confirm the work is fine by default.

## Required output format

1. Same PASS / FAIL / SKIPPED checklist as `verify` where applicable.
2. **Findings** list (required even if empty): each finding with why it matters.
   Do **not** silently patch — list and stop unless the user asks to fix.

## Hunt specifically for
- Logic bugs
- Missed files (should have been touched but weren't)
- Forgotten or incorrect imports
- API misuse (wrong signature, deprecated calls, wrong error handling)
- Incorrect assumptions
- Edge cases (empty/null, concurrency, large input)
- Race conditions
- Error handling gaps (swallowed errors, missing rollback)
- Missing tests for new behavior
