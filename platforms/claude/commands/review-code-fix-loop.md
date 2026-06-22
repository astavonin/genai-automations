---
name: review-code-fix-loop
description: Run initial code review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Code Review Fix Loop Command

Run the full code review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **coder** (sonnet) — fix all findings between review passes

## Prerequisite

Implementation exists on the branch. No existing review file required — this command produces `code-review.md` itself.

## Actions

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial code review..."

Follow `/review-code` exactly — full 3+1 consensus + Codex, all mandatory passes (Test Quality, Cross-Site Consistency, Dead Symbol). Writes `code-review.md`.

If result is `APPROVED`: proceed directly to Step 4 (final review + report). No fixes needed.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2.

### Step 2: Fix all findings

Declare: "I'll use coder agent to fix all findings from the current review..."

Invoke **coder agent** with:
- The full list of all current findings (Critical, High, and any Medium/Low that have actionable fixes)
- The full design doc if one exists (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`)
- Instruction: fix all listed findings in one pass; do not leave any finding unaddressed without an explicit reason

After the coder agent completes, verify the build passes before proceeding.

### Step 3: Re-review

Declare: "I'll use reviewer agent for re-review pass N..."

Follow `/review-code` exactly — same full protocol as Step 1. Overwrites `code-review.md` (per the file overwrite convention — no versioning suffixes).

If result is `APPROVED`: proceed to Step 4.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2 with the new finding list.

There is no automatic iteration cap — continue until `APPROVED`. If the same findings recur across 3 consecutive passes without progress, surface a blocker to the user and pause for a decision.

### Step 4: Final clean review

Once a review pass returns `APPROVED`, run the full `/review-code` protocol one final time — **without passing any prior review file as context**. This produces a clean report uncontaminated by prior-finding language.

Overwrites `code-review.md` with the final clean report.

### Step 5: Report and stop

Print the final review status and finding summary.

Run the review-planning-update fragment:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`)

Output:
```
Code review loop complete: APPROVED
Iterations: N
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md
```

Stop. Do not proceed to `/verify` automatically — the user drives the next step.
