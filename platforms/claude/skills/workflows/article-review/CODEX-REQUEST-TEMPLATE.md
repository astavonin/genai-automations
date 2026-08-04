---
name: article-review-codex-request
description: Codex review-request template for /review-article — code and factual accuracy cross-check.
allowed-tools: Bash
compatibility: claude-code
---

# Article Review — Codex Review-Request Template

Write this document to `<issue-folder>/article-codex-review-request.md` before launching agents.
`<issue-folder>` is the page-type-resolved path per `~/.claude/skills/workflows/page-type/SKILL.md`
(`main` or `appendix`) — the same path `/review-article` Setup resolved. The `Output File` field
controls where codex-flow writes its findings; the aggregation step reads from
`article-codex-review.md` (Codex output) at the same issue path — not this request file.

**Naming distinction:** `article-codex-review-request.md` is the input Codex reads; `article-codex-review.md` is the output Codex writes. They are different files. Write this template as the request; the aggregation step reads the output.

**Repository field:** use the **article project root** (the repo containing `planning/`),
NOT the companion code repo. This ensures `Output File` resolves under the repository.
Provide the companion code repo path in the Context section instead.

~~~markdown
# Review Request — <Article Title> — Code and Factual Accuracy

**Repository:** <absolute path to article project root — the repo containing planning/>
**Branch:** main
**Review Scope:** article factual claims; companion repo source files cited via annotations (main pages only — an appendix page cites no code, see `page-type/SKILL.md` → Resolution)
**Output File:** <issue-folder>/article-codex-review.md
**Date:** <today>

---

## Context

Code and factual accuracy review for article: <article title>.

**Companion code repo:** <absolute path to companion repo, or "n/a — appendix page">
**Article:** <issue-folder>/draft.md

The article references companion repo source files by GitHub permalink (`blob/<hash>/<path>#LN-LM`), or by the legacy `<!-- file: path:L10-L25 -->` comment in already-published drafts (main pages only — an appendix page never cites code). It also makes factual claims about external libraries, APIs, language semantics,
hardware/OS/protocol behaviour, and specifications. Verify only the items in Review Focus.
Do NOT assess prose quality, structure, audience calibration, completeness, or consistency.

*(If prior AC-prefixed findings exist in article-review.md, list each below with its
original Location and Evidence. Append: "This was a Codex-only finding in a prior review.
Re-raise if still present." Omit entirely if no prior AC findings exist.)*

---

## Requirements

Copy the bullet lines verbatim from the `## Codex Review-Request Requirements` section of
~/.claude/skills/workflows/article-review/SCOPES.md, selecting the bullets applicable to the
resolved page type per `/review-article` Step 1. Each line must start with `- `.
Do not use numbered lists or prose — codex-flow requires bullet format.

---

## Constraints

- For factual claims: cite the authoritative source (URL, spec section, RFC, version). A finding without a cited source is invalid.
- Do not flag prose style, structure, audience calibration, completeness, or consistency.
- Scope 1.1 (annotation present) is a mechanical check handled by Agent 1 — skip it.
- Cite companion-repo code as `<short-hash>:path:line` using the article-wide commit hash from the draft's metadata block, or as file + symbol. A bare `path:line` is not a durable locator. Reference the article itself by section, never by line. This review runs with `--ignore-user-config --ignore-rules`, so this line is the only channel carrying the rule into it. (main only — an appendix page has no commit hash to cite; its metadata fields read `n/a — appendix page`.)

---

## Observed-Failure Ledger

No ledger exists for this work — article review.

<!-- Required by codex-flow's review-request parser. An article review has no code diff and
     therefore no observed-failure ledger; state that explicitly rather than omitting the
     section, which the parser rejects. -->

---

## Evidence

```bash
# no build to run — article accuracy review
```

---

## Review Focus

- external-api-accuracy (2.1): library API claims correct per official docs
- language-semantics-accuracy (2.2): language behaviour claims correct per spec
- hardware-os-accuracy (2.3): hardware/OS/syscall claims correct per documentation
- protocol-accuracy (2.4): protocol/wire format claims correct per RFC/spec
- performance-claims (2.5): performance characteristics correct per official sources
- snippet-accuracy (1.2, main only): snippet matches cited lines in companion repo
- numbers-match-code (1.3, main only): numeric values in prose match implementation
- diagram-accuracy (1.4, main only): diagrams accurate at their abstraction level

---

## Exclusions

- Annotation presence check (Scope 1.1) — handled by Agent 1
- Prose quality, completeness, internal consistency — out of scope for Codex
- Code-accuracy criteria (1.2, 1.3, 1.4) for an appendix page — Scope 1 is suppressed entirely per `SCOPES.md` Scope 2A; an A-page never cites code
~~~
