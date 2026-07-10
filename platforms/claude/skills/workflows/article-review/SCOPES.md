---
name: article-review-scopes
description: Five verification scopes for /review-article — criteria, confirmation methods, severities, and Codex label mapping.
allowed-tools: Bash
compatibility: claude-code
---

# Article Review — Verification Scopes

Five scopes across three agents. Each criterion specifies what to check, how to confirm
it, and what to include as evidence in the finding.

## Scope 1 — Code Accuracy *(Agent 1)*

Every criterion is confirmed by direct inspection of the companion repo.

1. **Annotation present** — every code snippet has a `<!-- file: path:L10-L25 -->` annotation.
   Confirm: mechanical check — present or absent on every snippet in the article.
   Severity: **High** (without annotation, accuracy cannot be verified).

2. **Snippet accurate** — snippet content matches the exact lines at the cited path and
   line range in the companion repo.
   Confirm: read the file at `path:L10-L25`; compare character by character; quote any
   divergence.
   Severity: **High** (reader following wrong code is a direct harm).

3. **Numbers match implementation** — every numeric constant, threshold, or measured value
   cited in prose matches the companion repo.
   Confirm: grep for the value in the companion repo; cite `file:line`.
   Severity: **High**.

4. **Diagrams accurate** — diagrams must not contradict the companion repo or the spec.
   Accuracy requirement depends on diagram abstraction level:
   - *Code-level diagrams* (show structs, call flows, memory layout, or execution paths
     with code-level constructs): confirm by tracing the code path; cite `file:line`;
     describe the actual structure and where the diagram diverges. Severity: **High** if
     contradicts code; **Low** if omits detail.
   - *Higher-level diagrams* (system architecture, conceptual model, protocol overview at
     design level): confirm they do not contradict any fact in the companion repo or spec;
     no 1:1 code mapping required. Severity: **High** if factually wrong; no finding if
     merely simplified.
   Confirm the abstraction level first, then apply the appropriate check.

---

## Scope 2 — Facts Accuracy *(Agent 2)*

Every finding must cite the authoritative source consulted (URL, spec section, version,
RFC number). Findings without a cited source are invalid.

1. **External library API claims** — description of a library's API, return values, error
   conditions, or semantics.
   Confirm: check the library's official documentation or source code.
   Cite: URL or `file:line` in the library source; note the library version.
   Severity: **High**.

2. **Language semantics claims** — claims about language behaviour: ownership, memory
   layout, scheduling, undefined behaviour, exception guarantees, etc.
   Confirm: check the language specification or authoritative reference (Rust Reference,
   C++ Standard, Go spec, Java Language Specification, POSIX, etc.).
   Cite: document name and section number.
   Severity: **High**.

3. **Hardware and OS interface claims** — claims about hardware registers, CPU behaviour,
   kernel interfaces, system calls, memory-mapped I/O.
   Confirm: check the datasheet, kernel documentation (`kernel.org/doc`, man pages), or
   POSIX spec.
   Cite: document name, section, or URL.
   Severity: **High**.

4. **Protocol and wire format claims** — claims about protocol behaviour, packet formats,
   field semantics, or timing.
   Confirm: check the RFC or protocol specification.
   Cite: RFC number and section.
   Severity: **High**.

5. **Performance characteristic claims about external systems** — latency, throughput,
   resource usage attributed to an external library, OS, or hardware component.
   Confirm: check official benchmarks, documentation, or published papers.
   Cite: source URL or paper reference.
   Severity: **Medium** unless presented as a hard guarantee, in which case **High**.

---

## Scope 3 — Prose Accuracy *(Agent 3)*

Confirm each finding by quoting the specific passage that violates the criterion.
Cite the article section heading and approximate location.

1. **WHY before HOW** — every section opens with motivation before mechanics.
   Confirm: quote the opening sentence(s); note where motivation is absent.
   Severity: **High** if a core section jumps straight to code; **Medium** otherwise.

2. **No over-explanation** — the article does not define concepts the target audience
   already knows. Use the "Technical Familiarity" baseline provided in the agent prompt.
   Confirm: quote the over-explained passage; cite the baseline used.
   Severity: **High** if pervasive; **Medium** if occasional.

3. **Trade-offs named** — design decisions cite what was given up, not only what was chosen.
   Confirm: quote the decision passage; state which trade-off is absent.
   Severity: **Medium**.

4. **Direct voice** — no hedging words ("might", "could potentially", "arguably"), no
   preamble before the point.
   Confirm: quote the hedging passage.
   Severity: **Low**.

5. **No section duplication** — the same information does not appear in two places.
   Confirm: cite both locations with section headings.
   Severity: **Medium**.

6. **Heading hierarchy** — each heading maps to a distinct concept; no heading merely
   restates its parent heading.
   Confirm: quote the heading pair.
   Severity: **Low**.

---

## Scope 4 — Completeness *(Agent 3)*

Confirm each finding by citing what is promised or expected and where it is missing.
The spec is provided as context for what the article is supposed to cover.

1. **Opening promise kept** — the article covers every topic claimed in the opening paragraph.
   Confirm: list promised topics; for each missing one quote the opening claim and identify
   the gap.
   Severity: **High** if a core promised topic is absent.

2. **No stranded reader** — the reader has enough context to extend or debug the code.
   Confirm: identify the specific gap — what a reader would need that the article omits.
   Severity: **Medium**.

3. **Key failure modes addressed** — known implementation limitations are acknowledged.
   Confirm: cite the failure mode from the companion repo; note whether the article
   acknowledges it.
   Severity: **Medium**.

4. **Scope coverage noted** — uncovered public surface is explicitly excluded with a note.
   Confirm: identify uncovered surface; note whether an exclusion note exists.
   Severity: **Low**.

5. **No inline TODO placeholders** — the article must not contain any `<!-- TODO[ID] -->` comment. These markers indicate deferred or unresolved content registered in `planning/book/todos.md` and are publication blockers.
   Confirm: search the article for `<!-- TODO[` — cite every occurrence with its section heading.
   Severity: **High**.

---

## Scope 5 — Internal Consistency *(Agent 3)*

Every finding must cite all locations where the contradiction appears, with quoted text.

1. **Numbers consistent** — the same constant, threshold, or measured value is cited the
   same way throughout.
   Confirm: cite all locations; quote the divergent values.
   Severity: **High**.

2. **Terminology consistent** — the same concept is referred to by the same name throughout.
   Confirm: list all names used; cite all locations.
   Severity: **Medium**.

3. **Design decision descriptions consistent** — the same decision is described the same
   way in introduction, deep-dive, and conclusion.
   Confirm: quote the divergent descriptions and cite their locations.
   Severity: **High** if contradictory; **Medium** if only emphasis differs.

4. **Code examples consistent with prose** — when prose describes a behaviour, code
   examples illustrate the same behaviour.
   Confirm: quote the prose claim; cite the code example that contradicts it.
   Severity: **High**.

5. **No cross-section contradictions** — claims in one section do not contradict another.
   Confirm: quote both contradicting statements with their section locations.
   Severity: **High** if a reader would be directly misled.

---

## Codex Review-Request Requirements

Copy these bullet lines verbatim into the `## Requirements` section of the Codex
review-request document. codex-flow requires `- ` bullet format; do not use numbered
lists or free text in that section.

- **Snippet accurate (1.2):** snippet content matches the exact lines at the cited `path:L10-L25` in the companion repo; compare character by character and quote any divergence. Severity: High.
- **Numbers match implementation (1.3):** every numeric constant, threshold, or measured value cited in prose matches the companion repo; grep for the value and cite file:line. Severity: High.
- **Diagrams accurate (1.4):** code-level diagrams must match actual runtime structure/flow (trace code path, cite file:line); higher-level diagrams must not contradict any fact in the companion repo or spec. Severity: High if factually wrong, Low if merely simplified.
- **External library API claims (2.1):** check the library's official documentation or source code; cite URL or file:line plus library version. Severity: High.
- **Language semantics claims (2.2):** check the language specification or authoritative reference (Rust Reference, C++ Standard, Go spec, POSIX, etc.); cite document name and section number. Severity: High.
- **Hardware and OS interface claims (2.3):** check the datasheet, kernel documentation (kernel.org/doc, man pages), or POSIX spec; cite document name, section, or URL. Severity: High.
- **Protocol and wire format claims (2.4):** check the RFC or protocol specification; cite RFC number and section. Severity: High.
- **Performance characteristic claims about external systems (2.5):** check official benchmarks, documentation, or published papers; cite source URL or paper reference. Severity: Medium unless presented as a hard guarantee, in which case High.

---

## Codex Label → Scope Criterion Mapping

Used during aggregation to deduplicate Codex findings against Claude findings.

| Codex label | Scope criterion |
|-------------|----------------|
| `snippet-accuracy` | Scope 1.2 — Snippet accurate |
| `numbers-match-code` | Scope 1.3 — Numbers match implementation |
| `diagram-accuracy` | Scope 1.4 — Diagrams accurate |
| `external-api-accuracy` | Scope 2.1 — External library API claims |
| `language-semantics-accuracy` | Scope 2.2 — Language semantics claims |
| `hardware-os-accuracy` | Scope 2.3 — Hardware and OS interface claims |
| `protocol-accuracy` | Scope 2.4 — Protocol and wire format claims |
| `performance-claims` | Scope 2.5 — Performance characteristic claims |
