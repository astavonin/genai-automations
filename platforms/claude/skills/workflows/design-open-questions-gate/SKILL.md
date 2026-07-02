---
name: design-open-questions-gate
description: Pre-flight gate used by /review-design and /review-design-fix-loop. Blocks any review pass if design.md Open Questions section contains unresolved open questions. Read this fragment before launching any reviewer agents.
---

# Design Open Questions Gate

A design with unresolved open questions in the Open Questions section must not proceed to review — questions must be resolved via `/design` first.

## Check

**Step 1 — Verify file exists.** If `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` does not exist, the **gate fails**. Stop immediately and surface:

```
design.md not found at <path> — run /design first.
```

**Step 2 — Locate the Open Questions section.** Search for a heading that matches the pattern `## <number>. Open Questions` (case-sensitive, any section number — e.g. `## 7. Open Questions` or `## 8. Open Questions`). If no such heading exists in the file, the gate **passes** — the section is absent.

**Step 3 — Inspect the section body.** Read the content between the Open Questions heading and the next `##`-level heading (or end of file). The gate **passes** if the body is one of:

- Empty (whitespace only)
- Contains only checked checkboxes: `- [x] ...` (all items checked)
- Contains only a "none" note: any line that includes the word "none", "n/a", "no open questions", or the template placeholder `*(None` (case-insensitive)

The gate **fails** if the body contains **any** unchecked checkbox: `- [ ] ...`

Count the number of failing items (unchecked checkboxes). Any other text in the section (prose, `**Q:**` entries, numbered items) that does not match the passing patterns above is also treated as a failing item and counted.

**Note on checked items:** Checked checkboxes (`- [x] ...`) pass the gate because they represent resolved questions, not open ones. The `/design` Step 5 loop removes all items (checked and unchecked) from the Open Questions section as part of cleanup, so a clean design.md should not have either. If `- [x]` items appear at review time, they are harmless artifacts that the reviewer can assess; they do not block review.

## Action on failure

**The gate fails.** Stop immediately. Do not proceed to any review step. Do not launch any reviewer agents. Do not write a review file. Surface to the user:

```
Design is INCOMPLETE — Open Questions section contains N open question(s):
1. <first line of first unchecked item, checkbox prefix stripped>
...
Resolve all open questions via `/design` before requesting review.
```

where N is the total count of failing items, and each numbered line lists the first line of each failing item with its checkbox/list prefix stripped.
