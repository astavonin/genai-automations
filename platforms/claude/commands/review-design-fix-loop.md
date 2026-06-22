---
name: review-design-fix-loop
description: Run initial design review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Design Review Fix Loop Command

Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **architecture-research-planner** (opus) — fix all findings between review passes (design doc edits must always go through this agent — never use Write/Edit tools directly on design docs)

## Prerequisite

Design doc exists at `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` with `**Status:** Draft`. No existing review file required — this command produces `design-review.md` itself.

## Actions

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial design review..."

Follow `/review-design` exactly — full 3+1 consensus + Codex, Design-Level Constraint applied to every agent. Writes `design-review.md`.

If result is `APPROVED`: update design doc status header (`**Status:** Draft → **Status:** Approved`), then proceed directly to Step 5 (report and stop). Step 1's output is already a clean report — no final re-review needed.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2. Do **not** update the design doc status header yet.

### Step 2: Fix all findings

Declare: "I'll use architecture-research-planner agent to fix all design findings..."

**Which findings to fix:** Fix all Critical and High findings. For Medium and Low: fix those with a concrete fix direction stated in the review; skip advisory-only Medium/Low findings. Do not ask the user — apply this rule consistently.

Invoke **architecture-research-planner agent** with:
- The full design doc (`design.md`)
- The analysis doc (`analysis.md`) for original decision context
- The full list of findings selected above
- Instruction: apply all fixes to `design.md` in one pass; stay at the architectural level; do not leave any selected finding unaddressed without flagging it explicitly; do not insert RESOLVED markers or finding IDs into the design doc — those belong in the review report only

**After the agent completes, run `/verify-docs`** on the modified design doc to catch consistency drift:
- If `/verify-docs` reports blockers: invoke architecture-research-planner again scoped to fixing only those blockers, then re-run `/verify-docs` until clean
- If `/verify-docs` reports warnings only: proceed to Step 3 (warnings are non-blocking)

### Step 3: Re-review

Declare: "I'll use reviewer agent for re-review pass N..." (track N starting from 1)

Follow `/review-design` exactly — same full protocol as Step 1. **Pass the current `design-review.md` as prior review context** so agents can verify prior findings are addressed. Overwrites `design-review.md`.

If result is `APPROVED`: proceed to Step 4. Do **not** update the design doc status header yet — wait for the final clean review.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2 with the new finding list.

**Stall detection:** If the same root-cause area (same section + same component, not same finding ID — IDs reset each pass) appears in 3 consecutive re-review passes without being resolved, surface a blocker to the user and pause: "Finding in [area] has not been resolved after 3 passes — manual intervention needed." Do not continue the loop automatically.

### Step 4: Final clean review

Declare: "I'll use reviewer agent for the final clean review..."

Run the full `/review-design` protocol one final time. **Critical:** instruct all reviewer agents and Codex to treat this as a fresh review — do NOT read or reference the existing `design-review.md` from prior passes. This pass must be conducted as if no prior review exists, producing a report uncontaminated by prior-finding language.

Overwrites `design-review.md` with the final clean report.

If this final clean review returns `CHANGES REQUESTED` or `REJECTED`: report the findings to the user and stop. Do not automatically re-enter the fix loop — output:
```
Final clean review: CHANGES REQUESTED — N finding(s).
The fix loop converged but the clean pass found new issues. Review the findings and invoke /review-design-fix-loop again to address them.
```

If `APPROVED`: update design doc status header: `**Status:** Draft → **Status:** Approved`.

### Step 5: Report and stop

Verify the status marker is present in `design-review.md`:
```bash
head -20 planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md | grep -m 1 '^\*\*Status:\*\*'
```

Run the review-planning-update fragment:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

Push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Output:
```
Design review loop complete: APPROVED
Iterations: N  (0 if approved on first pass)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md
```

Stop. Do not proceed to `/implement` automatically — the user drives the next step.
