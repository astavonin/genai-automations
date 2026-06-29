---
name: review-iterate
description: Run initial review, iterate on findings with per-finding scoped fix verification, then run one final full re-review and stop
---

# Review Iterate Command

Run the initial review to find all defects, fix them one by one with scoped per-finding verification, then run a single final full re-review. After the final re-review, report and stop — do not start a new loop automatically.

## Purpose

Separates three concerns that ad-hoc re-running `/review-code` conflates:

1. **Initial review** — one full consensus review to establish the complete defect baseline
2. **Fix-verify loop** — for each finding, verify the fix in isolation; scope is that finding and the changed lines only, not the full codebase
3. **Final sweep** — one complete re-review after all findings are addressed, to catch regressions introduced by the fixes

## Agents

- **coder** (sonnet) — apply fixes when agent-driven
- **reviewer** (opus) — initial review (full protocol) + per-finding scoped verification (single agent) + final re-review (full protocol)

## Prerequisite

Determine review type from context:
- Code review: implementation exists on branch, or `code-review.md` already exists with `CHANGES REQUESTED`
- Design review: design doc exists, or `design-review.md` already exists with `CHANGES REQUESTED`

If a review file already exists with `CHANGES REQUESTED` or `REJECTED`, skip Step 0 and start from Step 1 (re-entering the loop on an in-progress review). If the review file is `APPROVED`, report and stop — nothing to do.

If both review files exist with open status, ask the user which to iterate on.

## Actions

### Step 0: Initial review

Declare: "I'll use reviewer agent for the initial review..."

Run the **complete review protocol** for the appropriate type:
- Code review: follow `/review-code` exactly — full 3+1 consensus + Codex, all mandatory passes, writes `code-review.md`
- Design review: follow `/review-design` exactly — full 3+1 consensus + Codex, writes `design-review.md`

If the result is `APPROVED`: update planning state per the invoked command, report `Initial review: APPROVED — no findings`, and stop. No fix loop needed.

If the result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 1.

### Step 1: Load open findings

Read the review file. Extract every finding with severity Critical, High, or Medium (mandatory to address) and any Low findings the user opts to include.

Display the full list: ID, severity, one-line description.

Count: "N findings to resolve (C Critical, H High, M Medium, L Low)."

### Step 2: Fix-verify loop (per finding)

Process findings in severity order: Critical → High → Medium → Low.

For each finding:

**2a. Present the finding** — show full description, location, and fix direction from the review.

**2b. Apply the fix** — apply the following test requirements before invoking the coder agent or accepting a manual fix:
- **Critical and High findings (mandatory):** the fix must include new or modified tests. Use unit tests for isolated logic and integration tests when the finding involves component interaction, external state, or runtime composition. No Critical or High finding is considered fixed without a corresponding test change.
- **Any severity with `Required test:` line:** implementing the described test is mandatory as part of the fix.

Choose based on context:
- Agent-driven: declare "I'll use coder agent to fix [finding ID]…" and invoke coder agent scoped to this finding only, explicitly passing the test requirements above
- Manual: wait for user to confirm the fix (including any required tests) is applied before continuing

**2c. Scoped verification** — invoke a **single reviewer agent** (not full consensus) with:
- The specific finding ID, description, and fix direction
- Output of `git diff` since the review baseline (or since the last commit)
- Instruction: "Verify ONLY whether finding [ID] has been resolved. Do not expand scope beyond the changed lines. Return one of: RESOLVED / STILL OPEN / REGRESSION INTRODUCED. If REGRESSION INTRODUCED: describe what broke and where. For Critical and High findings, also verify that a new or modified test covers the fix — return STILL OPEN if no test change is present."

**2d. Record result**:
- **RESOLVED** → mark finding fixed, proceed to next finding
- **STILL OPEN** → show reviewer feedback, loop back to 2b for this finding (cap at 3 retries; if still open after 3, surface as a blocker and pause for user decision)
- **REGRESSION INTRODUCED** → treat as a new Critical finding; fix the regression before continuing (re-enter 2b for the regression, then resume the original loop)

Continue until all findings from Step 1 are RESOLVED.

### Step 3: Final full re-review

Once all findings are resolved, declare: "I'll use reviewer agent for the final full re-review..."

Run the **complete review protocol** by invoking the appropriate command:
- Code review: follow `/review-code` exactly — full 3+1 consensus + Codex, mandatory passes (Test Quality, Cross-Site Consistency, Dead Symbol), overwrites `code-review.md`
- Design review: follow `/review-design` exactly — full 3+1 consensus + Codex, overwrites `design-review.md`

Do not shortcut the protocol. This is the convergence gate.

### Step 4: Report and stop

After Step 3 completes:

1. Display the final status: `APPROVED` / `CHANGES REQUESTED (N findings)` / `REJECTED`
2. If `APPROVED`: run the review-planning-update fragment as defined in the invoked command (`/review-code` or `/review-design`)
3. If `CHANGES REQUESTED` or `REJECTED`: list all new findings

**Stop. Do not automatically start a new fix-verify loop.**

Output exactly:
```
Final re-review: APPROVED
```
or:
```
Final re-review: CHANGES REQUESTED — N finding(s) remain.
Invoke /review-iterate to address them.
```

## Key Constraints

- **Single agent for per-finding verification** — step 2c uses one reviewer agent, not 3+1 consensus. Full consensus is reserved for the final sweep only.
- **No scope expansion in 2c** — the per-finding reviewer must not flag issues outside the changed lines. If it does, discard out-of-scope findings; they belong to the final sweep.
- **Final sweep is mandatory** — do not skip Step 3 even if all per-finding verifications returned RESOLVED. Fixes can interact in ways that per-finding checks miss.
- **Stop after final sweep** — the loop is closed by Step 4. The user decides whether to invoke `/review-iterate` again based on the report.
