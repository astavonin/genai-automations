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

**Both scans in Step 2 take paths, so pass the `docs/` files explicitly** — `citation-scan.sh` takes a folder and `doc-metrics` takes files, and neither receives this list unless you hand it over. A `docs/` file edited by a code-review fix otherwise reaches the gate and is read by a human but measured by nothing:

```bash
# For each tracked .md outside planning/ from the list above:
doc-metrics docs/architecture.md                             # read the REGISTER line only
bash ~/.claude/scripts/citation-scan.sh docs                 # a folder, not a file
```

Their word counts have no targets — only a `design.md` does — so the register count and the citation form are what apply here.

### Step 2 — Run consistency sweep

Use **architecture-research-planner agent** to read all modified files together and check:

**Stale placeholder scan:**
- Remaining `TBD`, `TODO`, `exact path TBD`, `TBD in #NNN` that the Q&A session was supposed to resolve
- `OPEN` status on Q&A / open-items table rows that were resolved in prose but not updated in their table cell
- **A `## Writing Rules` heading in a `design.md`** — that section is guidance in `DESIGN-TEMPLATE.md` and was copied into the output instead of applied. Always a blocker; strip it.
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

**Prose metrics scan.** Resolve the planning-doc paths from `<issue-folder>` directly — never from a caller-supplied modified-file list, because `git diff` never lists a planning doc and a scan that inherits Step 1's git list scans nothing and reports `Clean`. Files under `docs/` are the exception: they are tracked, so they come from Step 1's git list and are passed explicitly (see the end of Step 1).

Two invocations, because the two counters have different scopes:

```bash
# Words, ceiling AND register. Only design.md is gated on length.
# `if` rather than `&&`: a bare && makes the whole line exit 1 when the file is absent,
# which the exit contract below then reads as a blocker. An issue folder legitimately has
# no design.md before Phase 2.
if [ -f "<issue-folder>/design.md" ]; then
    doc-metrics "<issue-folder>/design.md"
fi

# Register only. Named explicitly rather than globbed: a glob re-measures design.md and
# pulls in review reports, whose finding IDs and reviewer prose are not the fix agent's to
# rewrite. Skip any that is absent.
doc-metrics "<issue-folder>/analysis.md"
```

**Exit contract.** `0` means it ran — read the numbers. Any non-zero exit is a blocker, not a clean result: no file given, an unsubstituted placeholder, a path that is not a file or not readable, content that is not valid UTF-8, NUL bytes, setext headings, unclosed YAML frontmatter, or an unclosed fence. That last one matters most — everything after an unclosed fence is invisible to the count, so a zero register total there would be a lie. Exit `127` means the package is not installed — `pip install -e ./tools/docgate`. Exit status never signals "over ceiling" or "register hits found", so do not wire `&&` to it.

Read four things from the output. The first three are mechanical; only the fourth needs judgement:

- **`REGISTER: N hit(s)` must be 0 — blocks.** The tool names the section, the token, and a word window for each. The detector list is non-exhaustive, so zero clears the gate without proving the rule is met (see `~/.claude/agents/architecture-research-planner.md` → Prose Register). Two forms are exempt in the tool and will not appear: a fenced block, and a token wrapped in backticks or quotes, which is a mention rather than a use. Table cells and blockquotes are **not** exempt — a defensive sentence in a table cell is still defensive.
- **`CEILING: N slot(s) over ceiling` must be 0 — blocks, but only for the `design.md` run.** Ceilings exist for Detailed Design, Test Requirements, and the whole document; every other section reports a target and an advisory verdict with a `-` ceiling. A p75 ceiling on all eight sections blocked 23 of 39 existing documents, over half of them on a small section carrying no bloat. `over-target` is **not** a blocker: it means past the median, and is discharged by one line of justification naming what the extra words buy. Report the two or three largest overshoots, not every row. The tool prints the numbers; do not restate them here or anywhere else.
- **`COST:`, `MISSES:`, `FROM:`, `UNTAGGED:` — the design-field counters, read together, on the `design.md` run only.** They print unconditionally right after `UNSLOTTED:`, checking `**Cost:**`/`**Misses:**` presence in every `### Option` block of §7 and an inline `From:` tag on every §3 requirement bullet — presence only, never the figure or the miss itself.

  | Counter | Classification | Meaning |
  |---|---|---|
  | `COST:` | warning | an option block, or a whole Trade-offs section, has no `**Cost:**` line — the document predates the field |
  | `UNTAGGED:` | warning | a §3 requirement bullet has no `From:` tag, or a requirement group opener is malformed (wrong heading level, a bulleted label, or whitespace inside `**...**` around the label) — the document predates the field or the opener needs fixing |
  | `MISSES:` | blocker | a `**Cost:**` line has no `**Misses:**` value — the field exists and is incomplete |
  | `FROM:` | blocker | a `From:` tag is misplaced (line-start, or outside a requirement group) or carries an unrecognised value — the field exists and is wrong |

  A non-zero counter prints a detail block underneath naming the section, a locator, and a reason for each hit — report the two or three worst, not every row, same as the CEILING guidance above.
- **Cross-section duplication spot-check — warning.** Take the two highest-word sections and look for a fact stated in both. This is the weakest check here: it needs whole-document awareness that does not survive a fix round, so treat a clean result as unproven rather than as evidence there is no duplication. When you do find a duplicate, the fix is to delete the restatement and keep the statement at its point of decision — never to relocate it.

The tool owns the target and ceiling numbers and prints them per row, so there is no table to cross-check against and nothing to keep in step.

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

**Blockers are exactly this list** — do not derive the set from "what a reviewer would flag". The register and ceiling gates are kept out of reviewer prompts (review pressure drives growth), so no reviewer will ever raise them and a reviewer-anticipation test silently classifies them as non-blocking:

1. A non-zero exit from `citation-scan.sh` or `doc-metrics` — the run is not a measurement.
2. `REGISTER:` greater than 0, on `design.md` or `analysis.md`.
3. `CEILING:` greater than 0 **on the `design.md` run only** — no other file is gated on length.
4. In a design or user-facing doc: a `## Writing Rules` heading, or a `Writing Rules` row in the `doc-metrics` table (the mechanical signal — it survives the heading being renamed), or an inline `RESOLVED` marker or finding ID. Review reports carry finding IDs by construction and are out of scope for this item.
5. A stale `TBD`/`TODO` the Q&A session was meant to resolve, or an `OPEN` row resolved in prose but not in its table cell.
6. A citation-scan hit that survives triage against the exemption list.
7. A broken `§N.M` cross-reference, a diagram contradicting prose, or a resolution summary in the review-request doc that contradicts the current doc content.
8. A `design.md` whose table shows no `5. Detailed Design` row — the section was renamed past recognition, so its ceiling never applied.
9. Either of the two design-field counters the table in Step 2 classifies as a blocker, greater than 0, **on the `design.md` run only**.

Warnings: `over-target` rows, terminology drift, cosmetic inconsistency, review-report status-marker drift, the duplication spot-check, and either of the two design-field counters the Step 2 table classifies as a warning, greater than 0 on the `design.md` run.

### Step 4 — Fix blockers

Fix blockers using **architecture-research-planner agent** (required for all `planning/**/issues/*/` edits per the standard rule). For `docs/` files, architecture-research-planner is also preferred. Propose warnings to the user — fix only if confirmed.

## Constraints

- Do NOT re-run the full `/review-design` consensus protocol — this is a targeted consistency sweep, not a new review cycle.
- Do NOT modify code files — doc verification only.
- Architecture-research-planner must be used for any design doc edits (`planning/**/issues/*/`). Never use Write/Edit tools directly on those files.
- When architecture-research-planner applies review-finding fixes, it must produce clean prose only — **never add `RESOLVED` markers, finding IDs, or review-cycle annotations** to design or user-facing docs. Resolution tracking belongs in the review report (`issues/*/design-review.md`) and the review-request doc, not in the design content itself.
