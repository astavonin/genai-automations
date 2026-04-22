---
name: start
description: Load current work context from planning files
---

# Start Work Command

Load context from planning files to understand current work status.

## Actions

### 0-pre. Auto-compact (first step, unconditional — §7.2)

`/start` is a context reset. Always compact first, before any other action.

- Log to gate-decision log: append one line to `planning/.workflow-safety.log` (create the file if it does not exist):
  ```
  <ISO-8601 timestamp> /start start FIRED
  ```
- Trigger compaction (automatic, no prompt per §7.8).
- After successful compaction, emit:
  ```
  ✓ Compacted at start (N messages summarized)
  ```
- **If compaction fails:** log `<ISO-8601 timestamp> /start start SKIPPED compact-failed`, surface `⚠️  workflow-safety: compaction failed at start — proceeding with /start normally`, and continue with the remaining steps. Do not block.

### 0. Sync planning state from backup (drift-check flow — §5)

Do NOT blindly run `projctl sync pull`. First check drift state.

#### 0a. Detect pre-feature projctl

```bash
projctl sync status --help 2>&1 | grep -q 'invalid choice\|unknown command\|No such command' && echo "pre-feature" || echo "ok"
```

If `projctl sync status` exits with error code 2 or stderr contains "invalid choice" / "unknown command" / "No such command", the installed projctl pre-dates the `sync status` feature. Fall back to blind pull:

```bash
projctl sync pull
```

Then proceed to step 0b. No warning needed for pre-feature fallback.

#### 0b. Run drift check (with 30-second timeout)

```bash
timeout 30 projctl sync status
```

Parse the **first line** of output:

**`STATUS: in-sync`** → No pull needed. Proceed to step 0c.

**`STATUS: remote-ahead`** → Run pull, then proceed to step 0c:
```bash
projctl sync pull
```

**`STATUS: local-ahead`** → **HALT.** Display the local-only files listed in the `projctl sync status` output. Surface:
```
⚠️  workflow-safety: local planning changes not pushed to backup
    reason: projctl sync status reports local-ahead — pulling would overwrite local-only files
    recovery: run `projctl sync push` first, then re-run /start
```
Do not proceed. Wait for user to either push or explicitly override.

**`STATUS: diverged`** → **HALT.** Display both-side change lists from the status output. Surface:
```
⚠️  workflow-safety: planning state has diverged between local and backup
    reason: both local and remote have changes the other does not have
    recovery: reconcile manually — inspect local-only and remote-only files, push or discard as appropriate, then re-run /start
```
Do not proceed. Require manual reconciliation.

**Timeout (no output within 30 seconds):** Fall back to blind pull with caveat:
```bash
projctl sync pull
```
Then surface:
```
⚠️  workflow-safety: drift detection timed out (30s)
    reason: projctl sync status did not complete in time
    recovery: check `projctl sync status` manually if you suspect unpushed local work — a blind pull was run
```

**Non-zero exit, no recognized STATUS line, not a timeout, not a pre-feature error:** Fall back to blind pull, then surface:
```bash
projctl sync pull
```
Then surface:
```
⚠️  workflow-safety: drift detection failed
    reason: projctl sync status failed (exit=<code>)
    recovery: verify projctl installation and backup availability; proceeding with blind pull
```
This branch applies when `projctl sync status` exits non-zero AND stderr does not match the pre-feature pattern (`invalid choice` / `unknown command` / `No such command`) AND stdout contains no `STATUS:` line. Parallel structure to the timeout branch: run blind pull, warn, proceed to step 0c.

### 0c. Read workflow and planning skills

```
Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
Read ~/.claude/skills/workflows/planning/SKILL.md
```

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

### 2. Verify active issue states

Extract every `#N` reference from the **Active** section of `progress.md` and fetch current state for each:

```bash
projctl load issue #N
```

For each issue:
- If state is **closed** or status is **Done** — it is stale
- If state is **open** — include normally

If any stale issues are found, propose the exact edits to `progress.md` (move them from Active to a completed/done section, update their status line) and wait for explicit user confirmation before writing.

### 3. Check active milestone status:
   ```bash
   cat planning/<goal>/milestone-XX-<name>/status.md
   ```

### 4. List design documents if they exist:
   ```bash
   ls planning/<goal>/milestone-XX-<name>/design/
   ```

### 5. Display summary:
   - Current active milestone/epic
   - Tasks in progress (with verified states)
   - Blockers
   - Next steps

## Output

Concise summary of:
- What's currently active
- What needs attention
- Any blocking issues
- Next immediate actions
