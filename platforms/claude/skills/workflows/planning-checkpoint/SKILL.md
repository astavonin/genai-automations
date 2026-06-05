---
name: planning-checkpoint
description: Shared fragment — single-outcome planning state update + push. Called by research, design, and implement after recording a phase transition. Caller specifies new_phase, progress_line, and escalation level.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, planning, sync, push]
---

# Planning Checkpoint — Shared Fragment

Single-outcome planning state update followed by a push to backup. Called by any skill that records one definite phase transition (not a 3-way review outcome — use `review-planning-update` for that).

## Caller Must Specify (immediately before or after the Read call)

- **`new_phase`** — canonical phase label to set in the Phase column of `status.md` (from `planning/SKILL.md` vocabulary)
- **`progress_line`** — line to append or replace in the Active entry of `progress.md`
- **`escalation`** — `standard` (default) or `elevated` (`elevated` adds the "check before /complete" recovery line; use only for `/review-code`)

## Steps

### 1. Update `planning/<goal>/milestone-XX/status.md`

Set the Phase column for the active issue(s) to `new_phase`.

### 2. Update `planning/progress.md`

In the **Active** section, find the entry for the active issue(s). Replace or append `progress_line`. Update `**Last Updated:**` to today's date.

### 3. Push to backup immediately

Push must fire **before** any blocking step (approval wait, user confirmation):

```bash
projctl sync push
```

**On success:** continue normally.

**On failure (standard escalation):**
```
⚠️  workflow-safety: planning push failed after <skill-name>
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually when backup is available
```

**On failure (elevated escalation — /review-code only):**
```
⚠️  workflow-safety: planning push failed after /review-code
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually; also run `projctl sync status`
              before /complete to verify no drift has accumulated across machines
```

Do not fail the calling skill — return success after surfacing the warning.
