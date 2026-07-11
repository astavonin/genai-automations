---
name: article-review-todos
description: Cross-article TODO tracking reference — Type A/B definitions, article-identifier derivation, and todos.md column contract used by /spec, /write, and /review-article.
allowed-tools: Bash
compatibility: claude-code
---

# Cross-Article TODO Tracking — Reference

Used by `/spec`, `/write`, and `/review-article`. Read this file when extracting TODOs from `planning/book/todos.md`.

## Column Contract

The three commands depend on these exact column names. Do not rename without updating all three commands.

- **Open table:** `ID | Description | Referenced in | Resolves in | Added`
  - `Added` is for triage and reporting only — no command reads it for matching or filtering
- **Resolved table:** `ID | Description | Resolved in | Date`

## Type Definitions

**Type A Predicate** — Open entry matches when `Referenced in` contains the article identifier. These correspond to `<!-- TODO[ID] -->` markers placed in a draft for deferred content. Type A is article-scoped — it does NOT match `milestone` because inline placeholders live inside a specific article, not at milestone scope.

**Type B Predicate** — Open entry matches when `Resolves in` contains the article identifier. These are items this article is expected to cover. Type B DOES include `milestone` because a TODO can be resolved by any article within a milestone (e.g., `Resolves in: milestone-02`).

## Article Identifier Derivation

To determine which `todos.md` entries belong to the current article:

1. **Determine the article's part** from `status.md`. Standard mappings:
   - `Part 1` → `part1`, `Part 2` → `part2`, etc.
   - `Introduction` → `intro`
   - `Appendix` → `appendix`
   This step is MANDATORY — do not skip it.

2. **For entries whose cell contains a `partN/` prefix** (e.g., `part1/04 draft`): the match MUST include the correct part. A bare numeric match (`04`) that crosses part boundaries is rejected — it would silently attribute a `part1/04` TODO to a `part2/04` article.

3. **Apply matches in priority order:**
   - Part-qualified: `part1/04` (or `part2/04`, etc.)
   - Full folder name: `04-storage-formats`
   - Name without number: `storage-formats`
   - Bare number: `04` — only valid as a fallback when the entry does NOT contain a `partN/` prefix
   - Milestone-qualified (Type B only): `milestone-02`, `milestone-01-foundations` — matches any article in the milestone

4. **If the article's part cannot be determined** from `status.md` (missing or ambiguous), skip the TODO extraction entirely. Do not halt the containing command — each command handles this differently:
   - In `/review-article`: record `**TODO scan:** ✗ skipped — part indeterminate from status.md` in the review file header
   - In `/spec` and `/write`: skip silently, no header to write
