---
name: review-fix
description: Review a targeted fix (CI failure, local issue) — not the full MR
---

# Fix Review Command

Review a specific fix in isolation — a CI failure resolution, a bug fix, or a correction
to a previous implementation. Scope is the fix only, not surrounding unchanged code.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol
**1 × reviewer (opus)** — test-coverage agent (Step F), mandatory: the observed-failure regression gate applies to every fix review

## Setup

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
```

## Actions

### Step 0: Resolve Linked Issue and Target Folder

Every fix review lives inside the issue folder it belongs to. Resolve the issue up front so all subsequent writes go to the correct location.

1. **Resolve `<issue-folder>`** using the shared procedure — including the orphan fallback and its deterministic branch-derived slug:

   ```
   Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
   ```

   Use that fragment's slug rule exactly. A description-derived slug is not acceptable: `/ci-debug` writes the observed-failure ledger under the branch-derived orphan path, and a differently-derived slug here lands on a different folder and reports the ledger missing — which reads as "no gate applies" rather than as an error.

2. **This command does not create issue folders.** If the issue resolves but no folder exists on disk, bail with an actionable error — that is `/start`/`/research`'s job.

3. **For the orphan path,** surface a warning: "Orphan fix review — no linked issue. This file is hand-managed and not tracked in progress.md." This path is uncommon for full-scope work; `/review-code` is the better choice for unlinked work with a full issue scope.

Confirm the resolved issue folder to the user in one line:
```
Fix review → <issue-folder>/fix-review.md    (add "(orphan — no linked issue)" when applicable)
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

**Pre-read context** before launching agents — pass all of it inline to **every** agent, including the Step F test-coverage agent:
- **Interface files not in the diff:** for each changed `.cc`/`.cpp`/`.c` file, also read its `.h`/`.hpp` if not in the diff
- **Full design doc** if one exists — pass the entire file
- **The observed-failure ledger** (`<issue-folder>/observed-failures.md`) if one exists. All four agents are asked to validate its entries; an agent without it will report a valid waiver as a missing test. State explicitly in the prompt when no ledger exists.

**Step 0 (do first, before any agents):** Write `<issue-folder>/fix-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** the fix diff range established in Step 1
- **Constraints:** include the line `Fix review — every observed-failure regression finding is High, not Medium.` Codex has no review-type field and its bundled guidance carries the default severities, so without this a Codex-only Medium lands directly in the report and this command's zero-High bar approves the exact gap it exists to catch.
- **Output File:** `<issue-folder>/codex-fix-review.md`
- **Requirements:** what the fix was supposed to solve (from Step 2)
- **Observed-Failure Ledger:** the contents of `<issue-folder>/observed-failures.md`, pasted **inside the template's `~~~markdown` fence** (its `## <date>` entry headings would otherwise end the section), or the literal `No ledger exists for this work.` Codex sees only this document; without the section it flags a user-approved waiver as a missing test, producing a High that no coder can clear. This matters most here — in a fix review every regression finding is High.
- **Evidence:** run the project's build and test commands; capture exit codes + last 40 lines of output and paste here
- **Review Focus:** correctness, completeness, regressions, root cause, tests

```
Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
```
(`test_coverage = yes`)

**Step A (single message):** Launch simultaneously:
- 3 × reviewer (opus) Agent calls with:
  - The fix diff (scoped per Step 1)
  - The problem statement (from Step 2)
  - Interface files and design doc (pre-read above)
  - The review checklist
  - Instruction: **review the fix only** — do not flag pre-existing issues outside the diff
- 1 × reviewer (opus) test-coverage agent (Step F) with:
  - The fix diff, the problem statement, the review checklist, and the pre-read context above (including the ledger). The checklist is not optional here: Step F's prompt item 8 runs its Test Quality Pass Step 3, which is what enforces the regression gate in this command.
  - Instruction: run the checklist's Test Quality Pass **including Step 3 (observed-failure regression coverage)** — the fix under review resolves a failure that actually happened, so Step 3 always applies, and every Step 3 finding is High in a fix review
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
- **Regression test (hard gate):** Every fix reviewed here addresses a failure that actually happened, so the observed-failure rule always applies. Verify a test reproducing the failure is present **in this diff** and recorded as resolved in `<issue-folder>/observed-failures.md`. Apply the fragment's Review Severities table — note its `/review-fix` rule: **every finding in that table is High here**, because a Medium would approve the exact gap this review exists to catch.
- **On-device verification (when `analysis.md ## On-Device Scope` is YES or YES-UNKNOWN — authoritative trigger; do not key off design doc section presence):** Verify the entry-point script is still present on disk and covers all documented build/deploy/verify steps; flag if the fix could break the entry point or invalidate the expected outcome stated in the design doc; if the design doc is missing the On-Device Verification section despite YES or YES-UNKNOWN scope, flag that absence as a separate finding.

Aggregate per protocol Steps B–H. Step F (test-coverage agent) is **mandatory** for fix reviews — its Step 3 pass is what enforces the observed-failure regression gate, and that gate applies whether or not the fix touched a test file. Its absence is precisely the case Step F must catch.

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

## Observed-Failure Regression Requirement

The fix under review resolves a failure that actually happened, which makes the regression rule unconditional here — not contingent on finding severity:

```
Read ~/.claude/skills/workflows/regression-test/SKILL.md
```

Apply its Review Severities table with the `/review-fix` rule: every finding in it is **High** here. That is what makes the gate binding under this command's Assessment thresholds below, which govern fix reviews in place of the stricter zero-Medium bar in `review-output-format/SKILL.md`.

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
