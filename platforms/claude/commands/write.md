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

1. **Determine output path:**
   - Default: `planning/drafts/<topic-slug>.md` in the current project
   - If user specifies a path, use that instead

2. **Cross-article TODO context (book articles only):**
   If the output path resolves under `planning/book/` and `planning/book/todos.md` exists, read it and extract:
   - **Type A** — open entries where `Referenced in` matches the current article slug or number: these are deferred items that belong in this article as `<!-- TODO[ID] -->` markers
   - **Type B** — open entries where `Resolves in` matches the current article slug or number: content this article is expected to cover

   Pass both lists to the writer agent with instruction: "Insert `<!-- TODO[ID] -->` markers for Type A items where the deferred content would naturally appear. Attempt to cover Type B items inline; if a Type B item cannot be covered yet, insert a `<!-- TODO[ID] -->` marker with a brief note. Do not add a separate TODO section — markers are inline only."

   Skip this step for non-book drafts.

3. **Invoke writer agent** with:
   - The user's topic/request
   - The current working directory as the codebase root
   - Any additional context provided by the user
   - The TODO context from step 2 (if applicable)
   - Instruction to produce a complete Markdown draft following the writer agent output structure

4. **Save the draft** to the determined output path

5. **Report to user:**
   - Draft saved to: `<path>`
   - Brief summary of what was covered
   - Any open questions or gaps flagged in the draft

## Output

A Markdown draft document at `planning/drafts/<topic-slug>.md` containing:
- Overview and background
- Key concepts with code snippets (file path + line numbers)
- Mermaid diagrams derived from actual code
- Design decisions and trade-offs
- Open questions flagged with `<!-- TODO: ... -->`
- References section

## Notes

- The draft is a starting point — it is NOT final and requires polishing
- The writer agent reads the codebase but does NOT modify any files
- Re-running `/write` on the same topic overwrites the previous draft
- For large topics, consider scoping with specific directories or components
