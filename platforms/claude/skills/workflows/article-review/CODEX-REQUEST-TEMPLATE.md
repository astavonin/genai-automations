---
name: article-review-codex-request
description: Codex review-request template for /review-article — code and factual accuracy cross-check.
allowed-tools: Bash
compatibility: claude-code
---

# Article Review — Codex Review-Request Template

Write this document to `planning/reviews/<issue-slug>-article-codex-review.md` before
launching agents. The `Output File` field controls where codex-flow writes its findings;
the aggregation step reads from this exact path.

**`<issue-slug>` derivation:** use the folder name inside `issues/` (pattern `NNN-name`).
Example: `issues/007-vector-tables/` → `planning/reviews/007-vector-tables-article-codex-review.md`.

**Repository field:** use the **article project root** (the repo containing `planning/`),
NOT the companion code repo. This ensures `Output File` resolves under the repository.
Provide the companion code repo path in the Context section instead.

```markdown
# Review Request — <Article Title> — Code and Factual Accuracy

**Repository:** <absolute path to article project root — the repo containing planning/>
**Branch:** main
**Review Scope:** article prose and companion repo source files cited via annotations
**Output File:** planning/reviews/<issue-slug>-article-codex-review.md
**Date:** <today>

---

## Context

Code and factual accuracy review for article: <article title>.

**Companion code repo:** <absolute path to companion repo>
**Article:** planning/book/milestone-XX-<name>/issues/<NNN-name>/draft.md

The article references companion repo source files via `<!-- file: path:L10-L25 -->`
annotations and makes factual claims about external libraries, APIs, language semantics,
hardware/OS/protocol behaviour, and specifications. Verify only the items in Review Focus.
Do NOT assess prose quality, structure, audience calibration, completeness, or consistency.

*(If prior AC-prefixed findings exist in article-review.md, list each below with its
original Location and Evidence. Append: "This was a Codex-only finding in a prior review.
Re-raise if still present." Omit entirely if no prior AC findings exist.)*

---

## Requirements

Copy the bullet lines verbatim from the `## Codex Review-Request Requirements` section of
~/.claude/skills/workflows/article-review/SCOPES.md. Each line must start with `- `.
Do not use numbered lists or prose — codex-flow requires bullet format.

---

## Constraints

- For factual claims: cite the authoritative source (URL, spec section, RFC, version). A finding without a cited source is invalid.
- Do not flag prose style, structure, audience calibration, completeness, or consistency.
- Scope 1.1 (annotation present) is a mechanical check handled by Agent 1 — skip it.

---

## Evidence

```bash
# no build to run — article accuracy review
```

---

## Review Focus

- snippet-accuracy (1.2): snippet matches cited lines in companion repo
- numbers-match-code (1.3): numeric values in prose match implementation
- diagram-accuracy (1.4): diagrams accurate at their abstraction level
- external-api-accuracy (2.1): library API claims correct per official docs
- language-semantics-accuracy (2.2): language behaviour claims correct per spec
- hardware-os-accuracy (2.3): hardware/OS/syscall claims correct per documentation
- protocol-accuracy (2.4): protocol/wire format claims correct per RFC/spec
- performance-claims (2.5): performance characteristics correct per official sources

---

## Exclusions

- Annotation presence check (Scope 1.1) — handled by Agent 1
- Prose quality, completeness, internal consistency — out of scope for Codex
```
