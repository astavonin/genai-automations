---
name: push-planning
description: Shared push-with-graceful-failure fragment. Reference this skill at the end of /design, /review-design, and /review-code to push planning files to backup after each durable artifact is written.
allowed-tools: Bash
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, sync, push, backup, planning]
---

# Push Planning — Shared Fragment

Push planning state to Google Drive backup after a durable artifact has been written. This is a best-effort checkpoint: push failure MUST NOT fail the calling skill.

## When to Use

Include this fragment as the **last step** of any skill that writes a durable planning artifact:

- `/design` — after writing `<feature>-design.md`
- `/review-design` — after writing `<feature>-design-review.md`
- `/review-code` — after writing `<feature>-code-review.md` (see elevated warning note below)

## Steps

### 1. Push planning state

```bash
projctl sync push
```

### 2. On success

Continue normally. No confirmation line needed (this is a background checkpoint, not a phase boundary).

### 3. On failure (non-zero exit code or any error)

**MUST NOT fail the skill.** The primary work (writing the artifact) succeeded. Push is a best-effort checkpoint.

Surface the following warning in the §8.2 visual block format:

```
⚠️  workflow-safety: planning push failed after <skill-name>
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually when backup is available
```

Then return success from the skill.

## Elevated Warning for /review-code

When this fragment is invoked from `/review-code`, an additional line MUST be appended to the warning on failure (because this is the last checkpoint before `/complete`, making a silent failure here higher-impact):

```
⚠️  workflow-safety: planning push failed after /review-code
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually; also run `projctl sync status`
              before /complete to verify no drift has accumulated across machines
```

## Design Reference

- §6.2 — Failure handling (general): push failures must not fail the skill
- §6.3 — Elevated failure handling for `/review-code`
- §6.4 — Shared push fragment rationale
- §8.2 — Warning surface convention (three-line visual block format)
