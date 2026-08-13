---
name: page-type
description: Shared fragment — single source for the book workflow's two page types (main article, reference appendix page). Owns the path forms, the status file, the spec template, identifier derivation, the TODO match rule, the companion-repo policy, and the unverified-claim marker. Read by spec, write, review-article, review-article-fix-loop, review-spec, and the writer agent; article-review/TODOS.md, planning/BRIEF-TEMPLATE.md, planning/APPENDIX-SPEC-TEMPLATE.md, and review-planning-update/SKILL.md also point back to it.
allowed-tools: Bash, Glob, Grep, Read
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, book, article, appendix, paths]
---

# Page Type — Shared Fragment

**This file is the single source for these rules.** `/spec`, `/write`, `/review-article`, and `agents/writer.md` resolve the page type here and carry no copy of the table below. A restatement in a consumer is how the copies drift: the A-page TODO rule was added to two commands, omitted from the third, and cancelled outright by the fragment all three defer to — a rule with three homes and no owner.

## Vocabulary

One term, two values: **page type** is `main` or `appendix`. Do not introduce a second name for *the page type itself* (`mode`, `sub-mode`) in any consumer — do not write "appendix mode" or "fact-spec mode" as a synonym for `appendix`. This does not restrict unrelated pre-existing terminology: the writer agent's **Book Article Mode** is the agent's own operating mode, orthogonal to page type, and predates this fragment. Its `[MODE: book-article/main]` / `[MODE: book-article/appendix]` activation token carries the page type as a value inside that name, not as a second name for it.

## Resolution

The **issue-folder path selects the page type**, and nothing else does. A command that cannot obtain that path cannot resolve a page type — see Obtaining the path.

| | `main` | `appendix` |
|---|---|---|
| Issue folder | `planning/book/milestone-XX-<name>/issues/<NNN-name>/` | `planning/book/appendix/issues/A<N>-<slug>/` |
| Status file | `planning/book/milestone-XX-<name>/status.md` | `planning/book/appendix/status.md` |
| Spec template | `~/.claude/skills/workflows/planning/SPEC-TEMPLATE.md` | `~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md` |
| Spec is | a coding contract — what the CODE must do | a fact contract — what must be TRUE, and how it was checked |
| Companion repo | required; stop if the path does not exist | **not applicable**; never a stop condition, never a WARN. Set the companion metadata fields to `n/a — appendix page` rather than leaving them unresolved |
| Identifier | the folder name `<NNN-name>`, e.g. `04-isp-pixel-formats` | `A<N>`, e.g. `A2` |
| Article part | from `status.md` | none — an A-page has no part |

**An appendix page never cites code.** Its facts come from kernel documentation, datasheets, specifications, and on-device measurement — not from a companion implementation. A draft, brief, or spec that cites companion-repo code for an `appendix` page is scope drift, not a citation to verify; every consumer below treats Scope 1 (code accuracy) as unconditionally suppressed for this page type rather than carving out an exception for code-citing drafts.

**Both globs require the full folder shape.** `planning/book/appendix/issues/A<N>-<slug>/` means a child of `issues/` whose name starts with `A` followed by a digit. A folder under `appendix/issues/` not matching that form is **not** an appendix page — it falls to the rejection rule, because every downstream rule needs the `A<N>` identifier the loose glob does not guarantee.

**Rejection is mandatory.** A path under `planning/book/` matching neither form is an error in every consumer. Do not guess a page type, and do not fall through to a default — picking a template by accident is how the wrong contract gets written. Error with:

```
Path does not match either book page type:
  main:     planning/book/milestone-XX-<name>/issues/<NNN-name>/
  appendix: planning/book/appendix/issues/A<N>-<slug>/
Got: <path>
```

## Appendix status.md — structures referenced

No `planning/book/appendix/status.md` exists yet in any repo; `/spec` and `/write` already assume the structures below, so whoever creates the file first should use exactly these names rather than inventing new ones:

- **Pages** — one row per A-page (identifier, title, and whatever existence/depth notes `/write` needs).
- **Linked from** — one row per A-page, carrying a **Blocks** column that names the main articles that depend on it.
- **Known defects in research notes** — known-bad claims in this page's `analysis.md`, checked before `/spec` or `/write` reuse anything from it.

## Obtaining the path

Take it from an explicit command argument when one is given; that always wins. Only when no argument is supplied, derive it from the active issue in `planning/progress.md`.

**The `progress.md` derivation cannot reach an appendix page.** Its Active section tracks main articles; A-pages appear there only as blockers on someone else's entry. A command whose sole path source is `progress.md` can never select `appendix`, so any command that supports A-pages must accept the path as an argument.

## Identifier derivation and TODO matching

`~/.claude/skills/workflows/article-review/TODOS.md` owns the TODO extraction rules, including the full appendix and main-article matching logic, and is authoritative for them — see its "Article Identifier Derivation" step 0/0a. This fragment states only the identifier each page type maps to, not the matching rule itself:

- `main` — `<NNN-name>` from the issue folder, then the part from `status.md`. Part determination is mandatory; when it fails, skip the TODO step per `TODOS.md`.
- `appendix` — `A<N>`, e.g. `A2`. There is no part, and its absence is **not** a skip condition — `TODOS.md` step 0a is the complete appendix rule.

## The unverified-claim marker

Two tokens, two meanings. They are not interchangeable and neither replaces the other:

| Token | Means | Set by |
|---|---|---|
| `[UNVERIFIED: <what is missing>]` | the fact contract tried to establish this and could not | `/spec` fact-spec, in the §2 unverified table |
| `[VERIFY: <claim>]` | nobody has tried yet; the writer could not confirm it | `/write`, when carrying a claim no §2 row covers |

**`[UNVERIFIED:]` travels verbatim, inside the claim string, from the moment it leaves spec §2's unverified table onward.** §2 keeps `Claim` and `What is missing` as separate columns; `/write` combines them into one hedged claim string when copying the row into `brief.md` §9, and that string then travels unchanged into the draft, where it must be hedged or absent. A consumer that rewrites it to `[VERIFY:]`, or that carries the claim without the marker, breaks the terminal check in `/review-article`, which looks for this exact token.

The marker sits in the third column of §2's unverified table, so a row copied into a facts section arrives stripped of it and reads as established. That is why it moves into the claim string on the way out, and why an unverified row never enters `brief.md` §7.5 or §8 — those sections are the verified-fact sections, and a claim in them carries no signal that it was not checked.

## Consumers

Listed so an editor knows what else to update. Each holds a one-line summary and a pointer here; none holds a copy of the tables above.

| File | Uses |
|---|---|
| `~/.claude/commands/spec.md` | resolution, template selection, companion policy, identifier |
| `~/.claude/commands/write.md` | resolution, status file, companion policy, marker propagation |
| `~/.claude/commands/review-article.md` | resolution, status file, companion policy, marker check, issue-folder argument |
| `~/.claude/commands/review-article-fix-loop.md` | resolution (via `/review-article`'s issue-folder argument), annotation-check branching |
| `~/.claude/commands/review-spec.md` | obtaining the issue-folder path, both path forms, the rejection rule |
| `~/.claude/agents/writer.md` | page type passed in the activation token; appendix branch |
| `~/.claude/skills/workflows/article-review/SCOPES.md` | the appendix review criteria keyed to page type |
| `~/.claude/skills/workflows/article-review/TODOS.md` | identifier derivation and TODO matching, both types |
| `~/.claude/skills/workflows/planning/BRIEF-TEMPLATE.md` | the unverified-claim marker, companion metadata sentinel |
| `~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md` | selected by the `appendix` page type |
| `~/.claude/skills/workflows/review-planning-update/SKILL.md` | the appendix issue-folder-form skip condition for Steps 1-2, taking the resolved path as an explicit `issue_folder` input |
| `~/.claude/skills/workflows/article-review/CODEX-REQUEST-TEMPLATE.md` | branches Review Scope, Constraints, and Review Focus by page type |
