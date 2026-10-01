---
name: review-output-format
description: Shared fragment — markdown output format template for code review and fix review reports. Includes findings structure, Reverified, Library Reuse, Test-coverage, Manual Pass, Assessment, and ID conventions. Codex-only findings route through Step G in every review type this protocol covers and land in Reverified (there is no separate Codex-Only section). Not used for design reviews (different structure).
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, output, format, template]
---

# Review Output Format — Shared Fragment

Markdown report template for **code reviews** and **fix reviews**. Design and spec reviews use their own templates (see `review-design.md` and `review-spec.md`).

**`## Assessment Criteria` below is the exception — it is the canonical approval bar for every review type**, including the design, spec and article reviews whose report templates live elsewhere. Those commands restate it; this is the copy to edit.

## Caller Must Specify

- **`review_type`** — `Code Review` or `Fix Review` (used as the H1 title)
- **`fix_review_extras`** — `yes` for fix review (adds `**Fix:**` and `**Problem:**` header fields); `no` for code review

## Report Template

```markdown
# <review_type>

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature / PR title>
<!-- Fix review only: -->
**Fix:** <one-line description of what was fixed>
**Problem:** <what was broken>
<!-- End fix review only -->
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject
**Codex:** ✓ ran | ✗ not run — <reason if skipped>
**Step G:** <N> eligible → <C> confirmed, <R> refuted, <U> unparseable | ✗ not run — <reason if skipped>
**Class:** <value> (declared | defaulted)

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...
  **Required test:** <what input triggers the bug and what the test asserts> *(only for behavioral bugs)*

### High
- **H1** [attribute] Description...
  **Required test:** <description> *(only for behavioral bugs)*

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Reverified Findings

Single-agent Claude findings and Codex-only findings that survived Step G adversarial reverification (both verifiers returned `VERDICT: CONFIRMED`; any REFUTED or unparseable-after-retry is discarded — the latter with a warning to the main conversation). Include even if 0 — write "None." This section is emitted by code, fix, and MR reviews. Design and spec reviews also run Step G and carry an equivalent section — see the templates in `~/.claude/commands/review-design.md` and `~/.claude/commands/review-spec.md`, each authoritative for its own report shape.

- **V1** [severity] [Reverified] Description...

The `[Reverified]` prefix at the start of the description is required so downstream consumers (MR YAML posting, code review report readers, GitLab comment readers who see the finding stripped from its section) can distinguish reverified findings from consensus findings without relying on section membership. Section membership alone is not sufficient because the MR YAML output flattens all findings into a single list.

## Library Reuse Findings

<!-- Omit this section and the next for fix reviews -->

Findings where new code duplicates functionality from the project's own common/utility modules or from available ecosystem libraries. Reviewers MUST check:

- **Project-internal duplication** — new functions/classes that replicate logic already present in the project's shared utilities, base classes, or helper modules. Flag as `High` if the duplicated code handles correctness-critical logic (parsing, serialization, crypto, error propagation).
- **Ecosystem library substitution** — custom implementations of functionality covered by standard or widely-adopted libraries. Flag as `Medium` unless security-sensitive, then `High`.
- **Vendored or pinned library ignored** — the project already vendors or pins a library that covers the use case but the new code does not use it.

Severity guidance:
- `High` — duplication in security, crypto, parsing, or data-integrity paths; or ignoring an already-vendored library
- `Medium` — general algorithmic duplication that a standard library covers; minor helper reimplementation
- `Low` — style-level preference

- **R1** [severity] Description...

## Common Library Promotion Candidates

<!-- Omit this section for fix reviews. Only include when a genuine candidate is found — do NOT add as a placeholder or write "None." -->

A candidate qualifies when ALL are true: domain-neutral, self-contained, stable interface, broadly applicable (≥2 other subprojects). For each genuine candidate:

```
**Candidate:** <function or class name>
**Location:** <file → symbol; a line range only pinned as `<short-hash>:path:line`>
**Rationale:** <one sentence — what generic problem it solves>
**Reuse signal:** <list the subprojects or contexts that would benefit>
**Suggested home:** <proposed module/package path in the common library>
```

## Test-coverage Findings

<!-- Always include for fix reviews — this is where the observed-failure regression gate reports. Write "None." if Step F returned nothing. Omitting it because the fix touched no test file would discard the exact finding the gate exists to produce. -->

Findings from the Step F test-coverage agent not already present in the consensus section. Reviewers MUST check:
- **New code without dedicated test file** — flag as `High` if missing
- **Missing failure scenarios** — flag each uncovered failure mode separately
- **Vacuous assertions** — assertions that pass even when implementation is wrong
- **Name/assertion mismatch** — test name describes a scenario the assertions do not verify
- **Under-specified error assertions** — only asserts "an error occurred" without type/code/message

Severity guidance: `High` = security/data integrity/resource management; `Medium` = non-critical paths; `Low` = easy-to-add type/message checks.

- **T1** [severity] Description...

## Manual Pass Findings

<!-- Always include, including for fix reviews — they run Steps B–H. -->

Findings from the Step H manual passes (Cross-Site Consistency Pass and Test Quality Pass). Include even if 0 — write "None."

- **P1** [severity] Description...

## Recommendation

<rationale and required actions if not approved; reference findings by ID e.g. "Fix C1, H2 before proceeding">
```

**The Step G report line's alternation is shared verbatim across three sites** — this template, `review-design.md`, and `review-spec.md` — and pinned byte-for-byte. A file introducing that line must carry the full `<N> eligible → <C> confirmed, <R> refuted, <U> unparseable | ✗ not run — <reason if skipped>` alternation and be added to `stepg_sites` in `tests/verify-config-consistency.sh`; a copy carrying only one half of the alternation is treated as an uncontrolled fourth site by that scan. A bare field with no alternation text at all, reading only `✓ ran` with no eligible/confirmed/refuted/unparseable counts, resolves to neither half and is invisible to it — catching that is a review responsibility, not this guard's.

## ID Conventions

IDs are prefixed by severity: `C` = Critical, `H` = High, `M` = Medium, `L` = Low. Number sequentially within each severity (`C1`, `C2`, `H1`, `H2`, `M1`, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment Criteria

- ✅ **Approve:** Zero Critical and zero High findings, **and every Medium fixed**
- ⚠️ **Request Changes:** One or more Critical or High findings — fix and re-review
- ❌ **Reject:** One or more Critical findings — redesign needed

**A Medium costs a fix, not a round.** Only a Critical or a High sends the work back through another review. Where a review returns zero Critical and zero High with Mediums open, those Mediums are fixed and the approval follows — no re-review of the Medium fixes. This is what the change buys: the fix work is unchanged, the extra review round is not spent.

**Name every Medium fixed on that path** in the conversational report, since no review pass ever graded those fixes. An approval reached this way rests on the fixes being small and mechanically verified — the build and test suites still run — not on a reviewer having read them.

**Scope of this criterion:** the **initial** review pass of code, design, spec and article reviews, and of the three `*-fix-loop` commands that wrap them. Three callers are out of scope and stay out:

- **Fix reviews keep their own bar** (`review-fix.md` → Assessment) — zero Critical and zero High, **Mediums uncounted**, with every observed-failure regression severity raised to High in compensation. That is a looser bar on Mediums and a stricter one on regressions, not this criterion.
- **`/review-mr` reviews merge requests we do not own** (`review-mr.md` → Step 6) — zero Critical and zero High, **Mediums uncounted**. There is no issue folder, no ledger and no fix loop, so a Medium gate would have no mechanism to satisfy.
- **`/review-iterate` runs one unconditional final sweep** (`review-iterate.md` → Key Constraints). A Medium sends work back through a review there, which this criterion does not permit — that divergence is known and tracked, not licensed.

**After the initial pass, the three fix loops diverge the same way.** Their three-branch routing sits at Step 1 only; a Step 3 re-review returning zero Critical and zero High with Mediums open matches the fragment's below-cap row and takes another full round. Known and tracked, not licensed — the same status as `/review-iterate`.
