---
name: verify-docs
description: Verify design document integrity and consistency after Q&A resolution or review finding fixes. Checks for stale TBDs, naming inconsistencies, cross-reference drift, and resolved items still marked open.
---

# Doc Verification Command

Run after resolving design review findings (Q&A phase) or after applying code review finding fixes that touch documentation. Catches drift introduced when multiple docs are updated in sequence.

## When to Run

- After completing a Q&A resolution session for a `/review-design` CHANGES REQUESTED result — before requesting re-review
- After applying code review findings that touch `docs/` or `planning/**/issues/*/` — before requesting re-review
- Any time multiple design docs are updated in sequence and cross-reference each other

## Inputs

Caller provides (in the `/verify-docs` invocation or as context):
- The list of design/doc files modified during this session
- The list of resolved finding IDs (C1, H1, H2 … etc.) and their resolution summaries

If no list is given, default to scanning all files modified in the current branch vs `master`:
```bash
git diff --name-only origin/master | grep -E '\.md$'
```

## Actions

### Step 1 — Collect modified files

```bash
git diff --name-only origin/master | grep -E '\.md$'
```

Read each file. Focus on:
- `docs/` — architecture / user-facing docs
- `planning/**/issues/*/` — design documents and review reports (check status marker consistency)

### Step 2 — Run consistency sweep

Use **architecture-research-planner agent** to read all modified files together and check:

**Stale placeholder scan:**
- Remaining `TBD`, `TODO`, `exact path TBD`, `TBD in #NNN` that the Q&A session was supposed to resolve
- `OPEN` status on Q&A / open-items table rows that were resolved in prose but not updated in their table cell
- **Review-process tracking artifacts** — inline `RESOLVED` markers (`**H1 RESOLVED — ...**`, `**L2 RESOLVED**`, `(M3 RESOLVED)`, `— M4 RESOLVED.`, `H6 RESOLVED block`, etc.) anywhere in design or user-facing docs. These are always blockers: resolution is tracked in the review report and review-request doc, not in design content. The architecture-research-planner must strip them when applying fixes.

**Terminology consistency:**
- Component names used consistently across all files (e.g., "Update Manager" vs bare "Manager" in a context where a "Build Manager" also exists — flag ambiguous unqualified uses)
- Mode/state names consistent across all docs (e.g., `partial-update`, `full-update`, `rollback`)
- Field names consistent in exact casing across all docs (e.g., `error_code`, `retry_count`, `is_complete`, etc.)

**Cross-reference integrity:**
- `§N.M` section references that point to renamed or moved sections
- `component-analysis.md §X` / `service-design.md §Y` / `docs/architecture.md §Z.W` cross-refs that no longer exist
- Finding IDs cited in resolution blocks that don't match the review report (e.g., "resolves C3" when the review labels a different finding as C3)

**Resolved-item consistency:**
- The review-request doc lists all resolved finding IDs with their resolution summaries — verify those summaries are plausible given the current doc content (no contradictions)
- Do NOT require RESOLVED markers in design docs — their absence is correct; their presence is a blocker (see stale placeholder scan above)

**Diagram / prose consistency:**
- Mermaid node labels that reference removed concepts or contradict updated prose
- Step sequences in diagrams that disagree with numbered step lists in the same or a related doc

### Step 3 — Report findings

Produce a compact report in the main conversation (not a file unless the user asks):

```
## Doc Verification Report

**Files checked:** N
**Issues found:** M

### Blockers (must fix before re-review)
- [file:section] description

### Warnings (should fix, low risk)
- [file:section] description

### Clean
- [file] — no issues
```

Blockers are items that would cause the next reviewer to raise a finding (stale TBD, unresolved OPEN row, diagram contradicts prose). Warnings are cosmetic or low-risk drift.

### Step 4 — Fix blockers

Fix blockers using **architecture-research-planner agent** (required for all `planning/**/issues/*/` edits per the standard rule). For `docs/` files, architecture-research-planner is also preferred. Propose warnings to the user — fix only if confirmed.

## Constraints

- Do NOT re-run the full `/review-design` consensus protocol — this is a targeted consistency sweep, not a new review cycle.
- Do NOT modify code files — doc verification only.
- Architecture-research-planner must be used for any design doc edits (`planning/**/issues/*/`). Never use Write/Edit tools directly on those files.
- When architecture-research-planner applies review-finding fixes, it must produce clean prose only — **never add `RESOLVED` markers, finding IDs, or review-cycle annotations** to design or user-facing docs. Resolution tracking belongs in the review report (`issues/*/design-review.md`) and the review-request doc, not in the design content itself.
