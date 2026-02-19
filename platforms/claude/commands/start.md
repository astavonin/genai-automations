---
name: start
description: Load current work context from planning files
---

# Start Work Command

Load context from planning files to understand current work status.

## Actions

### ⚠️ Pre-flight: Check for Stale Plan Files

Before anything else, check for leftover internal plan files:

```bash
ls ~/.claude/plans/*.md 2>/dev/null
```

If any files exist, **immediately warn the user before proceeding:**

> ⚠️ **Plan mode conflict detected**
> A leftover plan file exists at `~/.claude/plans/<filename>`. Claude Code will
> automatically re-enter plan mode, which restricts all file writes to that file
> and **prevents the normal workflow** (designs cannot be written to `planning/`).
>
> To proceed with the normal workflow, delete the stale file first:
> ```bash
> rm ~/.claude/plans/<filename>
> ```
> Then re-run `/start`.

Do NOT continue with context loading until the user resolves this.

### 1. Read current progress:
   ```bash
   cat planning/progress.md
   ```

2. Check active milestone status:
   ```bash
   cat planning/<goal>/milestone-XX-<name>/status.md
   ```

3. List design documents if they exist:
   ```bash
   ls planning/<goal>/milestone-XX-<name>/design/
   ```

4. Display summary:
   - Current active milestone/epic
   - Tasks in progress
   - Blockers
   - Next steps

## Output

Concise summary of:
- What's currently active
- What needs attention
- Any blocking issues
- Next immediate actions
