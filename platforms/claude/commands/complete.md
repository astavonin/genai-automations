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
