---
name: review-fix
description: Review a targeted fix (CI failure, local issue) — not the full MR
---

# Fix Review Command

Review a specific fix in isolation — a CI failure resolution, a bug fix, or a correction
to a previous implementation. Scope is the fix only, not surrounding unchanged code.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
```

## Actions

### Step 0: Resolve Linked Issue and Target Folder

Every fix review lives inside the issue folder it belongs to. Resolve the issue up front so all subsequent writes go to the correct location.

1. **Extract the linked issue** — parse `Ref #<N>` from the current branch's last commit, or from the branch name (`feature/<N>-*`, `fix/<N>-*`). If neither yields a number, prompt the user for the issue number. If the user replies "none" or "unlinked" (quick standalone fixes on `main`, hotfixes without tickets, sandbox experiments), set `<issue-folder>` = `planning/reviews-orphan/<slug>` where `<slug>` is derived from the branch name or a brief fix description; write the fix review there and surface a warning: "Orphan fix review — no linked issue. This file is hand-managed and not tracked in progress.md." Skip Step 0 sub-steps 2 and 3 (issue-folder resolution) and continue with Step 1 (Establish Fix Scope) — the orphan folder is your target. This path is uncommon; `/review-code` is the better choice for unlinked work with a full issue scope.
2. **Resolve the issue folder** — `projctl load issue <N>` to confirm existence. Match the issue against `planning/*/milestone-*/issues/<N>-*/` on disk. If no matching folder exists, resolve epic (from `## Epic &<M>` in the issue output) and milestone locally, then bail with an actionable error — this command does not create issue folders; that's `/start`/`/research`'s job.
3. **Set path variables** for the rest of the workflow:
   - `<issue-folder>` = `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>`

Confirm the resolved issue folder to the user in one line:
```
Issue #<N> — fix review will be written to <issue-folder>/fix-review.md
```

### Step 1: Establish Fix Scope

Identify exactly what changed. Use the narrowest scope that covers the fix:

```bash
git diff HEAD          # uncommitted fix
git diff HEAD~1        # last commit only
git diff <base>..<fix> # specific range
```

Show the user the scope (file list + line ranges) and confirm it matches the fix
being reviewed. Do not include unrelated changes.

### Step 2: State the Problem Being Fixed

Before reviewing, explicitly state:
- What was the original problem (CI failure, bug, logic error, etc.)
- What the fix does to address it

This anchors the review — findings irrelevant to the fix are out of scope.

### Step 3: Multi-Agent Consensus Review

Run the **Consensus Review Protocol** (Steps 0, A–H) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Pre-read context** before launching agents:
- **Interface files not in the diff:** for each changed `.cc`/`.cpp`/`.c` file, also read its `.h`/`.hpp` if not in the diff
- **Full design doc** if one exists — pass the entire file

**Step 0 (do first, before any agents):** Write `<issue-folder>/fix-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** the fix diff range established in Step 1
- **Output File:** `<issue-folder>/codex-fix-review.md`
- **Requirements:** what the fix was supposed to solve (from Step 2)
- **Evidence:** run the project's build and test commands; capture exit codes + last 40 lines of output and paste here
- **Review Focus:** correctness, completeness, regressions, root cause, tests

```
Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
```
(`test_coverage = no`)

**Step A (single message):** Launch simultaneously:
- 3 × reviewer (opus) Agent calls with:
  - The fix diff (scoped per Step 1)
  - The problem statement (from Step 2)
  - Interface files and design doc (pre-read above)
  - The review checklist
  - Instruction: **review the fix only** — do not flag pre-existing issues outside the diff
- `codex-flow` Bash call with `run_in_background: true`:
  ```bash
  codex-flow review <issue-folder>/fix-review-request.md
  ```

Focus areas for a fix review:
- **Correctness:** Does the fix actually solve the stated problem?
- **Completeness:** Are all affected paths/cases covered?
- **Regressions:** Could the fix break existing behaviour?
- **Root cause:** Does it address the root cause or only a symptom?
- **Safety / Security:** No new vulnerabilities introduced
- **Tests:** Is the fix covered by a test?
- **On-device verification (when `analysis.md ## On-Device Scope` is YES or YES-UNKNOWN — authoritative trigger; do not key off design doc section presence):** Verify the entry-point script is still present on disk and covers all documented build/deploy/verify steps; flag if the fix could break the entry point or invalidate the expected outcome stated in the design doc; if the design doc is missing the On-Device Verification section despite YES or YES-UNKNOWN scope, flag that absence as a separate finding.

Aggregate per protocol Steps B–H. Note: Step F (test-coverage agent) is optional for fix reviews — include it when the fix touches test files or adds new tests.

### Step 4: Output

**Write the report to `<issue-folder>/fix-review.md`** — single canonical file per issue folder, overwritten on every re-run. No `<fix-description>-` prefix in the filename; git history preserves prior fix reviews for the same issue.
After writing, ask the user if they want to `open <path>` the review file.

### Step 4b: Delete intermediates

The final `fix-review.md` is the published artifact. Delete the working files immediately after Step 4 writes the final report:

```bash
if test -s <issue-folder>/fix-review.md; then
  rm -f <issue-folder>/fix-review-request.md <issue-folder>/codex-fix-review.md
else
  echo "⚠️  Final artifact not durably written — intermediates preserved for inspection"
fi
```

Do NOT keep them "just in case" — the aggregated content lives in `fix-review.md`, and git history preserves prior Codex output if a future re-run needs a compare point.

Output format (`review_type = Fix Review`, `fix_review_extras = yes`):
```
Read ~/.claude/skills/workflows/review-output-format/SKILL.md
```

## Behavioral Bug Test Requirement

**Critical and High findings (mandatory):** every fix for a Critical or High finding must include new or modified tests. Use unit tests for isolated logic and integration tests when the finding involves component interaction, external state, or runtime composition. No Critical or High finding is considered fixed without a corresponding test change.

**Any severity with `Required test:` line:** implementing the described test is mandatory as part of the fix.

```
Read ~/.claude/skills/workflows/behavioral-bug-test/SKILL.md
```

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → fix is good to go
- ⚠️ **Request Changes:** One or more High findings → revise the fix
- ❌ **Reject:** One or more Critical findings → fix is incorrect or introduces new problems

## Final Step — Update Planning State

**If the fix is linked to an issue** (look for `Ref #NNN` in commits or branch name):

**Planning update** (`approved_phase = code review ✅`, `review_label = fix review`, `approved_next = ready to merge or re-submit`, `escalation = standard`):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
