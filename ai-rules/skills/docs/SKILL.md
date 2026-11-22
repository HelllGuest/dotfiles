---
name: docs
description: Update README and inline documentation only when current docs are incomplete or outdated relative to code. Use when the user says "docs" or asks to update documentation.
---

# Docs

Update project documentation only when it is wrong or incomplete relative to
the code.

## Workflow

1. Inspect the affected code and existing docs (README, inline docs, API specs).
2. Update only what is inaccurate or missing; no fluff or redundant comments.
3. Prefer one canonical howto (usually README). Other docs link; do not fork
   the same procedure into multiple files.
4. Remove obsolete sections; do not keep long "historical only" dumps.
5. Verify formatting and links (`scripts/lint-docs.sh` when the project has it).
