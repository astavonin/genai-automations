# Design — Add Greeting Helper

**Goal:** `codex-flow-smoke-test`
**Milestone:** `milestone-00-smoke-test` · `%0`
**Feature:** `#0`
**Branch:** `feature/codex-flow-smoke-test`
**Status:** Draft
**Revision:** 1

---

## 1. Problem Statement

The test repository needs a very small implementation task that exercises `codex-flow implement`
without requiring a large code change or broad repo context.

---

## 2. Goals and Non-Goals

### Goals
- Add one small Python function.
- Add or update one focused test.
- Keep the change easy to inspect in a separate Codex session.

### Non-Goals
- No refactor.
- No CLI redesign.
- No new dependencies.

---

## 3. Implementation Context

**Repository:** `/tmp/codex-flow-smoke-repo`

**Requirements:**
- Add a function `format_greeting(name: str) -> str`
- Return `Hello, <name>!`
- Strip leading and trailing whitespace from the input name before formatting

**Constraints:**
- Keep the existing project structure unchanged
- Do not add third-party dependencies
- Only touch files needed for this feature and its test

**Verification:**

*Extract from the project's README or CLAUDE.md. Must cover all three workflows.*

```bash
# Build / compile
python -m compileall src tests

# Test
pytest

# Debug / run
python -m pytest -q
```

**Context Files:**
- `src/example.py`
- `tests/test_example.py`

---

## 4. Architecture Overview

No architectural change. This is a narrow behavior addition intended only to validate the
external-input implementation workflow.

---

## 5. Detailed Design

Add a small pure function in the main module. Tests cover the expected output plus whitespace
trimming without changing package boundaries or introducing new dependencies.

---

## 6. Trade-offs and Alternatives

### Option A — Add a pure helper function
**Pros:** Small scope, easy to test, low regression risk.
**Cons:** Only validates a narrow slice of the workflow.

### Option B — Add a CLI feature
**Pros:** Exercises more behavior.
**Cons:** More setup, more chances for unrelated failure.

**Decision:** Chose A because this is a workflow smoke test, not a product feature.

---

## 7. Open Questions

- [ ] Update `Context Files` if the test repository uses different paths.
