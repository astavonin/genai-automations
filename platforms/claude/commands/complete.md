---
name: complete
description: Mark work complete and update progress tracking
---

# Completion Command

Mark work as complete and update progress tracking files.

## Setup

Read planning skill before starting:
```
Read ~/.claude/skills/workflows/planning/SKILL.md
```

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

6. **Sync planning state to backup:**
   ```bash
   projctl sync push
   ```
   Pushes updated planning files to Google Drive backup, making them available on all machines.
   Record whether this push succeeded (needed for the compaction gate below).

7. **Gated auto-compact (last step, §7.5)**

   Evaluate three disk-checkable conditions. All three must pass for compaction to fire.

   **Condition 1 — git clean outside planning:**
   ```bash
   git status --porcelain | grep -v '^??' | grep -v '^.. planning/' # check for uncommitted tracked changes outside planning/
   ```
   More precisely: `git status --porcelain` must report no uncommitted changes in tracked files outside of `planning/`. (`planning/` edits from this `/complete` invocation are OK.)

   **Condition 2 — sync push succeeded:**
   The `projctl sync push` in step 6 of this invocation must have returned exit code 0.

   **Condition 3 — post-push status is in-sync:**
   ```bash
   projctl sync status
   ```
   Parse the first line. Must be `STATUS: in-sync`.

   **If all three conditions pass:**
   - Log to gate-decision log: append one line to `planning/.workflow-safety.log`:
     ```
     <ISO-8601 timestamp> /complete complete-end FIRED
     ```
   - Trigger compaction (automatic, no prompt per §7.8).
   - After successful compaction, emit:
     ```
     ✓ Compacted at complete-end (N messages summarized)
     ```

   **If any condition fails:**
   - Log to gate-decision log: append one line to `planning/.workflow-safety.log`:
     ```
     <ISO-8601 timestamp> /complete complete-end SKIPPED <failing-condition>
     ```
     Where `<failing-condition>` is one of: `precondition-1-failed:uncommitted-changes`, `precondition-2-failed:push-failed`, `precondition-3-failed:STATUS=<value>`.
   - Surface warning:
     ```
     ⚠️  workflow-safety: compaction skipped at /complete
         reason: <specific failing condition>
         recovery: resolve the condition and run /complete again, or compact manually
     ```
   - Do NOT compact. Return success (incomplete compaction is not a workflow failure).

   **If all conditions pass but compaction itself fails:**
   - Log: `<ISO-8601 timestamp> /complete complete-end SKIPPED compact-failed`
   - Surface: `⚠️  workflow-safety: compaction failed at complete-end — session left uncompacted (all artifacts are durable)`
   - Return success. The session is fully durable; an uncompacted session is functionally equivalent to pre-design behavior.

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
