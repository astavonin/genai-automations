---
name: review-article
description: Review an article draft in two sequential passes — spec compliance first, then article quality. Runs after /write.
---

# Article Review Command

Review an article draft in two sequential passes. Pass 1 (spec compliance) gates Pass 2
(article quality) — if the implementation does not satisfy the spec, the article cannot
be reviewed for quality yet.

**No Codex** — this review evaluates spec compliance against a prose contract and article
quality for a human reader; code-correctness tools do not apply.

## Usage

```
/review-article                         # infers all paths from current issue context
/review-article <companion-repo-path>   # override companion repo location
```

## Agents

**1 × reviewer (opus)** — Pass 1 (spec compliance)
**1 × reviewer (opus)** — Pass 2 (article quality) — only if Pass 1 is clean

## Setup

### 1. Locate required files

All three must exist before launching any agents. Stop and report which is missing if any.

| File | Default location |
|------|-----------------|
| Spec | `planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md` |
| Draft | `planning/book/milestone-XX-<name>/issues/<NNN-name>/draft.md` |
| Companion repo | See resolution rule below |

**Companion repo resolution:**
1. If `<companion-repo-path>` was provided as an argument, use that directly — skip steps 2–4
2. Read `CLAUDE.local.md` companion repos table
3. Match the current article's part number to the correct table entry
4. Resolve local disk path as `~/projects/<repo-name>` from the matched entry
5. If the match is ambiguous or the directory does not exist, ask the user

### 2. Check for prior review

If `planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md` already exists,
read it and partition prior findings by pass:
- Prior **S-findings** (Pass 1) → include in the Pass 1 agent prompt
- Prior **A-findings** (Pass 2) → include in the Pass 2 agent prompt

In each case, append the instruction: "This finding was raised in a prior review. Verify
whether it has been addressed. Re-raise if unresolved at the same severity; note
explicitly if resolved."

### 3. Enumerate implementation files

From the spec, extract all type names, behaviour identifiers, and integration constraints.
Locate the corresponding source files in the companion repo using `grep` or directory
traversal. Also collect every file referenced in the draft via
`<!-- file: path/to/file.ext:L10-L25 -->` annotations. Deduplicate.

Pre-read every file in this list in the main conversation before launching any agents —
pass contents inline. Do not let agents call Read themselves.

Files to pre-read:
- `spec.md`
- `draft.md`
- All companion repo source files identified above
- The "Technical Familiarity" section of `CLAUDE.local.md` (pass to Pass 2 agent as
  audience context)

## File Overwrite Convention

This skill always writes a single file `article-review.md` inside the issue folder,
**overwriting** any prior content. No versioning suffixes. Git history preserves prior
reviews if needed.

## Status Marker Convention

Every article review file MUST contain exactly one status marker as the **first non-empty
line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji.

Verify with:
```bash
head -20 planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md \
  | grep -m 1 '^\*\*Status:\*\*'
```

## Pass 1 — Spec Compliance

Launch a single reviewer (opus) agent. Provide inline:
- Full `spec.md`
- Implementation source files identified in Setup §3
- Any prior Pass 1 findings from a previous review (per Setup §2)
- The checklist below

**Do not provide the draft** — Pass 1 is about the code, not the article.

### Spec compliance checklist

For items 1–5, cite the spec section and the implementation location (file:line).
For item 6 (scope creep), cite only the implementation location — there is no spec
section because the item is absent from the spec by definition.

1. **Types present** — every type named in the spec exists with the correct name and
   visibility
2. **Invariants enforced** — each type invariant from the spec is enforced by the
   implementation, not merely documented
3. **Behaviours implemented** — every behaviour described in the spec is present and
   produces the correct observable outcome (return value, side effect, error)
4. **Smoke test assertions match** — every assertion in the spec's smoke test section
   (tolerances, thresholds, counts) is present verbatim or equivalent in the test code
5. **Integration constraints satisfied** — each constraint in the spec's integration
   constraints section (target platforms, runtime restrictions, dependency rules) is met
6. **Scope creep** — note any public types, public methods, or testable behaviours present
   in the implementation that are absent from the spec; these do not block Pass 1 but
   must be listed so the article author can decide whether to cover them

Items 1–5 are blocking. Item 6 is informational.

### Pass 1 gate

If items 1–5 have any violations → write the review file with `**Status:** CHANGES REQUESTED`,
include Pass 1 findings only, skip Pass 2.

If Pass 1 is clean (zero violations in items 1–5) → proceed to Pass 2.

## Pass 2 — Article Quality

Only runs after a clean Pass 1.

Launch a single reviewer (opus) agent. Provide inline:
- Full article draft
- `spec.md` (context — what the article is supposed to cover)
- Implementation source files identified in Setup §3 (needed to verify snippet accuracy)
- The "Technical Familiarity" section from `CLAUDE.local.md` (pre-read in Setup §3)
- Any prior Pass 2 findings from a previous review (per Setup §2)
- The checklist below

**Agent instruction:** This is an article quality review, not a software code review.
Do not apply the 8-attribute software quality checklist. Apply only the article quality
checklist below.

**Audience context:** Use the "Technical Familiarity" section provided inline above as
the baseline for judging what counts as over-explanation — do not assume a generic
"systems engineer" profile.

### Article quality checklist

Severity guidance — High: reader is misled or cannot follow the article; Medium: article
works but has a structural or clarity problem; Low: polish issue.

#### Structure
- **WHY before HOW** — every section establishes motivation before showing mechanics;
  the reader understands why they are reading each section before they read it
  *(High if a core section jumps straight to code with no motivation)*
- **No section duplication** — the same information does not appear in two places
  *(Medium)*
- **Heading hierarchy** — each heading maps to a distinct concept; no heading merely
  restates its parent *(Low)*

#### Audience calibration
- **No over-explanation** — the target reader is a systems engineer; skip definitions of
  V4L2 ioctls, Rust ownership basics, Linux kernel concepts unless the article is
  specifically about those things *(Medium if occasional, High if pervasive)*
- **Trade-offs are named** — design decisions are explained in terms of what was given up,
  not just what was chosen *(Medium)*
- **Voice is direct** — no hedging ("might", "could potentially"), no preamble before the
  point *(Low)*

#### Code examples
- **One concept per snippet** — each snippet illustrates exactly one key insight; anything
  not essential to that insight is absent *(Medium)*
- **No noise** — no boilerplate imports, unrelated helpers, or scaffolding unless the
  article is specifically about those *(Medium)*
- **File path and line numbers present** — every snippet has a `<!-- file: path:L10-L25 -->`
  annotation *(High — without this, accuracy cannot be verified)*
- **Snippet accuracy** — the snippet matches what is actually at those lines in the
  companion repo *(High — reader following the wrong code is a direct harm)*

#### Diagrams
- **Derived from code** — each diagram reflects actual runtime structure or data flow
  *(High if diagram contradicts code)*
- **No prose duplication** — the diagram shows something the adjacent prose does not
  already say completely *(Low)*
- **Captioned** — every diagram has a caption that states what it shows *(Low)*

#### Technical accuracy
- **Numbers match code** — any constant, threshold, or measured value cited in prose
  matches the implementation *(High)*
- **Behaviour descriptions match code** — no approximations that would mislead a careful
  reader *(High)*

#### Completeness
- **Opening promise kept** — the article covers what its opening paragraph claims
  *(High if a promised topic is absent)*
- **No stranded reader** — the reader finishing the article has enough context to extend
  or debug the code without re-reading the spec *(Medium)*
- **Key failure modes addressed** — if the spec or implementation has known limitations,
  the article acknowledges them *(Medium)*

## Output

Write `planning/book/milestone-XX-<name>/issues/<NNN-name>/article-review.md`:

```markdown
# Article Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Article:** <article title from draft>
**Spec:** planning/book/milestone-XX-<name>/issues/<NNN-name>/spec.md
**Companion repo:** <path used>
**Pass 1:** ✅ Clean | ⚠️ N violations
**Pass 2:** ✅ Ran | ⏭ Skipped — Pass 1 violations must be resolved first

---

## Pass 1 — Spec Compliance

*(Clean — no violations.)*

OR, if violations found:

- **S1** [type | invariant | behaviour | smoke-test | constraint]
  Spec: `<spec section>`
  Implementation: `<file:line>`
  Gap: <what is missing or wrong>

- **S2** [scope-creep]
  Implementation: `<file:line>`
  Note: <what extra public surface is present and whether the article should cover it>

## Pass 2 — Article Quality

*(Skipped — resolve Pass 1 violations first.)*

OR, if ran:

### Structure
- **A1** [High | Medium | Low] <finding>

### Audience Calibration
- **A2** [High | Medium | Low] <finding>

### Code Examples
- **A3** [High | Medium | Low] <finding>

### Diagrams
- **A4** [High | Medium | Low] <finding>

### Technical Accuracy
- **A5** [High | Medium | Low] <finding>

### Completeness
- **A6** [High | Medium | Low] <finding>

---

## Recommendation

<what must change; reference findings by ID>
```

A-finding IDs are globally sequential across all sections (A1, A2, A3 … not restarting
per section). S-finding IDs are globally sequential within Pass 1 (S1, S2, S3 …).

## Assessment

- ✅ **Approve:** Pass 1 clean + zero High article quality findings
- ⚠️ **Request Changes:** Pass 1 blocking violations that are fixable without restructuring
  the article (missing behaviour, wrong threshold, constraint not met) OR one or more High
  article quality findings
- ❌ **Reject:** Pass 1 violations that invalidate the article's central narrative — the
  type or behaviour the article is built around exists but has the wrong contract, meaning
  the article's explanation of *why* the design is what it is would be wrong even after
  patching the implementation

After writing, ask the user if they want to `open <path>` the review file.

## After Resolving CHANGES REQUESTED Findings

### Pass 1 violations (implementation issues)
1. Fix the implementation in the companion repo
2. Re-run `/write` — the draft may reference wrong code and needs to be regenerated
3. Re-run `/review-article`

### Pass 2 findings (article quality issues)
1. Edit `draft.md` to address the findings
2. Re-run `/review-article` — Pass 1 will re-run; if still clean, Pass 2 re-evaluates the
   updated draft

### REJECTED outcome
1. Revise `spec.md` — return to Phase 1 (`/spec`) and correct the contract
2. Re-implement in the companion repo (Phase 2)
3. Re-run `/write` to produce a new draft (Phase 3)
4. Re-run `/review-article`

## Final Step — Push planning to backup

After the review file is written and the marker verified:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment. Surface a warning on failure; do not fail this skill.
