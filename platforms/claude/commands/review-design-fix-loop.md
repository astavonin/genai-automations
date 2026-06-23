---
name: review-design-fix-loop
description: Run initial design review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Design Review Fix Loop Command

Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **architecture-research-planner** (opus) — all substantive design doc edits (content, structure, sections) must go through this agent; the only exception is the one-line `**Status:**` header update, which uses the Edit tool directly (same as `/review-design` Step 6)

## Prerequisite

Design doc exists at `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` with `**Status:** Draft`. No existing review file required — this command produces `design-review.md` itself.

**Open questions pre-flight (blocking gate):** Before Step 1, run:

```
Read ~/.claude/skills/workflows/design-open-questions-gate/SKILL.md
```

Do not proceed to Step 1 until the gate passes.

## Protocol Deviations

When running any review pass in this command (Steps 1, 3, 4), deviate from the `/review-design` protocol as follows — these steps are suppressed because the fix-loop manages them centrally:

- **Skip** the planning-update step (Step 5 of this command handles it once at the end)
- **Skip** the push-planning step (Step 5 handles it)
- **Skip** the "ask user to open file" step (this command runs autonomously)
- **Skip** the "block until approved" step (the loop continues without user input)
- **Skip** the design doc status header update step (`**Status:** Draft → Approved`) — the fix-loop manages the header itself; it sets it only when the initial review (Step 1) or the final clean review (Step 4) returns APPROVED, never during re-review passes (Step 3)
- **Step 4 only — additionally skip:** the prior-review pre-read step. Do not read or pass the existing `design-review.md` to any agent in Step 4. Treat this pass as if no prior review file exists.

**Gate that remains active (not suppressed):** The open questions gate (Step 0 of `/review-design`) runs on every review pass (Steps 1, 3, 4). If Step 2 introduces new open questions in `## 7. Open Questions` despite the prohibition in Step 2's agent instruction, the gate fires. When the gate fires during a loop pass (Steps 3 or 4), use this specific message instead of the gate's default:

```
Fix loop paused — Step 2 introduced new open questions in ## 7. Open Questions despite the prohibition.
Resolve via /design then re-invoke /review-design-fix-loop.
```

Push planning to backup before stopping (to preserve the current `design-review.md`). Do not proceed to Step 5.

## Actions

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial design review..."

Follow `/review-design` with the deviations listed above. Writes `design-review.md`.

If result is `APPROVED`: use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc, then proceed directly to Step 5. Step 1's output is already a clean report — skip Steps 2–4.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2. Do not update the design doc status header. Reset iteration counter to 0.

### Step 2: Fix all findings

Declare: "I'll use architecture-research-planner agent to fix all design findings..."

**Which findings to fix:** Fix all Critical, High, and Medium findings. For Low: fix those with a concrete fix direction stated in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **architecture-research-planner agent** with:
- The full design doc (`design.md`)
- The analysis doc (`analysis.md`) if it exists — for original decision context
- The full list of findings selected above
- Instruction: apply all fixes to `design.md` in one pass; stay at the architectural level; validate any Mermaid diagrams that are added or modified; do not insert RESOLVED markers or finding IDs into the design doc; do NOT add new items to `## 7. Open Questions` — if something cannot be resolved architecturally while applying fixes, flag it as an unaddressable finding instead; flag explicitly any finding that cannot be addressed

**If the architecture-research-planner flags any finding as unaddressable:** surface it to the user immediately and wait for a decision before proceeding to Step 3 — do not silently continue into the next review pass.

**After the agent completes, run `/verify-docs`** on the modified design doc:
- If blockers are reported: invoke architecture-research-planner again scoped to fixing those blockers only, then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles; if blockers persist after 2 cycles, surface a blocker: "Consistency blockers remain after 2 fix attempts — manual intervention needed." Pause and wait for user.
- If warnings only: proceed to Step 3 (warnings are non-blocking).

### Step 3: Re-review

Increment iteration counter. Declare: "I'll use reviewer agent for re-review pass [N]..."

Follow `/review-design` with the deviations listed above. **Pass the current `design-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `design-review.md`.

If result is `APPROVED`: proceed to Step 4. Do not update the design doc status header yet.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2.

**Stall detection:** If the same root-cause area (same section + same component — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes, surface a blocker: "Finding area [section/component] unresolved after 3 passes — manual intervention needed." Pause and wait for user.

### Step 4: Final clean review

Declare: "I'll use reviewer agent for the final clean review..."

Follow `/review-design` with **all** deviations listed above, including the Step 4 addition (skip prior-review pre-read). Overwrites `design-review.md`.

If this final clean review returns `CHANGES REQUESTED` or `REJECTED`: push planning to backup (to preserve the review file), then report to the user and stop:
```
Final clean review: CHANGES REQUESTED — N finding(s).
The fix loop converged but the clean pass found new issues. Review the findings and invoke /review-design-fix-loop again to address them.
```

If `APPROVED`: use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc.

### Step 5: Report and stop

Verify the status marker:
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
Iterations: N  (fix+re-review cycles; 0 if approved on first pass)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md
```

Stop. Do not proceed to `/implement` automatically.
