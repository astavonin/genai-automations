---
name: review-design-fix-loop
description: Run initial design review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Design Review Fix Loop Command

Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **architecture-research-planner** (opus) — all substantive design doc edits (content, structure, sections) must go through this agent; the only exceptions are one-line header metadata updates — `**Status:**` (set to Approved in Steps 1 and 4 on APPROVED result) and `**Revision:**` (incremented in Step 5 when `design_modified = true`) — both use the Edit tool directly

## Prerequisite

Design doc exists at `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` with `**Status:** Draft`. No existing review file required — this command produces `design-review.md` itself.

**Status precondition:** Before Step 1, verify `**Status:** Draft` is present: run `grep '^\*\*Status:\*\* Draft' path/to/design.md`. If not found, stop immediately: "Cannot run /review-design-fix-loop — design.md is not in Draft state. Reset `**Status:**` to `Draft` before re-running."

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
- **Skip** the design doc status header update step (`**Status:** Draft → Approved`) — the fix-loop manages the header itself; it sets it only when the initial review (Step 1) or the final clean review (Step 4) returns APPROVED, never during re-review passes (Step 3). (Note: `/review-iterate` uses the opposite convention — it retains the invoked command's header update rather than managing it centrally. The two commands diverge here intentionally.)
- **Step 4 only — additionally skip:** the prior-review pre-read step. Do not read or pass the existing `design-review.md` to any agent in Step 4. Treat this pass as if no prior review file exists.

**Gate that remains active (not suppressed):** The open questions gate (Step 0 of `/review-design`) runs on every review pass (Steps 1, 3, 4). This is a separate invocation from the pre-Step-1 gate in the Prerequisite section — the gate re-evaluates on each pass because Step 2 may introduce new open questions despite the prohibition. If Step 2 introduces new open questions in `## 8. Open Questions` despite the prohibition in Step 2's agent instruction, the gate fires. When the gate fires during a loop pass (Steps 3 or 4 — not Step 1, which cannot re-fire since the pre-Step-1 gate just passed), use this specific message instead of the gate's default:

```
Fix loop paused — Step 2 introduced new open questions in ## 8. Open Questions despite the prohibition.
Resolve via /design then re-invoke /review-design-fix-loop.
```

Then follow the **Gate re-fire handling** in Actions below. Do not proceed to Step 5.

## Actions

**Preamble:** Initialize `iteration = 0` and `design_modified = false` before Step 1. These are set exactly once at command start and never reset mid-run. Invariant: `**Revision:**` in `design.md` is incremented at most once per invocation — in Step 5 (or any earlier terminal stop path) — contingent on `design_modified = true`.

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial design review..."

Follow `/review-design` with the deviations listed above. Writes `design-review.md`.

If result is `APPROVED`: use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc, then proceed directly to Step 5. Step 1's output is already a clean report — skip Steps 2–4. (No revision bump — the doc was not modified in this run.)

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2. Do not update the design doc status header.

### Step 2: Fix all findings

Declare: "I'll use architecture-research-planner agent to fix all design findings..."

**Which findings to fix:** Fix all Critical, High, and Medium findings. For Low: fix those with a concrete fix direction stated in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **architecture-research-planner agent** with:
- The full design doc (`design.md`)
- The analysis doc (`analysis.md`) if it exists — for original decision context
- The full list of findings selected above
- Instruction: apply all fixes to `design.md` in one pass; stay at the architectural level; validate any Mermaid diagrams that are added or modified; do not insert RESOLVED markers or finding IDs into the design doc; do NOT add new items to `## 8. Open Questions` — if something cannot be resolved architecturally while applying fixes, flag it as an unaddressable finding instead; flag explicitly any finding that cannot be addressed; do not modify the `**Revision:**` or `**Status:**` header fields — these are managed by the command outside the agent invocation

**After the agent completes, set `design_modified = true`.**

**If the architecture-research-planner flags any finding as unaddressable:** run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md` (the agent just completed, so the doc may have been partially modified — bump unconditionally). Then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`). This is a terminal stop. Surface the finding and output:
```
Design review loop paused — unaddressable finding
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after resolving the unaddressable finding via /design.
```
Do not proceed to Step 3.

**Run `/verify-docs`** on the modified design doc:
- If blockers are reported: invoke architecture-research-planner again scoped to fixing those blockers only, then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles (2 is sufficient; more signals a structural issue requiring design changes, not iterative fixes). If blockers clear within 2 cycles, proceed to Step 3. If blockers persist after 2 cycles, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`, then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`). This is a terminal stop. Surface the blocker and output:
```
Design review loop paused — consistency blockers after 2 fix cycles
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after resolving the doc consistency issues.
```
- If warnings only: proceed to Step 3 (warnings are non-blocking).

### Step 3: Re-review

Increment `iteration` (`iteration += 1`). Declare: "I'll use reviewer agent for re-review pass [N]..." where N is the current value of `iteration`.

Follow `/review-design` with the deviations listed above. **Pass the current `design-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `design-review.md`.

If result is `APPROVED`: proceed to Step 4. Do not update the design doc status header yet.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2.

**Stall detection:** If the same root-cause area (same section + same component — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes (3 provides enough signal that the finding requires design-level intervention, not iterative fixes), run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`, then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`). This is a terminal stop. Surface the stall and output:
```
Design review loop paused — stall detected
Finding area [section/component] unresolved after 3 passes.
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after addressing the stalled finding via /design.
```

### Step 4: Final clean review

Declare: "I'll use reviewer agent for the final clean review..."

Follow `/review-design` with **all** deviations listed above, including the Step 4 addition (skip prior-review pre-read). Overwrites `design-review.md`.

If this final clean review returns `APPROVED`: use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc, then proceed to Step 5.

If this final clean review returns `CHANGES REQUESTED` or `REJECTED`: if `design_modified = true` (defensive — at this point `design_modified` is always `true` since reaching Step 4 requires Step 2 to have run), run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`. Then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`). Report to the user and stop:
```
Final clean review: CHANGES REQUESTED — N finding(s).
Iterations completed: [iteration]
The fix loop converged but the clean pass found new issues. Review the findings and invoke /review-design-fix-loop again to address them.
```

### Gate re-fire handling

Step 1 gate re-fire is not possible — the pre-Step-1 gate in the Prerequisite section just passed, so no new open questions exist at that point. This section covers only Steps 3 and 4.

When the open questions gate fires during a review pass (Steps 3 or 4): if `design_modified = true`, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`. Then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`). This is a terminal stop. Output:
```
Design review loop paused — new open questions introduced
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after resolving open questions via /design.
```
Do not proceed to Step 5.

### Step 5: Report and stop

**If `design_modified` is `true`**, run:
```
Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md
```
This is one increment per fix loop run regardless of how many iterations Step 2 executed.

Verify the status marker:
```bash
head -20 planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md | grep -m 1 '^\*\*Status:\*\*'
```

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

Output:
```
Design review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md
```

Stop. Do not proceed to `/implement` automatically.
