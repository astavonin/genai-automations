# Review Request — <Feature / Fix Name>

**Repository:** `/absolute/path/to/repo`
**Branch:** `feature/<branch-name>`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/<epic-slug>/reviews/<name>-codex-review.md`  *(MR-scoped)*  or  `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/codex-review.md`  *(issue-scoped)*
**Date:** YYYY-MM-DD

---

## Context

Brief description of what was changed and why.

**Design doc:** `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/design.md` *(if applicable)*

---

## Requirements

What the code was supposed to implement:
- ...

---

## Constraints

What must not change:
- ...

---

## Evidence

Verification run before this review.
**This section MUST contain a non-empty fenced code block — codex-flow will reject the request otherwise.**
For design-only reviews with no commands to run, use the placeholder below as-is.

```bash
# commands + exit codes
# (design-only review: no implementation to verify)
```

---

## Review Focus

Priority quality attributes (used to steer agent focus among the 8 attributes):
- correctness
- regression risk

> **Note:** Test Quality Pass and Cross-Site Consistency Pass are mandatory for all code reviews and run regardless of what is listed here. Review Focus does not opt out of either pass.

---

## Exclusions

- `path/to/file` — reason

*(Remove if nothing to exclude)*
