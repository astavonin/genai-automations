---
name: design-revision-bump
description: Increment **Revision:** in design.md; insert the field if absent. Call at every exit point where design_modified is true.
---

# Design Revision Bump

Increment `**Revision:**` in the design doc. Run this at every terminal stop where `design_modified = true` — both normal completion and early exits (gate re-fire, blocker, stall, CHANGES REQUESTED).

## Procedure

Locate the design doc path (same path used throughout the calling command: `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`).

1. Check whether the field exists:
   ```bash
   grep -c '^\*\*Revision:\*\*' path/to/design.md
   ```
2. If the count is 0, use the Edit tool to insert `**Revision:** 1` immediately after the `**Status:** ...` line. Set `old_string` to the current Status line and `new_string` to the same line followed by a newline and `**Revision:** 1` — for example, if the doc has `**Status:** Draft`, use `old_string = '**Status:** Draft'` and `new_string = '**Status:** Draft\n**Revision:** 1'`. If no `**Status:**` line is present, locate the first H1 line by running `grep -n '^# ' path/to/design.md | head -1` and capture the exact line text. Insert `**Revision:** 1` after it using the Edit tool with `old_string = '<H1 line text>'` and `new_string = '<H1 line text>\n**Revision:** 1'` (substituting the actual H1 text — for example, if the line is `# My Design`, use `old_string = '# My Design'` and `new_string = '# My Design\n**Revision:** 1'`). If neither is present, stop and surface: "Design doc is missing both `**Status:**` and H1 title — manual correction needed in design.md." (Note: a legacy doc without a prior `**Revision:**` field will end this run at Revision 2 — 1 inserted as baseline, then bumped once. Revision 1 represents the pre-tracking state; Revision 2 is the first tracked fix session.)
3. Read the current integer value (call it `X`) by running:
   ```bash
   grep -oP '(?<=^\*\*Revision:\*\* )\d+' path/to/design.md
   ```
   If the grep returns no match or a non-integer, stop and surface: "Revision field malformed — manual correction needed in design.md." Otherwise, use the Edit tool with `old_string = '**Revision:** <X>'` (the current integer) and `new_string = '**Revision:** <X+1>'` (the incremented integer) — for example, `old_string = '**Revision:** 3'` and `new_string = '**Revision:** 4'`.
