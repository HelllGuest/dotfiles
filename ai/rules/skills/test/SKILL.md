---
name: test
description: Run all relevant tests for the last change and confirm it works as expected, or recommend tests if none exist. Use when the user says "test" or asks to confirm a change works.
---

# Test

Confirm the last change works using the project's real tooling.

## Order
1. Discover commands from Makefile / package.json / pyproject.toml / Cargo.toml /
   justfile; do not guess a generic runner.
2. Run: unit → integration → build → typecheck → lint (skip with SKIPPED + reason
   if that layer does not exist).
3. Report each layer as PASS / FAIL / SKIPPED.

## If no tests cover the change
Say so plainly. Recommend concrete cases (happy path + main edge cases). Do
**not** invent confidence or write large speculative suites unless asked.

## Failures
Quote the actual error output (shortest decisive lines), not a paraphrase.
