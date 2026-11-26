---
name: optimize
description: Improve performance, memory, readability, and maintainability without changing external behavior. Use when the user says "optimize" or asks for performance improvements.
---

# Optimize

Improve performance, memory, readability, or maintainability **without**
changing external behavior or API contracts.

## Workflow

1. Identify bottlenecks, redundant work, excess allocations, or poor structure.
2. Prefer existing tests or a quick regression check before risky changes; do
   not invent large speculative suites.
3. Apply targeted optimizations while preserving behavior.
4. Run affected tests / verify; report measurable or structured results.
