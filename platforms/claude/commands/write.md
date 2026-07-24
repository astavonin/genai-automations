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

**Book-article-mode detection.** If the output path resolves under `planning/book/milestone-*/issues/*/` (glob match), book-article mode fires. This is the sole detection signal — no other markers (repo-level, user-flag, etc.) are consulted. Rationale: there is no other authoritative signal available to `/write` at invocation time.

If the user's path resolves under `planning/book/` but does NOT match `planning/book/milestone-*/issues/*/`, error immediately:

```
/write in book-article mode requires a path under `planning/book/milestone-XX-<name>/issues/<NNN-name>/`.
Given path: `<path>`. Either fix the path or write outside `planning/book/` for non-book mode.
```

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

Extract: this article's part number, article number, article title, position within the part (previous article, next article), reader arc for the part. If missing, WARN and flag in brief.md §9.

**2c. Read the article notes.**

```
Read planning/book/milestone-XX-<name>/status.md
```

Extract this article's article notes — the paragraph under "Article Notes" for this article. These notes carry topic framing, pipeline slice, and any status.md-embedded theory guidance. If missing, WARN and flag in brief.md §9.

**2d. Read the coding spec.**

```
Read planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md
```

Used for factual context about what the code does (drives fact extraction in brief.md §7). If missing, WARN and flag in brief.md §9 — the writer will note that fact extraction will be sparse without it.

**2e. Enumerate and read relevant appendices.**

```
Read docs/appendix/A*.md   (glob — read all that exist)
```

Determine relevance by cross-referencing article topic keywords against appendix titles. Read only appendices relevant to this article's pipeline slice. If uncertain, err on the side of reading all A-pages that exist (there are few). If `docs/appendix/` does not exist or is empty, WARN and flag in brief.md §4 (A-page Dependencies) as "no A-pages available".

**2f. Read the previous article's draft (if published).**

```
Read docs/part<NN>/<NN>-<slug>.md   (previous article — derived from overview.md or status.md ordering)
```

Used for continuity of voice and to understand what the reader knows entering this article. If this is article 01 of a part (no previous), skip silently — expected. If a previous article is expected but missing, WARN and flag in brief.md §9.

**2g. Resolve companion repo path.**

```
Read CLAUDE.local.md
```

From the companion repos table (in the book repo root), resolve the local path for the article's part. Confirm the directory exists.

If `CLAUDE.local.md` is absent or the companion repo directory does not exist, WARN and flag in brief.md §9. Include this minimal template in the WARN message to help with fresh-setup:

```markdown
# Companion Repos

| Part | Repo local path | GitHub owner/repo |
|------|-----------------|-------------------|
| 05   | ~/projects/g2g-part5 | astavonin/g2g-part5 |

# Technical Familiarity

<one-line description of the target reader for style-guide-compliance review>
```

Fact-verification (line ranges, commit hash, code excerpts) then runs in best-effort mode — writer marks any unverifiable claim with `[VERIFY: ...]`.

If the article's part cannot be determined (2b and 2c both WARNed), record a §9 flag "companion repo unresolved: part number undetermined" and skip companion repo resolution. Fact-verification then falls back to best-effort with `[VERIFY: ...]` on every code-derived claim.

### 3. Cross-article TODO context (book articles only)

If the output path resolves under `planning/book/` and `planning/book/todos.md` exists:

```
Read ~/.claude/skills/workflows/article-review/TODOS.md
```

Follow the Type A Predicate, Type B Predicate, and Article Identifier Derivation rules in that file. Derive the article identifier from the output path (e.g. path ending in `04-storage-formats/brief.md` yields folder `04-storage-formats`); determine the article's part from `planning/book/milestone-XX-<name>/status.md` (derived from the output path) before matching. If the part cannot be determined, skip the TODO context step and proceed without it — do not halt.

Extract:
- **Type A** — open entries matching via Type A predicate: deferred items to insert as `<!-- TODO[ID] -->` markers.
- **Type B** — open entries matching via Type B predicate: content this article is expected to cover.

Pass both lists to the writer agent with instruction: "Record Type A items in brief.md §10 as inline placeholders to include in draft (with section positions). Record Type B items in brief.md §10 as resolution TODOs this article should close. The brief does NOT contain draft prose or `<!-- TODO[ID] -->` markers themselves — those get inserted at draft-writing time by Web-Claude."

### 4. Invoke writer agent

**Book-article mode:** begin the writer agent prompt with the activation token `[MODE: book-article]` on the first line, then pass:
- The user's topic/request
- All context files read in step 2 (style guide, overview.md, status.md, spec.md, A-pages, previous article) as inline context — not just references
- The companion repo path (or the WARN flag from 2g if unresolved) with instruction to verify line ranges, capture commit hash via `git rev-parse HEAD`, extract API signatures and code excerpts from current code
- The extracted style guide version from step 2a for the brief.md metadata block
- The TODO context from step 3 formatted for §10
- The full BRIEF-TEMPLATE.md structure (all 11 sections required)
- Metadata fallback rules derived from step 2 WARNs:
  - 2b WARN (overview.md missing) → Part field = `<unknown>`; add §9 "Missing context files" entry
  - 2d WARN (spec.md missing) → Spec field = `<unknown>`; add §9 "Missing context files" entry
  - 2g WARN (companion repo missing) → Companion repo (local) = `<unknown>`, Companion repo (github) = `<unknown>`, Companion repo commit = `<unknown>`; add §9 "Missing context files" entry

**Non-book mode:** default invocation — pass:
- The user's topic/request
- The current working directory as the codebase root
- Any additional context provided by the user
- The TODO context from step 3 (if applicable)
- Instruction to produce a complete Markdown draft following the writer agent default output structure

### 5. Save the output

- **Book-article mode:** writer agent writes to `planning/book/milestone-XX-<name>/issues/<NNN-name>/brief.md`.
- **Non-book mode:** writer agent writes to the determined output path (default `planning/drafts/<topic-slug>.md`, or user-specified).

### 6. Report to user

- Output saved to: `<path>` (`brief.md` in book mode; `draft.md` otherwise)
- Brief summary of what was covered
- Any open questions or gaps flagged in the output
- **Book-article mode additional:** report each WARN from step 2 (missing overview.md, status.md, etc.) so the user knows what context was unavailable and appears in brief.md §9 (Uncertainty Flags).
- Ask the user if they want to `open <path>` per the Post-Write Actions convention in CLAUDE.md. Ask in isolation — do not combine with any next-step suggestion.

#### Web-Claude handoff (book-article mode only)

After reporting brief.md, include the following handoff block so the user can copy-paste it into a Web-Claude session:

**Files Web-Claude needs:**
1. `planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md`
2. `planning/book/milestone-XX-<name>/issues/<NNN-name>/brief.md`
3. Any relevant A-pages referenced in brief.md §4 (from `docs/appendix/A*.md`)
4. `planning/style-guide.md`

**Copy-paste prompt template:**

```
You are writing a technical article for a book series. I'm providing four inputs:

1. spec.md — the coding contract: what the implementation does, its public API, and test requirements.
2. brief.md — the article-writing brief: verified facts (line ranges, commit hash, code excerpts, test list, API signatures), article intent (theory scope, reader arc, section outline, A-page dependencies, diagram list), and structural guidance.
3. Relevant A-pages — appendix pages for depth references.
4. planning/style-guide.md — the style contract you MUST follow.

Read planning/style-guide.md before writing anything. The brief's §11 Style Guide Compliance Target is the contract you are held to by /review-article.

Write the article as `draft.md` in the same folder as brief.md. The draft is the actual reader-facing article — narrative prose, code snippets at the verified line ranges, diagrams per the brief's §6 diagram list. Do not reproduce the brief's structure in the draft.

Output path: planning/book/milestone-XX-<name>/issues/<NNN-name>/draft.md
```

**Output expectation:** Web-Claude writes `draft.md` at `planning/book/milestone-XX-<name>/issues/<NNN-name>/draft.md` — the same folder as `brief.md`. The `/review-article` command targets `draft.md` at that path.

**Style guide requirement:** Web-Claude MUST read `planning/style-guide.md` before writing `draft.md`. The brief's §11 Style Guide Compliance Target is the contract. `/review-article` will fail `draft.md` if style-guide rules are violated.

## Output

### Non-book mode — `draft.md`

A Markdown draft document at `planning/drafts/<topic-slug>.md` (or user-specified path) containing:
- Overview and background
- Key concepts with code snippets (file path + line numbers)
- Mermaid diagrams derived from actual code
- Design decisions and trade-offs
- Open questions flagged with `<!-- TODO: ... -->` (author-managed, no ID; distinct from tracked `<!-- TODO[ID] -->` markers used in book articles)
- References section

### Book-article mode — `brief.md`

A fact-verified article-writing brief at `planning/book/milestone-XX-<name>/issues/<NNN-name>/brief.md` following `~/.claude/skills/workflows/planning/BRIEF-TEMPLATE.md`. The brief carries verified facts (line ranges, commit hash, test list, API signatures), article intent (theory scope, reader arc, section outline, A-page dependencies, diagram list), and structural guidance — **not** article prose. The brief is consumed by Web-Claude in a subsequent step to write the actual `draft.md`.

The brief has 11 required sections plus a metadata block. See BRIEF-TEMPLATE.md for the exact structure.

## Notes

- The draft or brief is a starting point — it is NOT final and requires further steps (polishing for `draft.md`; Web-Claude article-writing for `brief.md`).
- The writer agent reads the codebase but does NOT modify any files.
- Re-running `/write` on the same topic overwrites the previous output (draft or brief).
- For large topics in non-book mode, consider scoping with specific directories or components.
- Book-article mode requires `planning/style-guide.md` to exist in the book repo; missing style guide HALTS the command with a clear error.
