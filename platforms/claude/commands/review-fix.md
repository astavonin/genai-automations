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

**Step 0 (do first, before any agents):** Write `planning/reviews/<fix-description>-fix-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** the fix diff range established in Step 1
- **Output File:** `planning/reviews/<fix-description>-codex-fix-review.md`
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
  codex-flow review planning/reviews/<fix-description>-fix-review-request.md
  ```

Focus areas for a fix review:
- **Correctness:** Does the fix actually solve the stated problem?
- **Completeness:** Are all affected paths/cases covered?
- **Regressions:** Could the fix break existing behaviour?
- **Root cause:** Does it address the root cause or only a symptom?
- **Safety / Security:** No new vulnerabilities introduced
- **Tests:** Is the fix covered by a test?
- **On-device verification (when `analysis.md ## On-Device Scope` is YES or YES-UNKNOWN — authoritative trigger; do not key off design doc section presence):** Verify the entry-point script is still present on disk and covers all documented build/deploy/verify steps; flag if the fix could break the entry point or invalidate the expected outcome stated in the design doc; if the design doc is missing the On-Device Verification section despite YES scope, flag that absence as a separate finding.

Aggregate per protocol Steps B–H. Note: Step F (test-coverage agent) is optional for fix reviews — include it when the fix touches test files or adds new tests.

### Step 4: Output

**Write the report to `planning/reviews/<fix-description>-fix-review.md`** (use a short slug for `<fix-description>`, e.g. `tier-timeout-fix`).
After writing, ask the user if they want to `open <path>` the review file.

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
