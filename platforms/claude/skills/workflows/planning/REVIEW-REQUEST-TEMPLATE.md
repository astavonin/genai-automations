# Review Request — <Feature / Fix Name>

**Repository:** `/absolute/path/to/repo`
**Branch:** `feature/<branch-name>`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/<epic-slug>/reviews/<name>-codex-review.md`  *(MR-scoped)*  or  `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/codex-review.md`  *(issue-scoped)*
**Date:** YYYY-MM-DD

`Output File` is resolved against `Repository` and must land inside it — `codex_flow/contracts.py` → `output_path` rejects anything that escapes the repo root, including an absolute path elsewhere or a `../` prefix. When the review targets a companion repo, `Repository` is still the repo whose `planning/` receives the output, never the code repo being read.

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
- Name the **file and symbol** for every finding (`src/pipeline/pipeline.cc` → `process_frame()`), or a quoted distinctive token where no symbol exists. A `file:line` may accompany the symbol but must never be the only locator, and no finding may reference a planning document by line — use `§N.M` and finding IDs.
- This review runs with `--ignore-user-config --ignore-rules`, so the rule reaches it only through this line and the bundled `codex_flow/resources/skills/reviewer/SKILL.md`; editing `platforms/codex/` does not reach a review run.

---

## Observed-Failure Ledger

Contents of `<issue-folder>/observed-failures.md`, pasted verbatim — or the literal line `No ledger exists for this work.` when there is none, or `No ledger exists for this work — external MR.` for an MR we do not own. Codex receives only this document, so without this section it cannot distinguish an unguarded fix from a correctly waived one, and will flag a user-approved waiver as a missing test.

~~~markdown
# (paste ledger here, or: No ledger exists for this work.)
~~~

An entry whose `**Status:**` is `covered`, `waived`, or `out-of-scope` is resolved. `open` is not. A recorded, user-approved waiver is a valid resolution — do not report it as a missing test. The outer fence uses `~~~` so a pasted ledger containing its own ``` blocks does not terminate it early.

---

## Evidence

Verification run before this review. **This section MUST contain a non-empty fenced code block — codex-flow will reject the request otherwise.** For design-only reviews with no commands to run, use the placeholder below as-is.

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
