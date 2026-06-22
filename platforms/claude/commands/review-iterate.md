---
name: review-iterate
description: Iterate on CHANGES REQUESTED findings with per-finding scoped fix verification, then run one final full re-review and stop
---

# Review Iterate Command

Address all open findings from a prior review one by one with scoped verification per finding, then run a single final full re-review. After the final re-review, report and stop — do not start a new loop automatically.

## Purpose

Separates two concerns that re-running `/review-code` conflates:

1. **Fix-verify loop** — for each prior finding, verify the fix in isolation; the scope is that finding and the changed lines only, not the full codebase
2. **Final sweep** — one complete re-review after all findings are addressed, to catch regressions introduced by the fixes

## Agents

- **coder** (sonnet) — apply fixes when agent-driven
- **reviewer** (opus) — per-finding scoped verification (single agent, not consensus) + final re-review (full protocol)

## Prerequisite

A review file must exist with status `CHANGES REQUESTED` or `REJECTED`:
- Code review: `planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md`
- Design review: `planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`

If both exist with open status, ask the user which to iterate on. If neither exists or both are `APPROVED`, report and stop.

## Actions

### Step 1: Load open findings

Read the review file. Extract every finding with severity Critical or High (mandatory to address) and any Medium/Low the user opts to include.

Display the full list: ID, severity, one-line description.

Count: "N findings to resolve (C Critical, H High, M Medium, L Low)."

### Step 2: Fix-verify loop (per finding)

Process findings in severity order: Critical → High → Medium → Low.

For each finding:

**2a. Present the finding** — show full description, location, and fix direction from the review.

**2b. Apply the fix** — choose based on context:
- Agent-driven: declare "I'll use coder agent to fix [finding ID]…" and invoke coder agent scoped to this finding only
- Manual: wait for user to confirm the fix is applied before continuing

**2c. Scoped verification** — invoke a **single reviewer agent** (not full consensus) with:
- The specific finding ID, description, and fix direction
- Output of `git diff` since the review baseline (or since the last commit)
- Instruction: "Verify ONLY whether finding [ID] has been resolved. Do not expand scope beyond the changed lines. Return one of: RESOLVED / STILL OPEN / REGRESSION INTRODUCED. If REGRESSION INTRODUCED: describe what broke and where."

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
