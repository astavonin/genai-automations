---
name: behavioral-bug-test
description: Shared fragment — defines when and how to include a Required test: line in review findings for incorrect runtime behavior. Used by review-code and review-fix.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, testing, behavioral]
---

# Behavioral Bug Test Requirement — Shared Fragment

## Rule

Any finding that identifies **incorrect runtime behavior** MUST include a `**Required test:**` line as part of the finding body. This applies regardless of severity.

**Incorrect runtime behavior** means the code:
- Produces wrong output or corrupts data (e.g., writes redirect response body into a download file)
- Silently accepts input that should be rejected (e.g., treats HTTP 3xx as success)
- Gets stuck or loops incorrectly (e.g., complete-file → 416 → infinite retry)
- Bypasses a stated security or correctness invariant

This does **NOT** apply to quality findings (naming, observability, performance, maintainability) that have no wrong-output consequence.

## Format

The `**Required test:**` line must describe the minimal test that would fail before the fix and pass after:
- What precondition / input triggers the bug
- What outcome the test asserts
