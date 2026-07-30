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
- **The resolved `<issue-folder>` path** — required. Step 1 and the Step 2 scan both need it, and neither can discover planning docs without it.
- The list of design/doc files modified during this session
- The list of resolved finding IDs (C1, H1, H2 … etc.) and their resolution summaries

If no file list is given, discover them per Step 1 — do not fall back to a bare `git diff` against a guessed branch name. Step 1 explains why that yields nothing for planning docs.

## Actions

### Step 1 — Collect modified files

**`git diff` does not discover planning docs.** A global gitignore entry (`planning/*`) leaves them untracked in every repo, so the command below returns nothing for `design.md`, `analysis.md`, or any review report. A run that relies on it reports `Files checked: 0 — Clean`, and a silently-green gate is worse than no gate.

Resolve the issue folder directly and enumerate its `.md` files:

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

```bash
ISSUE_FOLDER=""   # <-- the resolved path
ls "${ISSUE_FOLDER:?resolve the issue folder first}"/*.md
```

Then add tracked docs outside `planning/`, where `git diff` does work. Resolve the default branch rather than hardcoding `master` — repos using `main` make a hardcoded `origin/master` exit non-zero and yield nothing, which is silently empty in exactly the same way:

```bash
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
  || BASE=$(git remote show origin | sed -n 's/.*HEAD branch: /origin\//p')
git diff --name-only "${BASE:?could not resolve the default branch}" | grep -E '\.md$'
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

**Citation form scan.** The scan lists **candidates**; you decide. It resolves the two exemptions it can see mechanically (fenced blocks, hash-pinned permalinks) and cannot see the rest, so every hit is triaged against the full exemption list in `~/.claude/CLAUDE.md` → Markdown Writing → code references before it becomes a blocker.

What it looks for:
- **Unpinned source references** — a `path:NN` or `path:NN-MM` locator with no leading commit hash. Valid forms are file + symbol, or the pinned `<short-hash>:path:line`.
- **Planning-document references** — `design.md:682-690`, `analysis.md:69`, `code-review.md:65`. Flagged even when hash-prefixed: planning docs are untracked, so no commit pins them and the prefix is decoration. Cite `§N.M` and finding IDs.

```bash
# Resolved issue folder from Step 1.
# Tests: tests/verify-citation-scan.sh in the genai-automations repo.
bash ~/.claude/scripts/citation-scan.sh "<issue-folder>"
```

**Exit contract.** `0` means the scan ran — read its output. Any non-zero exit is a **blocker**, not a clean result: the script prints a `BLOCKER:` line for an unresolved path, a placeholder, a folder with no `.md` files, or a missing or failing `awk`. Exit `127` means the script is not installed — `sync-configs.sh install` copies `platforms/claude/scripts/` into `~/.claude/scripts/`, and until it has run this gate cannot execute. Do not record a `Clean` result in Step 3 for any non-zero exit.

**Triage each hit by hand — the scan cannot see these:** a hit is **not** a defect when the citation names a symbol and the line number merely accompanies it, nor when it is an annotation form permitted by `BRIEF-TEMPLATE.md` §7. A hit **is** a defect when the line number stands alone as the only locator. Article-review findings are not exempt: they cite companion-repo code by the pinned form, so an unpinned companion-repo line in `article-review.md` is a blocker.

Two known limits, so a clean result is not over-read. A word of seven-to-forty hex characters (`defaced:src/x.cc:88`) reads as a hash and passes — the scan never contacts git, so pushed-ness is unverified. And `.md` targets outside `planning/` (a real source file named `README.md:12`) report as planning-doc refs.

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
