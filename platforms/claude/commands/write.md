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
/write how the Yocto CI cache strategy works
/write the Anki sync pull handler design
/write overview of ci-platform-manager architecture
```

Optional context the user may provide:
- Specific files or directories to focus on
- Target audience (self-reference, team doc, blog post, etc.)
- Depth level (overview vs. deep dive)

## Actions

1. **Determine output path:**
   - Default: `planning/drafts/<topic-slug>.md` in the current project
   - If user specifies a path, use that instead

2. **Invoke writer agent** with:
   - The user's topic/request
   - The current working directory as the codebase root
   - Any additional context provided by the user
   - Instruction to produce a complete Markdown draft following the writer agent output structure

3. **Save the draft** to the determined output path

4. **Report to user:**
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
