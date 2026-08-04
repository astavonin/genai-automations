---
name: write
description: Research a topic and produce a structured Markdown draft using the writer agent. Collects info, code snippets, and diagrams from the codebase for future research and polishing.
---

# Write Command

Use the **writer (opus)** agent to research a topic and produce a structured Markdown draft document.

## Agent

**writer** (opus model)

## Input

The user provides a topic or request, e.g.:
```
/write how the CI caching strategy works
/write the sync pull handler design
/write overview of the scheduler architecture
```

Optional context the user may provide:
- Specific files or directories to focus on
- Target audience (self-reference, team doc, blog post, etc.)
- Depth level (overview vs. deep dive)

## Actions

### 1. Determine output path and detect book mode

- Default output path: `planning/drafts/<topic-slug>.md` in the current project.
- If the user specifies a path, use that instead.

**Book-article-mode detection.** If the output path resolves under `planning/book/milestone-*/issues/*/` **or** `planning/book/appendix/issues/A<N>-<slug>/` (glob match, full shape required per `page-type/SKILL.md` → "Both globs require the full folder shape" — a child of `appendix/issues/` not starting with `A` + digit does not fire book-article mode; it falls through to the rejection rule below), book-article mode fires. This is the sole detection signal — no other markers (repo-level, user-flag, etc.) are consulted. Rationale: there is no other authoritative signal available to `/write` at invocation time.

**Page type.** Resolve it, and the status file and companion policy that follow from it, here:

```
Read ~/.claude/skills/workflows/page-type/SKILL.md
```

Report the resolved page type in the pre-flight report. `<issue-folder>` and `status.md` below mean the resolved paths; where this file spells out the milestone form it is written for readability, not to exclude the appendix. The page type changes which context files step 2 reads and which spec template governs — not the output filename.

If the user's path resolves under `planning/book/` but matches neither glob, stop with the fragment's error text (`page-type/SKILL.md` → "Rejection is mandatory").

In book-article mode, the output filename is `brief.md` (NOT `draft.md`). If the user's path ends in `draft.md`, rewrite the filename to `brief.md` and inform the user of the rewrite in the pre-flight report. No confirmation prompt — the rename is deterministic. If the user's path ends in any other filename besides `brief.md`, use it as-is. Rationale: `draft.md` is reserved for the actual article produced by Web-Claude in the subsequent step.

### 2. Book-article-mode context reading (only if book mode)

Skip this entire step for non-book drafts.

For each read below, HALT applies only where explicitly noted; all other misses produce a WARN and become an entry in `brief.md` §9 (Uncertainty Flags) via the writer agent.

**2a. Read the writing style guide — HALT if missing.**

```
Read planning/style-guide.md
```

If the file does not exist, HALT with:

```
Book-article mode requires `planning/style-guide.md` to exist. Style guide governs prose,
code annotation format, diagram workflow, and AI-detection patterns. Cannot proceed
without it. Drop the style guide at that path and re-run.
```

If the file exists, scan the first 10 lines for a line matching regex `^Version:\s*(.+?)\s*$`; capture the version string for the writer agent. If no `Version:` line is found in the first 10 lines, WARN and record `version-unknown` for brief.md metadata; do not HALT.

**2b. Read the book overview.**

```
Read planning/book/overview.md
```

**main:** Extract this article's part number, article number, article title, position within the part (previous article, next article), reader arc for the part. If missing, WARN and flag in brief.md §9.

**appendix:** An A-page has no part (`page-type/SKILL.md` → Resolution) — do not extract one. Set brief.md's `Part` metadata field to `n/a — appendix page`; this is not a WARN and does not get a §9 flag. Still extract article title and reader arc for the part owning most of this page's Blocks column, for continuity context.

**2c. Read the article notes.**

```
Read planning/book/milestone-XX-<name>/status.md      (main)
Read planning/book/appendix/status.md                 (appendix)
```

Extract this page's notes. For a main article that is the paragraph under "Article Notes", which opens with a `**Pipeline slice:**` line and a `**Depth refs:**` line — the slice names what this article walks, and the depth refs name the A-pages it links to. For an A-page it is the row in "Pages" plus the matching "Linked from" row, whose **Blocks** column names the main articles that depend on this page and therefore the depth each needs. If missing, WARN and flag in brief.md §9.

**2d. Read the spec.**

```
Read planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md    (main)
Read planning/book/appendix/issues/A<N>-<slug>/spec.md              (appendix)
```

For a `main` page the spec is a **coding contract** and supplies factual context about what the code does, driving fact extraction in brief.md §7.

For an `appendix` page it is a **fact contract** per `~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md`. Its §2 Claims and §5 Verification Procedure are the verified facts: carry each claim into brief.md §7.5 **together with the source attached to it in the spec**. A claim copied without its source is the failure this contract exists to prevent — Web-Claude cannot re-derive it and will publish it unsourced. Its §4 Terminology Contract defines terms that dependent main articles rely on and is passed to Web-Claude directly via the full `spec.md` inline context in step 4 — those definitions are binding, not suggestions, and are not duplicated into the brief.

**Routing (appendix).** §2 verified rows → **§7.5 only** (numeric or not — see BRIEF-TEMPLATE.md §7.5), with their source. §8 (External Citations) is not used for an appendix page — every fact the brief carries is already spec-verified, not something Web-Claude re-derives at draft time. §2 unverified rows → **§9 only**, per the marker rules in `page-type/SKILL.md`. A row whose `Verified by` is empty or names a §5 row that does not exist counts as unverified whichever table it sits in — and for a row demoted this way from the *verified* table, which has no `What is missing` cell to carry, synthesize the marker inline before routing it to §9: `[UNVERIFIED: dangling Verified-by reference — <ID> names no §5 row]`, or `[UNVERIFIED: Verified-by is empty — <ID>]` for the empty case. Do not route it to §9 with no marker; an unmarked claim in §9 reads as a verified fact.

If the spec is missing: `main` → WARN and flag in brief.md §9.

**appendix → HALT** with:

```
Book-article mode (appendix) requires `<issue-folder>/spec.md` to exist. The spec is the
verification contract for this A-page — its §2 Claims and §5 Verification Procedure are
the only source of verified facts a brief can carry. Cannot proceed without it.
Run `/spec <issue-folder>`, then re-run `/write`.
```

**2d-bis. Read the research notes (appendix only).**

```
Read planning/book/appendix/issues/A<N>-<slug>/analysis.md
```

Pre-existing research for this A-page. Treat it as **unverified**: it predates the fact contract, and known defects are listed under "Known defects in research notes" in `planning/book/appendix/status.md`. Read that defects table before using anything here. Any claim taken from the notes that §2 of the spec does not carry must be flagged `[VERIFY: ...]` in brief.md §9. If `analysis.md` is missing, skip silently. If `analysis.md` exists but `status.md` was WARNed as missing in step 2c, there is no defects table to check — do not proceed as if none exist: add a §9 flag ("defects table unavailable — status.md missing") so a known-bad claim's absence-of-warning is visible, not silent.

**2e. Enumerate and read relevant appendices.**

```
Read docs/appendix/A*.md   (glob — read all that exist)
```

Determine relevance by cross-referencing article topic keywords against appendix titles. Read only appendices relevant to this article's pipeline slice. If uncertain, err on the side of reading all A-pages that exist (there are few). If `docs/appendix/` does not exist or is empty, WARN and flag in brief.md §4 (A-page Dependencies) as "no A-pages available".

**2f. Read the adjacent published articles.**

```
Read docs/part<NN>/<NN>-<slug>.md   (main: previous article — derived from overview.md or status.md ordering)
Read docs/part<NN>/<NN>-<slug>.md   (appendix: each PUBLISHED article in this page's Blocks column — see 2f below for the zero-pad rule)
```

For a `main` page, used for continuity of voice and to understand what the reader knows entering this article. If this is article 01 of a part (no previous), skip silently — expected. If a previous article is expected but missing, WARN and flag in brief.md §9.

For an `appendix` page there is no "previous article". Read instead the already-published main articles that list this A-page as a depth reference: they establish the depth the page must actually carry and the terminology those articles already use. Resolve each dependent's path by zero-padding its part number to two digits (part 1 → `part01`, part 10 → `part10` — do not string-concatenate a literal `0` prefix, which produces `part010` at part 10) and globbing `docs/part<NN>/<NN>-*.md` for the article number named in the Blocks entry; a match means published, no match means skip. If none of the dependents are published, skip silently — expected under the A-page-first policy, where the A-page normally ships first.

**2g. Resolve companion repo path.**

```
Read CLAUDE.local.md
```

From the companion repos table (in the book repo root), resolve the local path for the article's part. Confirm the directory exists.

**Appendix:** an A-page has no companion repo of its own. Resolve the repo for the part owning most of this page's Blocks column and treat it as **optional context** — an A-page's facts come from kernel documentation, datasheets, specifications, and on-device measurement, not from companion source. A missing repo is not a WARN here — note it in the pre-flight report, set the companion metadata fields to `n/a — appendix page` per step 4, and continue.

**Main only.** If `CLAUDE.local.md` is absent or the companion repo directory does not exist, WARN and flag in brief.md §9. Include this minimal template in the WARN message to help with fresh-setup:

```markdown
# Companion Repos

| Part | Repo local path | GitHub owner/repo |
|------|-----------------|-------------------|
| 05   | ~/projects/g2g-part5 | astavonin/g2g-part5 |

# Technical Familiarity

<one-line description of the target reader for style-guide-compliance review>
```

Fact-verification (line ranges, commit hash, code excerpts) then runs in best-effort mode for a `main` page — writer marks any unverifiable claim with `[VERIFY: ...]`. Does not apply to `appendix`, which resolved its own companion-repo policy above.

**Main only** (an appendix page has no part to fail to determine). If the article's part cannot be determined (2b and 2c both WARNed), record a §9 flag "companion repo unresolved: part number undetermined" and skip companion repo resolution. Fact-verification then falls back to best-effort with `[VERIFY: ...]` on every code-derived claim.

### 3. Cross-article TODO context (book articles only)

If the output path resolves under `planning/book/` and `planning/book/todos.md` exists:

```
Read ~/.claude/skills/workflows/article-review/TODOS.md
```

Follow the Type A Predicate, Type B Predicate, and Article Identifier Derivation rules in that file. Derive the identifier and match entries per `~/.claude/skills/workflows/page-type/SKILL.md` → "Identifier derivation and TODO matching", which states both branches — step 0a for an `appendix` page, steps 1–4 for a `main` page. A `main` page whose part cannot be determined skips the TODO context step and proceeds — do not halt.

Extract:
- **Type A** — open entries matching via Type A predicate: deferred items to insert as `<!-- TODO[ID] -->` markers.
- **Type B** — open entries matching via Type B predicate: content this article is expected to cover.

Pass both lists to the writer agent with instruction: "Record Type A items in brief.md §10 as inline placeholders to include in draft (with section positions). Record Type B items in brief.md §10 as resolution TODOs this article should close. The brief does NOT contain draft prose or `<!-- TODO[ID] -->` markers themselves — those get inserted at draft-writing time by Web-Claude."

### 4. Invoke writer agent

**Book-article mode:** begin the writer agent prompt with the activation token — `[MODE: book-article/main]` or `[MODE: book-article/appendix]`, carrying the resolved page type — on the first line, then pass:
- The user's topic/request
- All context files read in step 2 (style guide, overview.md, status.md, spec.md, A-pages, previous article) as inline context — not just references
- The companion repo path (or the WARN flag from 2g if unresolved) with instruction to verify line ranges, capture commit hash via `git rev-parse HEAD`, extract API signatures and code excerpts from current code
- The extracted style guide version from step 2a for the brief.md metadata block
- The TODO context from step 3 formatted for §10
- The full BRIEF-TEMPLATE.md structure (all 11 sections required)
- Metadata fallback rules derived from step 2 WARNs:
  - 2b WARN (overview.md missing, main only) → Part field = `<unknown>`; add §9 "Missing context files" entry
  - 2b appendix case (expected, not a WARN) → Part field = `n/a — appendix page`; no §9 entry
  - 2d WARN (spec.md missing) → Spec field = `<unknown>`; add §9 "Missing context files" entry
  - 2g WARN (companion repo missing) → Companion repo (local) = `<unknown>`, Companion repo (github) = `<unknown>`, Companion repo commit = `<unknown>`; add §9 "Missing context files" entry
  - 2g appendix case (expected, not a WARN) → Companion repo (local) = `n/a — appendix page`, Companion repo (github) = `n/a — appendix page`, Companion repo commit = `n/a — appendix page`; no §9 entry

**Appendix page — additionally pass** (the agent does the work; a rule stated only here does not reach it):
- `<issue-folder>/analysis.md` from 2d-bis, labelled **unverified prior research**, with the Known-defects table — the A4 fabrication (a fabricated claim published as established fact, with no verification behind it) is in that file
- The 2d routing rule verbatim
- Companion-repo metadata fields = `n/a — appendix page`. The 2g WARN does not fire here, so the standing "capture the commit hash" mandate would otherwise have nothing to capture
- `§7.1`–`§7.4` (line ranges, excerpts, tests, API signatures) take `(none — fact contract)`

**Non-book mode:** default invocation — pass:
- The user's topic/request
- The current working directory as the codebase root
- Any additional context provided by the user
- The TODO context from step 3 (if applicable)
- Instruction to produce a complete Markdown draft following the writer agent default output structure

### 5. Save the output

- **Book-article mode:** writer agent writes to `<issue-folder>/brief.md` (main or appendix — the resolved path from step 1).
- **Non-book mode:** writer agent writes to the determined output path (default `planning/drafts/<topic-slug>.md`, or user-specified).

### 6. Report to user

- Output saved to: `<path>` (`brief.md` in book mode; `draft.md` otherwise)
- What was covered — one line
- Any open questions or gaps flagged in the output
- **Book-article mode additional:** report each WARN from step 2 (missing overview.md, status.md, etc.) so the user knows what context was unavailable and appears in brief.md §9 (Uncertainty Flags).
- Ask the user if they want to `open <path>` per the Post-Write Actions convention in CLAUDE.md. Ask in isolation — do not combine with any next-step suggestion.

#### Web-Claude handoff (book-article mode only)

After reporting brief.md, include the following handoff block so the user can copy-paste it into a Web-Claude session:

**Interpolate the resolved folder and the page-type variant before printing** — this block leaves the session, and Web-Claude never saw the `<issue-folder>` convention. A pasted placeholder path sends an appendix draft to a folder that does not exist.

**Files Web-Claude needs:**
1. `<issue-folder>/spec.md`
2. `<issue-folder>/brief.md`
3. Any relevant A-pages referenced in brief.md §4 (from `docs/appendix/A*.md`)
4. `planning/style-guide.md`

**Copy-paste prompt template** — line 1 of the numbered list differs by page type; emit the matching one:

```
You are writing a technical article for a book series. I'm providing four inputs:

1. [main]     spec.md — the coding contract: what the implementation does, its public API, and test requirements.
1. [appendix] spec.md — the fact contract: §2 Claims (every assertion with its source), §4 Terminology Contract (definitions dependent articles bind to), §5 Verification Procedure (the command or lookup that established each claim, with captured output). It contains no code, no API, and no tests.
2. brief.md — the article-writing brief: verified facts, article intent (theory scope, reader arc, section outline, A-page dependencies, diagram list), and structural guidance.
3. Relevant A-pages — appendix pages for depth references.
4. planning/style-guide.md — the style contract you MUST follow.

Read planning/style-guide.md before writing anything. The brief's §11 Style Guide Compliance Target is the contract you are held to by /review-article.

Any claim in brief.md §9 marked [UNVERIFIED: ...] or [VERIFY: ...] could not be established, or has not yet been checked. Either leave it out of the draft, or state it with the hedge the marker gives you. Presenting either as settled fact is a High finding at review.

Write the article as `draft.md` in the same folder as brief.md. The draft is the actual reader-facing article — narrative prose, code snippets at the verified line ranges, diagrams per the brief's §6 diagram list. Do not reproduce the brief's structure in the draft.

Output path: <issue-folder>/draft.md
```

**Output expectation:** Web-Claude writes `draft.md` at `<issue-folder>/draft.md` — the same folder as `brief.md`. The `/review-article` command targets `draft.md` at that path.

**Style guide requirement:** Web-Claude MUST read `planning/style-guide.md` before writing `draft.md`. The brief's §11 Style Guide Compliance Target is the contract. `/review-article` will fail `draft.md` if style-guide rules are violated.

## Output

### Non-book mode — `draft.md`

A Markdown draft document at `planning/drafts/<topic-slug>.md` (or user-specified path) containing:
- Overview and background
- Key concepts with code snippets, each anchored to its source (pinned `<short-hash>:path:line` for pushed code, file + symbol otherwise)
- Mermaid diagrams derived from actual code
- Design decisions and trade-offs
- Open questions flagged with `<!-- TODO: ... -->` (author-managed, no ID; distinct from tracked `<!-- TODO[ID] -->` markers used in book articles)
- References section

### Book-article mode — `brief.md`

A fact-verified article-writing brief at `<issue-folder>/brief.md` (`planning/book/milestone-XX-<name>/issues/<NNN-name>/brief.md` for `main`, `planning/book/appendix/issues/A<N>-<slug>/brief.md` for `appendix`) following `~/.claude/skills/workflows/planning/BRIEF-TEMPLATE.md`. The brief carries verified facts (line ranges, commit hash, test list, API signatures), article intent (theory scope, reader arc, section outline, A-page dependencies, diagram list), and structural guidance — **not** article prose. The brief is consumed by Web-Claude in a subsequent step to write the actual `draft.md`.

The brief has 11 required sections plus a metadata block. See BRIEF-TEMPLATE.md for the exact structure.

## Notes

- The draft or brief is a starting point — it is NOT final and requires further steps (polishing for `draft.md`; Web-Claude article-writing for `brief.md`).
- The writer agent reads the codebase but does NOT modify any files.
- Re-running `/write` on the same topic overwrites the previous output (draft or brief).
- For large topics in non-book mode, consider scoping with specific directories or components.
- Book-article mode requires `planning/style-guide.md` to exist in the book repo; missing style guide HALTS the command with a clear error.
