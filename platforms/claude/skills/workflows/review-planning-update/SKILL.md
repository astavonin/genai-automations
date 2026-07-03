---
name: review-planning-update
description: Shared fragment — 3-way review outcome planning update + push. Called by review-design, review-code, review-fix after the status marker is verified. Caller specifies approved_phase, review_label, approved_next, and escalation.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, planning, review, sync, push]
---

# Review Planning Update — Shared Fragment

Three-way planning state update (APPROVED / CHANGES REQUESTED / REJECTED) followed by push to backup. Called by any review skill after the status marker has been verified. Push fires **before** any blocking approval step.

## Caller Must Specify (immediately before the Read call)

- **`approved_phase`** — canonical phase label to set when APPROVED (e.g., `implementing 🔨`, `code review ✅`)
- **`review_label`** — short human label for the review type (e.g., `design review`, `code review`, `fix review`)
- **`approved_next`** — what comes next after approval (e.g., `ready for implementation`, `ready for MR`)
- **`escalation`** — `standard` or `elevated` (`elevated` for `/review-code` adds the "check before /complete" line)

## Steps

### 1. Update `planning/<goal>/milestone-XX/status.md` (canonical phase vocabulary)

Note: `milestone-XX` is a pattern — substitute the actual folder name, including any name suffix (e.g., `milestone-01-foundations`). For the article workflow, `goal=book` and the full folder name (with suffix) must be used.

- `APPROVED` → set Phase to `approved_phase`
- `CHANGES REQUESTED` → set Phase to `changes requested 🔄`
- `REJECTED` → set Phase to `rejected ❌`

### 2. Update `planning/progress.md`

In the **Active** section, find the entry for the reviewed issue(s). Replace or append:

- `APPROVED` → `- <review_label> ✅ APPROVED — <approved_next>`
- `CHANGES REQUESTED` → `- <review_label> ⚠️ CHANGES REQUESTED — <N> findings to fix`
- `REJECTED` → `- <review_label> ❌ REJECTED — redesign required`

Update `**Last Updated:**` to today's date.

### 3. Push to backup immediately (before blocking)

```bash
projctl sync push
```

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
