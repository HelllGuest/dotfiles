---
name: rephrase
description: Rewrite prose to remove dash punctuation (em dash, en dash, clause-separating hyphen) and rephrase with periods, colons, or semicolons. Use when the user says "rephrase", "remove dashes", or asks to strip "-" from writing.
---

# Rephrase (no dash punctuation)

Rewrite the target text (chat reply, docs, comments, or files the user names)
so meaning stays the same without dash-as-punctuation.

## Remove
* Em dash (`—`) and en dash (`–`) used as clause breaks
* Spaced hyphen used as a pause (`word - word`)
* Title patterns like `Name — subtitle` (prefer `Name: subtitle`)
* Markdown list markers that are `-` when applying this style (prefer `*`)

## Keep
* Hyphens inside identifiers and tokens: paths, flags (`--force`), names
  (`Co-authored-by`, `double-check`), URLs, code, Conventional Commit scopes
* Arithmetic or range notation only when it is literal code or data

## How to rephrase
* Split into two sentences, or join with a colon / semicolon / comma
* Prefer direct verbs over parenthetical asides set off by dashes
* Checklist / status lines: use a colon
  (`PASS | FAIL | SKIPPED (reason): <item>`)

## Scope
* Default: the last assistant message or the files the user just pointed at
* If the user names paths, edit those files in place
* Do not change code logic; only prose, comments, and docs unless asked

## After
If files changed, briefly list what was rewritten. Do not commit unless asked.
