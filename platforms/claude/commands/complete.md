---
name: complete
description: Mark work complete and update progress tracking
---

# Completion Command

Mark work as complete and update progress tracking files.

## Prerequisites

Before running this command:
- ✅ Code review approved
- ✅ All verification checks passed
- ✅ User confirms issue is complete
- ✅ User handled git commits (Phase 7)

## Actions

1. **Propose update to progress.md:**
   - Explicitly state intention to update
   - Wait for user confirmation
   - DO NOT update automatically

2. **Update progress.md** (after confirmation):
   - Mark completed tasks
   - Update active work section
   - Add timestamp

3. **Update milestone status.md** (if needed):
   - Update epic/issue completion status
   - Recalculate completion percentage
   - Update blockers if resolved

4. **Archive design documents** (if milestone complete):
   - Move or delete temporary design artifacts
   - Update overview.md to mark milestone complete

5. **Clean up internal plan files:**
   ```bash
   rm -f ~/.claude/plans/*.md
   ```
   Leftover plan files in `~/.claude/plans/` cause Claude Code to re-enter plan mode
   automatically at the next session start, which blocks the normal workflow.

## Critical Rules

- ⚠️ **NEVER update planning files automatically**
- ⚠️ **ALWAYS propose explicitly and wait for user confirmation**
- ⚠️ **Assume work is complete ONLY after user confirms**

## Usage Pattern

```
"The implementation is complete and all checks have passed.
I propose updating planning/progress.md to mark [task] as complete.
Should I proceed?"
```

Wait for user response before updating any files.
