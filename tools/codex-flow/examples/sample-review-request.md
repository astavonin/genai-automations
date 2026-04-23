# Review Request — Greeting Helper Smoke Test

**Repository:** `/tmp/codex-flow-review-smoke-repo`
**Branch:** `review-smoke`
**Review Scope:** `working-tree`
**Output File:** `planning/reviews/greeting-helper-review.md`
**Date:** `2026-04-23`

---

## Context

This is a narrow smoke-test review request for `codex-flow review`.

The repository contains a small Python module with a recent uncommitted change that adds a greeting
helper and its tests. The review should focus on correctness and regression risk for that change.

---

## Requirements

- Add a function `format_greeting(name: str) -> str`
- Return `Hello, <name>!`
- Strip leading and trailing whitespace from the input name before formatting
- Preserve the existing `ping()` behavior

---

## Constraints

- Do not change project structure
- Do not add third-party dependencies
- Only the requested review output file may be written by the workflow

---

## Evidence

```bash
pytest
```

---

## Review Focus

- correctness
- regression risk
- test coverage
