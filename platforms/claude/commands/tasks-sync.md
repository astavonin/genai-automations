---
name: tasks-sync
description: Sync local planning task state with remote ticket system (GitLab, GitHub, etc.) — push local completions, discover epic children
---

# Tasks Sync Command

Sync local planning task state with the remote ticket system using `projctl`.

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
  milestone: 10           # corresponds to %10
  milestone_state: closed # optional — skip network load if closed
  epic: 21                # single epic — corresponds to &21
  epic_state: closed      # optional — skip network load if closed
  epics:                  # multiple epics (use instead of epic: when there are more than one)
    - id: 21
      state: closed       # optional per-epic state
    - 22                  # plain number = open (will be loaded)
    - id: 23
      state: closed
---
```

Use `epic:` for a single epic, `epics:` for a list. Both are supported. If both appear, `epics:` takes precedence.

**Closed-state semantics:** any entity marked `state: closed` (or `epic_state: closed` / `milestone_state: closed`) is skipped entirely during network load — no `projctl load` call is made and no child discovery is attempted. The `/complete` command should write the closed state to frontmatter when finishing a milestone or epic.

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

**Load order: epics first, then milestones, then individual issues — never load the same entity twice.**

**Pre-flight skip rule:** before calling `projctl load` for any entity, check its state from the frontmatter. If it is marked `closed`, skip the network call and all child discovery for that entity entirely — treat it as already done.

**2a — Load epics** (epics return all child issues with state, so children need no separate fetch):

```bash
# Skip if epic_state == "closed" or epics[N].state == "closed"
epic_output=$(projctl load epic N)
```

Parse `$epic_output` to build the shared issue lookup (see 2c). Do not call `projctl load issue` for any issue number found in an epic's output.

**2b — Load milestones** (same capture-once rule):

```bash
# Skip if milestone_state == "closed"
milestone_output=$(projctl load milestone N)
```

**2c — Build shared issue lookup table**

After all epic and milestone loads are complete, construct a single in-memory map:

```
issue_state[N] = "open" | "closed"
issue_title[N] = "<title string>"
```

Populate it from every epic and milestone output already captured. This table is the sole source of truth for Steps 3 and 4 — no further network calls to look up issue state.

**2d — Load remaining individual issues (`[ ]` orphans only)**

Collect all `#N` references found in planning files. Remove any N already present in `issue_state[]`. Split the remainder by local state:

- **`[x]` orphans** (locally done, not in lookup): do NOT load — add directly to list A (close remote). `projctl update issue N --state close` is idempotent; no pre-fetch needed.
- **`[ ]` orphans** (locally open, not in lookup): load these — needed to detect remote-closed issues for list B.

```bash
# Only [ ] orphans get a network call
issue_output=$(projctl load issue N)
```

Add each result to `issue_state[]` and `issue_title[]`.

**Rule:** if `issue_state[N]` is already populated, skip the `projctl load issue N` call entirely. If N is a `[x]` orphan, skip loading unconditionally.

**2e — Load MRs (`[ ]` only)**

Collect all `!N` references found in planning files. Split by local state:

- **`[x]` MRs**: skip — no remote action is taken for locally-done MRs (never auto-close an MR without merging).
- **`[ ]` MRs**: load to detect remote-merged/closed state.

```bash
mr_output=$(projctl load mr N)
```

Build a parallel MR lookup from the output:

```
mr_state[N] = "open" | "merged" | "closed"
mr_title[N] = "<title string>"
```

An MR is considered done when `mr_state[N]` is `"merged"` or `"closed"`.

### Step 3 — Epic child discovery

For each epic loaded, compare its child issue list against the task lines in the corresponding `status.md`. Use `issue_title[]` and `issue_state[]` from the lookup table — no additional network calls:
- Any child issue number **not present** in the local file → record as a "new remote issue" to be added
- Match by issue number (`#N`) in task lines

### Step 4 — Compute sync plan

Use `issue_state[]` and `issue_title[]` exclusively — no `projctl load` calls in this step.

Build three lists:

**A. Local → Remote (close):** Tasks marked `[x]` with a remote reference where `issue_state[N] == "open"` OR `issue_state[N]` is absent (orphan skipped in 2d) → will call `projctl update issue N --state close`. The close is idempotent; no pre-check is needed for orphans.

**B. Remote → Local (mark done):** Issues where `issue_state[N] == "closed"` but the local line is `[ ]` → will mark the local task line as `[x]`

**B2. MR remote → local (mark done):** MRs where `mr_state[N]` is `"merged"` or `"closed"` but the local line is `[ ]` → will mark the local task line as `[x]`. Never push `[x]` local state back to remote for MRs.

**C. New remote issues (discovery):** Epic child issue numbers not present in local `status.md` → will append as `- [ ] <issue_title[N]> #N` to the relevant status file

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

MRs merged/closed (mark done locally):
  ✓ !34 Add auth middleware   →  merged — will mark [x] in milestone-02/status.md

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
projctl update issue N --state close
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
