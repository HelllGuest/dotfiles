---
name: security-review
description: Review a diff or codebase area for common vulnerability classes. Use when the user says "security" or asks for a security review.
---

# Security review

Review the relevant diff or files for:
* SQL / NoSQL injection
* XSS
* Command injection
* Unsafe file access (path traversal, unrestricted upload)
* Authentication and authorization gaps
* Secret leakage (hardcoded keys, secrets in logs/errors)
* Unsafe logging (PII, tokens, passwords)
* Unsafe shell execution (unsanitized input into subprocess/exec)

Report by severity (critical / high / medium / low), with file:line and a
concrete fix for each finding, not a generic "sanitize input" note.
