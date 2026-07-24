---
name: review-article
description: Review an article across five quality scopes — code accuracy, facts accuracy, prose accuracy, completeness, and internal consistency.
---

# Article Review Command

**MANDATORY CHECKPOINT:** Review article before publication.

Review an article across five quality scopes using three focused agents and Codex in
parallel. Implementation correctness is handled by `/review-code` before this command
runs; this command covers only article quality.

Applies equally to drafts, final articles, blog posts, and any other written format.

## Usage

```
/review-article                         # infers all paths from current issue context
/review-article <companion-repo-path>   # override companion repo location
```

## Verification Scopes

```
Read ~/.claude/skills/workflows/article-review/SCOPES.md
```

Five scopes: Code Accuracy (Agent 1), Facts Accuracy (Agent 2), Prose Accuracy +
Completeness + Internal Consistency (Agent 3). Each criterion specifies what to check,
how to confirm it, and severity.

## Agents

**3 × reviewer (opus)** — focused, in parallel
**1 × codex-flow** — Scopes 1 and 2 cross-check, background

Focus assignments:
- **Agent 1:** Scope 1 — Code Accuracy (including 1.1 annotation check, excluded from Codex)
- **Agent 2:** Scope 2 — Facts Accuracy; **must search the web**; every finding must cite
  an authoritative source
- **Agent 3:** Scopes 3 + 4 + 5 — Prose Accuracy, Completeness, Internal Consistency

All agents receive the full article, spec (context), and companion repo files inline.
All agents may flag High issues outside their primary scope.
Consensus: **≥2 of 3 agents** to confirm a finding.

---

## Setup

### 1. Locate required files

All three must exist before launching any agents. Stop and report which is missing.

| File | Default location |
|------|-----------------|
| Spec | `planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md` |
| Article | `planning/book/milestone-XX-<name>/issues/<NNN-name>/draft.md` |
| Companion repo | See resolution rule below |

`draft.md` is the canonical article filename. `/review-article` always targets `draft.md`. If `draft.md` is absent, error and stop — report the missing file. Do NOT fall back to `brief.md` (brief.md is the writer agent's fact-verified brief, not the article Web-Claude produces). If the article file has a non-standard name for a legitimate reason, the user must pass the path explicitly; the command does not scan for candidate files.

**Companion repo resolution:**

Precondition: `CLAUDE.local.md` must exist at the repo root with a companion repos table
(`part` and `repo-name`/`path` columns). If absent, the command must be invoked with an
explicit `<companion-repo-path>` argument — otherwise stop and report.

1. If `<companion-repo-path>` provided, use it directly — verify the directory exists
2. Else read `CLAUDE.local.md`, match the article's part number, resolve path as `~/projects/<repo-name>`
3. If ambiguous or directory missing, ask the user

### 2. Check for prior review

If `article-review.md` exists in the issue folder, read it and route prior findings:
- **A-prefixed findings** → agent whose primary scope matches (1→Agent 1, 2→Agent 2, 3/4/5→Agent 3).
  Append: "Re-raise if unresolved at same severity; note explicitly if resolved."
- **AC-prefixed findings** → Codex review-request Context section.
  Append: "Re-raise if still present."

### 2b. Cross-article TODO scan

If `planning/book/todos.md` exists:

```
Read ~/.claude/skills/workflows/article-review/TODOS.md
```

Derive the article identifier from `<NNN-name>` in the issue folder path (from Setup Step 1). Determine the article's part from `status.md`. If the part cannot be determined, skip the TODO scan, set `**TODO scan:** ✗ skipped — part indeterminate from status.md`, and proceed without it — do not halt the review.

Follow the Type A Predicate, Type B Predicate, and Article Identifier Derivation rules in TODOS.md to extract two lists:

**Type A — Inline placeholders:** Open entries matching via Type A Predicate. Grep the article draft for each `<!-- TODO[ID] -->` pattern. Every match is an unresolved placeholder that must appear in the review.

**Type B — Resolution TODOs:** Open entries matching via Type B Predicate. Check whether the article now covers the described content — either explicitly or via a cross-link to content already written.

Record both lists. Pass them to Agent 3 verbatim as completeness context. Set the scan status: `**TODO scan:** ✓ ran (N Type A, N Type B)` (replace N with actual counts). If `todos.md` does not exist, skip this step and set `**TODO scan:** ✗ skipped — todos.md not present`.

### 3. Enumerate and pre-read files

Extract type names and behaviour identifiers from the spec. Locate corresponding source
files in the companion repo. Collect files referenced via `<!-- file: path:L10-L25 -->`
annotations. Deduplicate.

Pre-read in the main conversation before launching any agents (pass inline; agents must
not call Read themselves):
- `spec.md`, article file, all companion repo source files identified above
- "Technical Familiarity" section from `CLAUDE.local.md` → Agent 3 audience baseline.
  If absent: use senior systems engineer as default; note in the review header.

Large repo: if >20 files or >4000 lines, prioritise annotation-cited files then
spec-named files. Record omissions as `Files omitted: <list>` in the review header.

---

## File Overwrite Convention

Always writes a single file `article-review.md` inside the issue folder, overwriting
any prior content. No versioning suffixes.

Only **APPROVED** and **CHANGES REQUESTED** are valid Status values. REJECTED is
intentionally omitted — articles never require redesign; unresolvable problems map to
CHANGES REQUESTED with High findings driving revision.

**Path pattern note:** This workflow uses `book/milestone-XX-<name>/` (name suffix
included). Substitute `goal=book` and `milestone-XX=milestone-XX-<name>` when calling
shared skills that use the generic `<goal>/milestone-XX/` pattern.

---

## Review

### Step 1 — Write Codex review-request

```
Read ~/.claude/skills/workflows/article-review/CODEX-REQUEST-TEMPLATE.md
```

Write the populated document to `planning/book/milestone-XX-<name>/issues/<NNN-name>/article-codex-review-request.md` (this is the Codex **input** — not the review output). The `Output File` field in this document must point to `planning/book/milestone-XX-<name>/issues/<NNN-name>/article-codex-review.md` (the Codex **output**, read in Step 3). Use the **article project root** (the repo containing `planning/`) as `Repository` — not the companion code repo. Provide the companion repo path in the Context section. Copy Requirements bullets verbatim from `## Codex Review-Request Requirements` in SCOPES.md.

### Step 2 — Hard gate + parallel launch

```
Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
```
(`test_coverage = no`)

Launch simultaneously:
- **Agent 1** — Scope 1; article + source files inline; include full Scope 1 criteria from SCOPES.md
- **Agent 2** — Scope 2; article + source files inline; MUST search the web; every finding MUST cite an authoritative source (URL, RFC number, spec section with version); include full Scope 2 criteria from SCOPES.md
- **Agent 3** — Scopes 3+4+5; article + spec + audience baseline inline; include full Scopes 3–5 criteria from SCOPES.md
- **Codex** — `codex-flow` Bash call (`run_in_background: true`) with the review-request above

**Agent instruction (all agents):** This is an article quality review. Do not apply the
8-attribute software quality checklist. Apply only the scope criteria assigned to you,
plus any High issues you observe in other scopes.

### Step 3 — Aggregate

Wait for all 3 agents to complete. Then wait for Codex (Monitor tool; fall back to
polling the output file with 10-minute timeout). Read Codex output at
`planning/book/milestone-XX-<name>/issues/<NNN-name>/article-codex-review.md`. If absent or empty, record
`Codex: ✗ not run — no output written` in the review header.

**Deduplication:** Two findings are duplicates when they cover the same criterion and
the same location. Use the Codex label → scope criterion mapping table in SCOPES.md.

**Claude consensus:** ≥2 of 3 Claude agents → confirmed finding.
**Codex (finder only, not a voter):** A Codex finding needs ≥2 Claude agents to confirm
it; otherwise it goes to Codex-Only Findings.

**Edge cases:**
- Codex fails → proceed on Claude findings only; record in header.
- Agent errors → re-launch once; on second failure include partial findings under
  `Findings Requiring Manual Review`, set `**Status:** CHANGES REQUESTED`.
- Empty pool → mark review clean.

---

## Output

Write `planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md`:

```markdown
# Article Review

**Status:** APPROVED

**Article:** <title>
**Spec:** planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md
**Companion repo:** <path used>
**Audience baseline:** Technical Familiarity from CLAUDE.local.md | default: senior systems engineer
**Files omitted:** <list> — exceeded inline budget  *(omit if nothing omitted)*
**Codex:** ✓ ran  *(on success)*  |  ✗ not run — <reason>  *(on failure)*
**TODO scan:** ✓ ran (N Type A, N Type B)  *(or: ✗ skipped — todos.md not present | ✗ skipped — part indeterminate from status.md)*

---

## Code Accuracy

*(Clean.)* OR list findings:

- **A1** [High | Medium | Low]
  Agents: <Claude agents only — Codex is a finder, not a voter>
  Location: `<file:line or article section>`
  Votes: <N of 3>
  Evidence: <what was found vs what is expected>
  Confirmation: `<file:line read to verify>`

## Facts Accuracy

- **A2** [High | Medium | Low]  Agents: ...  Location: ...  Votes: ...
  Evidence: <claim vs correct>  Source: `<URL or spec section and version>`

## Prose Accuracy

- **A3** [High | Medium | Low]  Agents: ...  Location: ...  Votes: ...
  Evidence: <quoted passage>

## Completeness

- **A4** [High | Medium | Low]  Agents: ...  Location: ...  Votes: ...
  Evidence: <what is promised and where it is missing>

## Internal Consistency

- **A5** [High | Medium | Low]  Agents: ...  Locations: `<A>` and `<B>`  Votes: ...
  Evidence: <quoted contradicting statements>

## Cross-Article TODOs

*(Populated from `planning/book/todos.md` scan — not from agent consensus.)*

**Type A — Inline placeholders still present:**
- `TODO[ID]` — *description from todos.md* — placeholder at `<article section / line>` *(High — publication blocker)*

**Type B — Resolution TODOs this article should close:**
- `TODO[ID]` — *description* — covered ✓ / not covered ✗ *(Medium if not covered)*

**Proposed todos.md updates:**
- Move `ID` from Open → Resolved: *reason*

*(Write "None." for each subsection if empty.)*

## Codex-Only Findings

Always include. Findings raised by Codex not confirmed by ≥2 Claude agents. Write "None." if empty.

- **AC1** [High | Medium | Low]  Location: ...  Evidence: ...  Source: `<cited source>`

## Dropped Findings (failed 2/3)

Always include. Write "None." if empty.

---

## Recommendation

<what must change; reference findings by ID>
```

**Finding IDs:** A-prefix globally sequential across all scopes. AC-prefix for Codex-only.

---

## Assessment

- ✅ **Approve:** Zero High findings. Medium findings do not block (unlike `/review-code`).
- ⚠️ **Request Changes:** One or more High findings.

Verify the status marker:

```
Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
```
(`review_file = planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md`)

Ask the user if they want to `open <path>` the review file.

**Block until the user explicitly approves** before the article proceeds to publication
or any revision cycle. Articles do not carry a status header in the article file itself
(no doc-status update required on approval, unlike `/review-design`).

---

## After Resolving Findings

1. Edit the article file to address the findings.
2. Re-run `/review-article`.

## After Final Approval: Update todos.md

This step runs once, only when the review cycle ends with `**Status:** APPROVED`.

If any TODOs are confirmed resolved (Type A placeholders removed from the article, or Type B items now covered):

1. Propose the exact rows to move from `## Open` to `## Resolved` in `planning/book/todos.md`, with today's date in the `Date` column.
2. Wait for explicit user confirmation before writing.

---

## Final Step

```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = article approved ✅`, `review_label = article review`,
`approved_next = ready for publication or revision`, `escalation = standard`)

`review-planning-update` pushes to backup as its last step — no separate push needed.
