---
name: tasks-sync
description: Sync local planning task state with remote ticket system (GitLab, GitHub, etc.) — push local completions, discover epic children
---

# Tasks Sync Command

Sync local planning task state with the remote ticket system using `ci-platform-manager`.

**Primary direction:** Local → Remote (push completions to close remote tickets).
**Discovery:** For each referenced epic, pull all its child issues from the remote and add any that are missing from local planning.

---

## Mapping Format

Planning files must contain explicit remote references for sync to work.

### Status file header (YAML frontmatter)

Add to the top of `status.md` to bind the file to remote entities:

```markdown
---
sync:
  milestone: 10   # corresponds to %10
  epic: 21        # single epic — corresponds to &21
  epics:          # multiple epics (use instead of epic: when there are more than one)
    - 21
    - 23
    - 24
---
```

Use `epic:` for a single epic, `epics:` for a list. Both are supported. If both appear, `epics:` takes precedence.

### Individual task lines

Task lines are any `- ` bullet that contains a remote reference anywhere in the line.

**Preferred format** (reference at end):
```markdown
- [x] Implement sync hook #145
- [ ] Write tests for sync #146
- [ ] Untracked task (no remote reference)
```

**Also recognized** (existing files may use emoji status or reference at start):
```markdown
- ✅ #183 [Design] Analyze manager.py
- ⏳ #239 Watchdog instrumentation
- ⬜ #153: [Design] Analyze existing logging
- 🔶 #121: [Impl] Configuration parsing for SRT
- [ ] Start #140: VisionIpcClient handling
```

**Completion state mapping:**
| Marker | State |
|--------|-------|
| `[x]` or `✅` | done |
| `[ ]`, `⬜`, `⏳`, `🔶` | todo |

**Reference extraction:** first occurrence of `#N`, `&N`, `%N`, or `!N` anywhere in the line (N = one or more digits).

Valid reference prefixes:
- `#N` — issue
- `&N` — epic
- `%N` — milestone
- `!N` — merge request

---

## Actions

### Step 1 — Scan planning files

Find all `status.md` files under `planning/`:

```bash
find planning/ -name "status.md"
```

For each file:
- Read YAML frontmatter to extract `sync.epic` and `sync.milestone` (if present)
- Scan task lines (`- [ ]` / `- [x]`) for inline remote references (`#N`, `&N`, etc.)

### Step 2 — Load remote state

For each unique remote reference found:

```bash
# Epic — also loads all child issues (discovery)
ci-platform-manager load epic &N

# Milestone
ci-platform-manager load milestone %N

# Individual issue (if referenced inline but not part of an epic already loaded)
ci-platform-manager load issue #N
```

Collect from each epic: the full list of its child issues (title + number + state).

### Step 3 — Epic child discovery

For each epic loaded, compare its child issue list against the task lines in the corresponding `status.md`:
- Any child issue **not present** in the local file → record as a "new remote issue" to be added
- Match by issue number (`#N`) in task lines

### Step 4 — Compute sync plan

Build three lists:

**A. Local → Remote (close):** Tasks marked `[x]` with a remote reference where the remote issue is still open → will call `ci-platform-manager update issue #N --state close`

**B. Remote → Local (mark done):** Remote issues that are closed but appear as `[ ]` locally → will mark the local task line as `[x]`

**C. New remote issues (discovery):** Remote epic child issues not present in local `status.md` → will append as `- [ ] <title> #N` to the relevant status file

### Step 5 — Display sync plan

Before making any changes, print a structured summary:

```
Sync Plan
─────────────────────────────────────
Push to remote (close tickets):
  ✓ #145 Implement sync hook  →  will close
  ✓ #148 Update CLAUDE.md     →  will close

Pull to local (mark done):
  ✓ #143 Bootstrap project    →  will mark [x] in milestone-01/status.md

New remote issues (discovery):
  + #152 Add error handling   →  will append to milestone-01/status.md
  + #153 Write changelog      →  will append to milestone-01/status.md

No changes: 3 tasks already in sync
─────────────────────────────────────
```

If there is nothing to sync, say so clearly and stop.

### Step 6 — Confirm and execute

Ask the user: **"Apply this sync plan? (yes / no / edit)"**

- **yes** → execute all three lists in order: close remote tickets → mark local done → append new issues
- **no** → abort, make no changes
- **edit** → show each action individually and ask per-action

**Execution:**

Close remote tickets:
```bash
ci-platform-manager update issue #N --state close
```

Mark local tasks done: edit the `status.md` file, replacing `- [ ] <text> #N` with `- [x] <text> #N`.

Append new remote issues: add to the bottom of the **Tasks** section in the relevant `status.md`:
```markdown
- [ ] <title from remote> #N
```

### Step 7 — Report

After execution, print a short summary of what was done:
- N tickets closed in remote
- N tasks marked done locally
- N new issues added to local planning

---

## Critical Rules

- **NEVER close a remote ticket without showing the plan first** — always confirm in Step 6
- **NEVER modify `progress.md`** — this command only touches `status.md` files and remote tickets
- **If a status.md has no `sync:` frontmatter and no inline references**, skip it silently (do not error)
- **Dry-run flag:** if the user calls `/tasks-sync --dry-run`, execute Steps 1–5 only (no changes)

---

## Examples

```
/tasks-sync                # full sync across all planning files
/tasks-sync --dry-run      # show plan only, make no changes
```
