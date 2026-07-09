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

- **coder** (sonnet) — apply fixes for code reviews
- **architecture-research-planner** (opus) — apply fixes for design reviews; the `**Revision:**` header increment at the end of Step 2 uses the Edit tool directly — same one-line-metadata exemption pattern as documented in `/review-design-fix-loop` (Agents section)
- **reviewer** (opus) — initial review (full protocol) + per-finding scoped verification (single agent) + final re-review (full protocol)

## Prerequisite

Determine review type from context:
- Code review: implementation exists on branch, or `code-review.md` already exists with `CHANGES REQUESTED`
- Design review: design doc exists, or `design-review.md` already exists with `CHANGES REQUESTED`

If a review file already exists with `CHANGES REQUESTED` or `REJECTED`, skip Step 0 and start from Step 1 (re-entering the loop on an in-progress review). If the review file is `APPROVED`: run the review-planning-update fragment (which includes push) to reconcile planning state:
- Code review: `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`)
- Design review: `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

Report `Review already APPROVED — no fix loop needed`, and stop.

If both review files exist with open status, ask the user which to iterate on.

## Protocol Deviations

When running any review pass in this command (Steps 0 and 3), deviate from the invoked protocol as follows — these steps are suppressed because `/review-iterate` manages them centrally at Step 4:

- **Skip** the planning-update step — Step 4 of this command runs it once at the end
- **Skip** the push-planning step — Step 4 handles it
- **Skip** the "ask user to open file" step — this command runs autonomously
- **Skip** the "block until approved" step — the command continues without user input
- **Retain** the design doc `**Status:** Draft → Approved` header update (Step 6 of `/review-design`) — the invoked command manages this transition when the initial review (Step 0) OR the final review (Step 3) returns APPROVED; `/review-iterate` does not manage this header centrally. (Note: `/review-design-fix-loop` uses the opposite convention — it skips this step and manages the header transition itself in Steps 1 and 4. The two commands diverge here intentionally.)

## Actions

**Preamble (design reviews only):** Initialize `design_modified = false` before Step 0. Set to `true` in Step 2b immediately after any fix — agent-driven or confirmed manual — is applied to `design.md`. Invariant: `**Revision:**` in `design.md` is incremented at most once per invocation, immediately before Step 3 (or at any earlier exit point), when `design_modified = true`. For code reviews, `design_modified` is not initialized and the revision bump is skipped entirely — code reviews have no `**Revision:**` header to increment.

### Step 0: Initial review

Declare: "I'll use reviewer agent for the initial review..."

Run the **complete review protocol** for the appropriate type:
- Code review: follow `/review-code` exactly — full 3+1 consensus + Codex, all mandatory passes, writes `code-review.md`
- Design review: follow `/review-design` exactly — full 3+1 consensus + Codex, writes `design-review.md`

If the result is `APPROVED`: run the review-planning-update fragment (which includes push):
- Code review: `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`)
- Design review: `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

Report `Initial review: APPROVED — no findings`, and stop. No fix loop needed.

If the result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 1.

**If the open-questions gate in the invoked `/review-design` fires during Step 0** (design.md has unresolved open questions before any fixes have been applied): the gate surfaces its message and stops the invoked command. `/review-iterate` terminates without running Steps 1–4. No revision bump or planning update is needed — no design edits occurred.

### Step 1: Load open findings

Read the review file. Extract every finding with severity Critical, High, or Medium (mandatory to address) and any Low findings the user opts to include.

Display the full list: ID, severity, one-line description.

Count: "N findings to resolve (C Critical, H High, M Medium, L Low)."

### Step 2: Fix-verify loop (per finding)

**Review type → fix agent:**

| Review type | Fix agent |
|-------------|-----------|
| Code review | coder (sonnet) |
| Design review | architecture-research-planner (opus) |

Process findings in severity order: Critical → High → Medium → Low.

For each finding:

**2a. Present the finding** — show full description, location, and fix direction from the review.

**2b. Apply the fix:**

For **code-review findings**, apply these test requirements before invoking the agent or accepting a manual fix:
- **Critical and High findings (mandatory):** the fix must include new or modified tests. Use unit tests for isolated logic and integration tests when the finding involves component interaction, external state, or runtime composition. No Critical or High finding is considered fixed without a corresponding test change.
- **Any severity with `Required test:` line:** implementing the described test is mandatory as part of the fix.

For **design-review findings**, no test requirements apply — the fix is a doc edit; the design agent applies it and Step 2c verifies the architectural concern is resolved.

**Agent-driven is the default.** Two exception cases:
- User explicitly requests manual for this finding → fall back to manual: wait for user to confirm the fix is applied, then continue
- Agent declines with a reason → for design reviews, if `design_modified = true`, first run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`. For all review types, run the review-planning-update fragment (which includes push; use the review-type-matching parameters from Step 4). Surface as an unaddressable blocker: "Fix agent declined finding [ID] with reason: <reason>. Manual intervention needed." This is a terminal stop — do NOT silently fall back to manual. Output:
  ```
  /review-iterate paused — fix agent declined finding [ID]
  Invoke /review-iterate after resolving.
  ```

Invoke the appropriate agent:
- Code review: declare "I'll use coder agent to fix [finding ID]…" and invoke coder agent scoped to this finding only, explicitly passing the test requirements above
- Design review: declare "I'll use architecture-research-planner agent to fix [finding ID]…" and invoke architecture-research-planner scoped to this finding only; instruct it not to add new items to `## 8. Open Questions` and not to modify the `**Revision:**` or `**Status:**` header fields — if it cannot address a finding, it must flag it explicitly rather than declining silently

After applying any design-review fix (agent-driven or confirmed manual), set `design_modified = true`.

**2c. Scoped verification** — invoke a **single reviewer agent** (not full consensus) with:
- The specific finding ID, description, and fix direction
- Output of `git diff` since the review baseline (or since the last commit)
- Instruction: "Verify ONLY whether finding [ID] has been resolved. Do not expand scope beyond the changed lines. Return one of: RESOLVED / STILL OPEN / REGRESSION INTRODUCED. If REGRESSION INTRODUCED: describe what broke and where. For Critical and High **code-review** findings: also verify that a new or modified test covers the fix — return STILL OPEN if no test change is present. For Critical, High, and Medium **design-review** findings: verify the design.md change addresses the architectural concern named in the finding — return STILL OPEN if only cosmetic edits were made or the concern remains visible in the updated section."

**2d. Record result**:
- **RESOLVED** → mark finding fixed, proceed to next finding
- **STILL OPEN** → show reviewer feedback, loop back to 2b for this finding (cap at 3 retries; 3 provides enough signal that the finding needs different intervention). If still open after 3 retries: (a) for design reviews, if `design_modified = true`, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`; (b) for both review types, run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (use the review-type-matching parameters from Step 4); (c) surface as a blocker: "Finding [ID] unresolved after 3 attempts — manual intervention needed." This is a terminal stop. Output:
  ```
  /review-iterate paused — finding [ID] unresolvable after 3 attempts
  Invoke /review-iterate after resolving.
  ```
- **REGRESSION INTRODUCED** → treat as a new Critical finding with its own fresh 3-retry cap. Re-enter 2b for the regression; if the regression is resolved, resume the original loop at the parent finding's next retry attempt (the parent finding's retry counter is not reset). If a regression fix triggers a further REGRESSION result, apply the same stacking rules recursively — each nested regression gets its own fresh 3-retry cap; all ancestor counters remain frozen. A cap-3 failure at any nesting level is a terminal stop (same procedure as below). If the regression itself hits cap-3: (a) for design reviews, if `design_modified = true`, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`; (b) for both review types, run the review-planning-update fragment (which includes push; use the review-type-matching parameters from Step 4); (c) surface as a blocker: "Regression [ID] unresolvable after 3 attempts — manual intervention needed." This is a terminal stop. Output:
  ```
  /review-iterate paused — regression [ID] unresolvable after 3 attempts
  Invoke /review-iterate after resolving.
  ```

Continue until all findings from Step 1 are RESOLVED.

**Immediately before Step 3, if this is a design review and `design_modified = true`**, run:
```
Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md
```
One increment per `/review-iterate` invocation regardless of how many per-finding fix passes occurred. (Early-exit paths — Step 2b agent-decline and Step 2d cap-3 blockers — that bump revision are terminal stops; the pre-Step-3 bump here is only reached when Step 2 completed normally without hitting a blocker.)

### Step 3: Final full re-review

Once all findings are resolved, declare: "I'll use reviewer agent for the final full re-review..."

Run the **complete review protocol** by invoking the appropriate command:
- Code review: follow `/review-code` exactly — full 3+1 consensus + Codex, mandatory passes (Test Quality, Cross-Site Consistency, Dead Symbol), overwrites `code-review.md`
- Design review: follow `/review-design` exactly — full 3+1 consensus + Codex, overwrites `design-review.md`

Do not shortcut the protocol. This is the convergence gate.

### Gate re-fire handling (design reviews only)

If the open-questions gate fires during Step 3 (the final re-review invokes `/review-design`, which runs its open-questions gate at Step 0): this means Step 2 applied a design fix that inadvertently introduced new open questions in `## 8. Open Questions`. Use this message:

```
/review-iterate paused — Step 2 introduced open questions in ## 8. Open Questions.
Resolve via /design then re-invoke /review-iterate.
```

The pre-Step-3 bump (immediately before Step 3) has already run if `design_modified = true` — do not bump again. Run the review-planning-update fragment (which includes push) using the design-review parameters from Step 4. This is a terminal stop. Output:
```
/review-iterate paused — open questions introduced during Step 2
Invoke /review-iterate after resolving open questions via /design.
```

### Step 4: Report and stop

After Step 3 completes, run the review-planning-update fragment (which includes push).

**If `APPROVED`:**

Code review — run:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`)

Design review — run:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`)

**If `CHANGES REQUESTED` or `REJECTED`:** list all new findings. Run the review-planning-update fragment (which includes push; same parameters as the APPROVED case for the current review type).

**Stop. Do not automatically start a new fix-verify loop.**

Output:
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
