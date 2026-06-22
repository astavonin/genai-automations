---
name: review-design-fix-loop
description: Run initial design review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Design Review Fix Loop Command

Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **architecture-research-planner** (opus) — fix all findings between review passes (design doc edits must always go through this agent)

## Prerequisite

Design doc exists at `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`. No existing review file required — this command produces `design-review.md` itself.

## Actions

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial design review..."

Follow `/review-design` exactly — full 3+1 consensus + Codex, Design-Level Constraint applied to every agent. Writes `design-review.md`.

If result is `APPROVED`: update design doc status header (`**Status:** Draft → Approved`) then proceed directly to Step 4 (final review + report). No fixes needed.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2.

### Step 2: Fix all findings

Declare: "I'll use architecture-research-planner agent to fix all design findings..."

Invoke **architecture-research-planner agent** with:
- The full design doc
- The full list of all current findings (Critical, High, and any Medium/Low that have actionable fixes)
- Instruction: apply all fixes to the design doc in one pass; stay at the architectural level; do not leave any finding unaddressed without an explicit reason

The agent edits `design.md` directly. After the agent completes, run `/verify-docs` on the modified design doc to catch any consistency drift introduced by the fixes before re-reviewing.

### Step 3: Re-review

Declare: "I'll use reviewer agent for re-review pass N..."

Follow `/review-design` exactly — same full protocol as Step 1. Overwrites `design-review.md`.

If result is `APPROVED`: update design doc status header (`**Status:** Draft → Approved`) then proceed to Step 4.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2 with the new finding list.

There is no automatic iteration cap — continue until `APPROVED`. If the same findings recur across 3 consecutive passes without progress, surface a blocker to the user and pause for a decision.

### Step 4: Final clean review

Once a review pass returns `APPROVED`, run the full `/review-design` protocol one final time — **without passing any prior review file as context**. This produces a clean report uncontaminated by prior-finding language.

Overwrites `design-review.md` with the final clean report. Update design doc status header to `Approved` if not already set.

### Step 5: Report and stop

Print the final review status and finding summary.

Run the review-planning-update fragment:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

Output:
```
Design review loop complete: APPROVED
Iterations: N
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md
```

Stop. Do not proceed to `/implement` automatically — the user drives the next step.
