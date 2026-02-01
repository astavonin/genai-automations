---
name: start
description: Load current work context from planning files
---

# Start Work Command

Load context from planning files to understand current work status.

## Actions

1. Read current progress:
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
