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
- **Class:** `CI` | `TEST` | `PRODUCT-NEW` | `PRODUCT-SHIPPED` — the **higher** of the design doc header's `**Class:**` value and `analysis.md` → `## Change Class` (either alone where only one is set; `PRODUCT-NEW` where neither is), with the calibration table pasted beneath this section.
- Name the **file and symbol** for every finding (`src/pipeline/pipeline.cc` → `process_frame()`), or a quoted distinctive token where no symbol exists. A `file:line` may accompany the symbol but must never be the only locator, and no finding may reference a planning document by line — use `§N.M` and finding IDs.
- This review runs with `--ignore-user-config --ignore-rules`, so the rule reaches it only through this line and the bundled `codex_flow/resources/skills/reviewer/SKILL.md`; editing `platforms/codex/` does not reach a review run.
- The artifact's relation to pending work has three cases, not two — grade by this table, not by a marked/unmarked binary:

| Relation | Correct treatment |
|---|---|
| Describes the target state, tree differs, divergence marked where it applies | Not a finding |
| Describes the target state, tree differs, divergence unmarked | Finding |
| Describes something the pending work **deletes** | Do not teach it as part of the model — the rule is moot, not merely unmarked |

**Fill the `**Class:**` bullet above from `~/.claude/skills/domains/quality-attributes/references/review-checklist.md` → Change Class Calibration, never from this template's placeholder.** Paste the table fresh rather than reusing an old copy — this review runs with `--ignore-user-config --ignore-rules`, so this pasted copy is the only calibration Codex ever reads. Leaving the alternation unresolved (the literal `CI | TEST | PRODUCT-NEW | PRODUCT-SHIPPED`) is read as undeclared, not as a declared `CI` — the bundled reviewer skill says so, and the fallback line below repeats it. Resolve it anyway: an undeclared class grades every compatibility finding at `PRODUCT-SHIPPED`.

~~~markdown
# (paste the Change Class Calibration table here)
~~~

An absent or unresolved `**Class:**` value means the review is uncalibrated: grade as `PRODUCT-NEW`, with the pasted table's `PRODUCT-NEW` row applying its defaulted-class clause.

---

## Scheduled Deletions

Every entity the design schedules for removal — enum entries, config keys, files, symbols — one per line, or the literal line `No deletions are scheduled by this design.` when it schedules none. Codex receives only this document, so an omitted section reads as "nothing is being deleted" and the third row of the Constraints relation table above becomes unreachable.

**Fill this from the design's ticket table, never from this template's placeholder.** A deletion ticket is one that removes rather than adds; read the table for them rather than assuming the design only adds. Where there is no design doc, no ticket table, or no deletions — and for an external MR, where none of the three exists — write the no-op line with the reason on the same line after a ` — ` suffix (`No deletions are scheduled by this design. — external MR, no design doc`). The absence is only defensible when the reason travels with it, the same rule the ledger section below states.

~~~markdown
# (paste the list here, or the no-op line stated above — do not leave this fence as-is)
~~~

Flag any listed entity that the reviewed artifact presents as a live part of the model.

---

## Observed-Failure Ledger

Contents of `<issue-folder>/observed-failures.md`, pasted verbatim — or the literal line `No ledger exists for this work.` when there is none, or `No ledger exists for this work — external MR.` for an MR we do not own. Codex receives only this document, so without this section it cannot distinguish an unguarded fix from a correctly waived one, and will flag a user-approved waiver as a missing test.

**Fill this from the issue folder, never from this template's placeholder.** Run `ls <issue-folder>/observed-failures.md` before writing the section — the no-ledger line copied out of the boilerplate has twice reached a review whose subject carried recorded failures, and both times the reviewer raised it as High. When the folder genuinely has no ledger but a sibling folder does, or a known defect is out of scope, say so on the same line after the ` — ` suffix: the absence is only defensible when the reason travels with it.

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
