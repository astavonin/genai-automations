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

**Preferred format** (reference at end, linked per the CLAUDE.md clickable-ticket-links rule):
```markdown
- [x] Implement sync hook [#145](URL)
- [ ] Write tests for sync [#146](URL)
- [ ] Untracked task (no remote reference)
```

**Also recognized** (existing files may use emoji status, reference at start, or bare sigils from before the clickable-links rule was adopted):
```markdown
- ✅ #183 [Design] Analyze manager.py
- ⏳ #239 Watchdog instrumentation
- ⬜ #153: [Design] Analyze existing logging
- 🔶 #121: [Impl] Configuration parsing for SRT
- [ ] Start #140: VisionIpcClient handling
```

Read-side matching accepts both bare and linked forms for backward compatibility. **All new writes must use the linked form** (see Preferred format above); when done-marking a legacy bare-sigil line, preserve whichever sigil form is already present — do not rewrite the sigil format during a state change.

**Completion state mapping:**
| Marker | State |
|--------|-------|
| `[x]` or `✅` | done |
| `[ ]`, `⬜`, `⏳`, `🔶` | todo |

**Reference extraction:** first occurrence of a ticket reference in either form — bare (`#N`, `&N`, `%N`, `!N`) or linked (`[#N](URL)`, `[&N](URL)`, `[%N](URL)`, `[!N](URL)`) — anywhere in the line (N = one or more digits).

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
issue_url[N]   = "<web_url from projctl output>"
```

Populate it from every epic and milestone output already captured — `projctl load` returns `web_url` for each child. This table is the sole source of truth for Steps 3 and 4 — no further network calls to look up issue state. `issue_url[N]` is required by Step 6 to write linked-form references when appending newly discovered issues.

**2d — Load remaining individual issues (all orphans)**

Collect all `#N` references found in planning files. Remove any N already present in `issue_state[]`. Load all remaining orphans regardless of local state — remote state must be known before deciding whether to close or skip:

```bash
issue_output=$(projctl load issue N)
```

Add each result to `issue_state[]` and `issue_title[]`.

**Rule:** if `issue_state[N]` is already populated (from epic or milestone load), skip the `projctl load issue N` call entirely.

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

**A. Local → Remote (close):** Tasks marked `[x]` with a remote reference where `issue_state[N] == "open"` → will call `projctl update issue N --state close`. Skip if `issue_state[N] == "closed"` — no action needed.

**B. Remote → Local (mark done):** Issues where `issue_state[N] == "closed"` but the local line is `[ ]` → will mark the local task line as `[x]`

**B2. MR remote → local (mark done):** MRs where `mr_state[N]` is `"merged"` or `"closed"` but the local line is `[ ]` → will mark the local task line as `[x]`. Never push `[x]` local state back to remote for MRs.

**C. New remote issues (discovery):** Epic child issue numbers not present in local `status.md` → will append as `- [ ] <issue_title[N]> [#N](<issue_url[N]>)` to the relevant status file (linked form per the CLAUDE.md rule)

### Step 5 — Display sync plan

Before making any changes, print a structured summary. Include a timestamp header so the user knows when the remote state was captured — concurrent changes after this point are not reflected in the plan.

Console/terminal display uses **bare sigils** for readability (CLI output is exempt from the clickable-links rule). File writes below (Step 6) still use the linked form.

```
Sync Plan  (remote state captured at HH:MM)
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

- **yes** → execute all three lists in order: mark local done → close remote tickets → append new issues
- **no** → abort, make no changes
- **edit** → show each action individually and ask per-action

**Execution order rationale:** local marks happen first so that local state is correct even if a remote close fails. A failed remote close leaves local as `[x]` and remote as `open` — the next sync run will retry the close. The reverse order (close remote first) would leave local as `[ ]` after a successful remote close, which looks like the task is still pending and is more confusing to the user.

**Execution:**

Mark local tasks done first: edit each `status.md` file, flipping the checkbox on the matched task line — replace `- [ ]` with `- [x]` while preserving the rest of the line verbatim, including whichever sigil form (bare `#N` or linked `[#N](URL)`) is already present. Do NOT rewrite the sigil format during a done-mark; format migration is out of scope for `/tasks-sync`.

Close remote tickets: for each issue in List A, run:
```bash
projctl update issue N --state close
```
If a close call fails, log the failure, continue with the remaining tickets, and record the failed issue number for Step 7. Do not abort the entire execution on a single failure.

Append new remote issues: add to the bottom of the **Tasks** section in the relevant `status.md`. If no Tasks section exists in the file, create one (`## Tasks`) immediately before appending. Use the linked form; the URL comes from `issue_url[N]` populated in Step 2c:
```markdown
- [ ] <title from remote> [#N](<issue_url[N]>)
```

### Step 7 — Report

After execution, print a short summary of what was done:
- N tasks marked done locally
- N tickets closed in remote
- N new issues added to local planning

If any remote close calls failed, list them explicitly:
```
Failed to close (retry or resolve manually):
  ✗ #148 Update CLAUDE.md  →  <error message>
```

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
