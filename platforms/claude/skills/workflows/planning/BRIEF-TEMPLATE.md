# `brief.md` template

Every `brief.md` produced by `/write` in book-article mode MUST follow this structure. The brief is a **fact-verified article-writing brief**, not a first-pass article. It carries verified facts (line ranges, commit hash, test list, API signatures), article intent (theory scope, reader arc, section outline, A-page dependencies, diagram list), and structural guidance. It does not carry theory prose, article prose, or narrative — that is Web-Claude's job in the subsequent step.

**Consumed by:** Web-Claude (fresh session), which reads `spec.md` + `brief.md` + relevant A-pages and writes the actual `draft.md`.

**Related:**
- `SPEC-TEMPLATE.md` — the coding contract this brief's facts are drawn from.
- `platforms/claude/skills/workflows/article-review/SCOPES.md` — the review scopes the resulting draft is measured against.
- `planning/style-guide.md` (in the book repo) — governs brief prose and enforces GitHub permalink format for code refs.

## Structure

```markdown
# Brief — <Article Title>

**Article:** <NNN-slug>
**Part:** <part number> — <part title>
**Companion repo (local):** <absolute path from CLAUDE.local.md>
**Companion repo (github):** <owner>/<repo-slug> (used in GitHub permalinks)
**Companion repo commit:** <full commit hash captured at brief-writing time>
**Spec:** <path to spec.md>
**Style guide:** `planning/style-guide.md` — version <auto-extracted from `^Version:\s*(.+?)\s*$` in first 10 lines, e.g. `1.5`; `version-unknown` if line absent>

---

## 1. Article Identity

**G2G frame.** <1–2 sentences describing what pipeline slice this article walks. Reader-facing "what this article is about" framed as a G2G concern, not a Rust API concern.>

**Title.** <Reworked title using pipeline concept, not code artifact.>

**Position in book.** <Which article precedes this one, what the reader knows entering; which article follows, what the reader will know leaving.>

---

## 2. Reader Arc

**Reader arrives knowing:**
- <bullet points describing prerequisite knowledge from previous articles and A-pages>

**Reader leaves knowing:**
- <bullet points describing what the article delivers>

**Language-neutrality test.** <One paragraph confirming that a C++/Zig/Go systems engineer at the audience baseline can follow the article without prior Rust knowledge. If the article requires Rust-specific knowledge for its argument, flag which sections and why.>

---

## 3. Theory Scope

Concepts the article's front-half walks the reader through. Each item is a walking-tour concept, not a deep dive — depth lives in A-pages.

- **<Concept 1>**: <one-line description of what the article covers about this> — depth reference: <A-page name, or "none — this article carries the depth">
- **<Concept 2>**: <same>
- ...

**Explicitly out of theory scope for this article** (belongs in A-pages or later articles):
- <bullet points>

---

## 4. A-page Dependencies

Every A-page the article will link to.

| A-page | Title | Existence | Depth available |
|--------|-------|-----------|-----------------|
| A1 | <A-page title> | Published / Planned / Missing | <what's there, or what needs to be there before this article ships> |
| A2 | ... | ... | ... |

If no A-pages exist yet, replace the table with: `(none — no A-pages currently exist; article synthesizes theory inline)`. If status.md notes planned A-pages that don't exist yet, list them under the "must be written before this article ships" line as `Missing`.

**A-page dependencies that must be written before this article ships:** <list, or "none">

**A-page dependencies acceptable as `planned` links:** <list, or "none" — these appear inline as "planned in Part X" notes>

---

## 5. Section Outline

Section-by-section skeleton with line budgets. Section names use pipeline framing, not code-artifact framing ("What V4L2 promises when you ask for a format", not "`Format` (requested) vs `FrameLayout` (negotiated)").

1. **<Section name>** (~<N> lines) — <one-line description of what this section covers>
2. **<Section name>** (~<N> lines) — <same>
3. ...

**Total target length:** ~<N> lines (pipeline-walking articles are typically 700–1000 lines; length follows content, not the other way around).

---

## 6. Diagram List

Diagrams needed for the article. Excalidraw authoring happens in Web-Claude sessions; this section specifies WHAT is needed, not the diagram content.

| Diagram | Purpose | Placement | Mermaid concept sketch |
|---------|---------|-----------|------------------------|
| `img/NN-<slug>.png` | <what it shows> | <which section> | <ASCII or Mermaid rough concept for Web-Claude to iterate from before rebuilding in Excalidraw> |
| ... | ... | ... | ... |

---

## 7. Verified Facts

Every fact in this section MUST be verified against the companion repo state at the commit hash in the metadata block.

**Rendering note for all §7 subsections:** every code reference below (in tables, excerpt headings, and API-signature headings) MUST render as a GitHub permalink of the form `` [`src/file.rs:N-M`](https://github.com/<owner>/<repo>/blob/<hash>/src/file.rs#LN-LM) `` — where `<owner>`, `<repo>` come from the `Companion repo (github)` metadata field and `<hash>` from `Companion repo commit`. The tables and headings below split `File` / `Range` columns and use plain `path:LN-LM` in headings **only for template readability**; the writer agent MUST emit the permalink form in the actual brief. If the commit hash is `<unknown>` (2g WARN case, see Rules), fall back to plain `` `src/file.rs:N-M` `` with no URL — see the plain-path fallback rule under `## Rules`.

### 7.1 Line-range table

Every code range the article will reference.

| File | Range | Purpose in article | Verified |
|------|-------|-------------------|----------|
| `src/session.rs` | 431–477 | `negotiate_format` loop (Section 12) | ✓ |
| `src/traits.rs` | 40–53 | `Format` struct definition (Section 9) | ✓ |
| ... | ... | ... | ... |

*Actual brief renders each `File`+`Range` cell pair as one permalink cell per the Rendering note above.*

### 7.2 Code excerpts to include verbatim

For excerpts under ~30 lines that will appear in the article body, include the exact code text so Web-Claude does not have to re-fetch. For larger blocks that will be summarized (not shown verbatim), include just the permalink and a one-sentence purpose note under §7.1 above.

**Excerpt A: `src/traits.rs:40-53` (Format struct)**
```rust
<full code text captured verbatim from the companion repo at the metadata commit hash>
```

**Excerpt B: `src/traits.rs:653-675` (torn-frame regression test)**
```rust
<full code text captured verbatim>
```

...

*Actual brief renders each excerpt heading with the permalink form per the Rendering note above (e.g. `**Excerpt A: [`src/traits.rs:40-53`](https://github.com/<owner>/<repo>/blob/<hash>/src/traits.rs#L40-L53) (Format struct)**`).*

### 7.3 Test list

Every test named in the spec, verified against the code. If the spec lists no tests, write `(none — spec defines no tests)` here and record a §9 uncertainty flag noting the empty test surface.

| Test name | File | Range | What it proves |
|-----------|------|-------|----------------|
| `test_pixel_at_uses_stride_not_width_for_row_offset` | `src/traits.rs` | 653–675 | Torn-frame regression: `pixel_at` computes row offset from driver stride, not `width * bpp`. |
| ... | ... | ... | ... |

*Actual brief renders each `File`+`Range` cell pair as one permalink cell per the Rendering note above.*

### 7.4 API signatures

Struct, enum, and trait definitions to reference in the article. Captured from **current code**, not the spec's version.

**`Format`** (`src/traits.rs:40-53`)
```rust
pub struct Format {
    pub width: u32,
    pub height: u32,
    pub fourcc: FourCC,
    pub stride: u32,
    pub size: u32,
}
```

**`FrameLayout`** (`src/traits.rs:81-94`)
```rust
<current definition>
```

...

*Actual brief renders each signature heading with the permalink form per the Rendering note above.*

### 7.5 Numeric facts

Concrete numbers the article uses. Source of each is captured.

| Value | Source | Purpose |
|-------|--------|---------|
| Pi 5 cache line size: 64 bytes | Cortex-A76 TRM §<section> | Explains DMA alignment in stride discussion (Section 4) |
| IMX708 pixel clock at 2304×1296 mode: <value> | A1 §Sensor Modes | Explains sensor jitter physics (Section 6) |
| ... | ... | ... |

---

## 8. External Citations Needed

Footnote-worthy external sources the article will cite. Web-Claude verifies via search at draft time; brief lists what needs citing.

- **[<citation label>]** <what claim is being cited> — recommended source: <URL or reference>
- ...

---

## 9. Uncertainty Flags

Claims the writer agent could not verify with high confidence. Web-Claude and `/review-article` handle these.

- **[VERIFY: <specific claim>]** — <context: where in the brief this claim appears, what needs verifying>
- ...

**Missing context files** (recorded by `/write` at brief-writing time when a non-blocking file was absent):
- <e.g. "overview.md missing at planning/book/overview.md — part number and position-in-book fields left as `<unknown>`"; or "no A-pages found at docs/appendix/A*.md — §4 table lists all planned dependencies as `Missing`">

---

## 10. TODO Integration

### Type A — Inline placeholders to include in draft

`<!-- TODO[ID] -->` markers to insert at specific section positions, per Type A rules in `article-review/TODOS.md`.

- **`TODO[<ID>]`** — <description from todos.md> — insert at <section>

### Type B — Resolution TODOs this article should close

Content this article is expected to cover per Type B rules.

- **`TODO[<ID>]`** — <description from todos.md> — planned coverage at <section>

---

## 11. Style Guide Compliance Target

- Version: <auto-extracted from `^Version:\s*(.+?)\s*$` in first 10 lines of `planning/style-guide.md`; matches metadata block at top of brief.md>
- Applicable rules: <bullet list of style-guide sections particularly relevant to this article, e.g. "Code Integration density target", "No em-dashes", "Pipeline framing in section headers">
- AI-detection patterns to actively watch: <copied verbatim from the AI-detection heading in `planning/style-guide.md` — do not paraphrase; if the section cannot be found, write `patterns-unavailable`>
- **Note:** This §11 is the style contract for **both** the brief's own minimal prose AND the `draft.md` that Web-Claude writes. Web-Claude MUST read `planning/style-guide.md` before writing `draft.md`; `/review-article` will fail `draft.md` against the rules named here.
```

## Rules

- **Metadata block is required.** Every field in the frontmatter (Article, Part, Companion repo (local), Companion repo (github), Companion repo commit, Spec, Style guide) MUST be populated by the writer agent before the brief is considered complete. If a field cannot be resolved, use `<unknown>` and add an Uncertainty Flag in §9 — do NOT silently omit. For `Companion repo (github)`, parse `owner/repo` from `git remote get-url origin` in the companion repo if CLAUDE.local.md does not carry a GitHub slug column.
- **All 11 sections are required.** If a section is genuinely N/A for this article (e.g. no external citations), keep the section header and write `(none)` under it. Never delete a section — downstream reviewers rely on the fixed structure.
- **Every code reference uses the GitHub permalink format.** ``[`src/file.rs:N-M`](https://github.com/<owner>/<repo>/blob/<commit-hash>/src/file.rs#LN-LM)`` where `<commit-hash>` is the full hash from the metadata block. The `<!-- file: path:LN-LM -->` HTML comment format is NOT accepted in briefs (it is only accepted in legacy published articles per SCOPES.md 1.1). **If commit hash is `<unknown>`**, emit code references as `` `src/file.rs:N-M` `` (plain path, no URL) and flag every affected entry in §7.1 with a `[VERIFY: commit hash unresolved]` note. Do NOT emit a permalink with `<unknown>` in the URL slot — GitHub will render a 404.
- **Verified facts are traceable.** Every line range in §7.1 corresponds to a read the writer agent performed against the companion repo at the metadata commit hash. Every test in §7.3 is verified against the file, not against the spec text. Every API signature in §7.4 is captured from the current code, not from the spec.
- **Theory scope is stated, not omitted.** §3 must enumerate what the front-half covers. "Whatever the article touches" is not a valid entry.
- **Uncertainty is flagged, not hidden.** Any claim the writer agent cannot verify with high confidence lands in §9 as `[VERIFY: <specific claim>]`. Missing context files (non-blocking WARN cases from `/write` book mode) are also recorded in §9's "Missing context files" subsection — not as `[VERIFY:]` bullets.
- **Diagrams are specifications, not artifacts.** §6 describes what diagrams the article needs. It does NOT contain the diagrams themselves — Excalidraw authoring happens in Web-Claude sessions.
- **The brief is not a draft.** No article prose, no reader-facing narrative, no first-pass theory explanations. The brief is raw material Web-Claude writes from. If prose accumulates in the brief, the writer agent is straying from its Book Article Mode remit.

## When to use

`brief.md` is produced by `/write` when the output path resolves under `planning/book/` (book-article mode). For non-book uses of `/write`, the writer agent produces `draft.md` with its default output structure — this template does not apply.
