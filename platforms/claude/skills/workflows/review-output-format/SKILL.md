---
name: review-output-format
description: Shared fragment — markdown output format template for code review and fix review reports. Includes findings structure, Codex-Only, Reverified, Library Reuse, Test-coverage, Manual Pass, Assessment, and ID conventions. Not used for design reviews (different structure).
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, output, format, template]
---

# Review Output Format — Shared Fragment

Markdown report template for **code reviews** and **fix reviews**. Design reviews use a different template (see `review-design.md`).

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

## Codex-Only Findings

Findings raised by Codex that did not reach 2/3 Claude consensus. Include even if 0 — write "None."

- **X1** [severity] Description...

## Reverified Findings

Single-agent Claude findings and Codex-only findings that survived Step G reverification (≥1 of 2 verifiers confirmed). Include even if 0 — write "None."

- **V1** [severity] ✓ Reverified — Description...

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
**Location:** <file path and line range>
**Rationale:** <one sentence — what generic problem it solves>
**Reuse signal:** <list the subprojects or contexts that would benefit>
**Suggested home:** <proposed module/package path in the common library>
```

## Test-coverage Findings

<!-- Omit this section for fix reviews unless the fix touches test files -->

Findings from the Step F test-coverage agent not already present in the consensus section. Reviewers MUST check:
- **New code without dedicated test file** — flag as `High` if missing
- **Missing failure scenarios** — flag each uncovered failure mode separately
- **Vacuous assertions** — assertions that pass even when implementation is wrong
- **Name/assertion mismatch** — test name describes a scenario the assertions do not verify
- **Under-specified error assertions** — only asserts "an error occurred" without type/code/message

Severity guidance: `High` = security/data integrity/resource management; `Medium` = non-critical paths; `Low` = easy-to-add type/message checks.

- **T1** [severity] Description...

## Manual Pass Findings

<!-- Omit this section for fix reviews -->

Findings from the Step H manual passes (Cross-Site Consistency Pass and Test Quality Pass). Include even if 0 — write "None."

- **P1** [severity] Description...

## Recommendation

<rationale and required actions if not approved; reference findings by ID e.g. "Fix C1, H2 before proceeding">
```

## ID Conventions

IDs are prefixed by severity: `C` = Critical, `H` = High, `M` = Medium, `L` = Low. Number sequentially within each severity (`C1`, `C2`, `H1`, `H2`, `M1`, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment Criteria

- ✅ **Approve:** Zero Critical, zero High, and zero Medium findings
- ⚠️ **Request Changes:** One or more High or Medium findings — fix and re-review
- ❌ **Reject:** One or more Critical findings — redesign needed
