# Review Request — <Feature / Fix Name>

**Repository:** `/absolute/path/to/repo`
**Branch:** `feature/<branch-name>`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/<name>-codex-review.md`
**Date:** YYYY-MM-DD

---

## Context

Brief description of what was changed and why.

**Design doc:** `planning/<goal>/milestone-XX/design/<feature>-design.md` *(if applicable)*

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

Priority quality attributes:
- correctness
- regression risk

---

## Exclusions

- `path/to/file` — reason

*(Remove if nothing to exclude)*
