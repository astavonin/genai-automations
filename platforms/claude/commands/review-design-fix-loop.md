---
name: review-design-fix-loop
description: Run initial design review, fix all findings, re-review until APPROVED or the iteration cap, then print the report
---

# Design Review Fix Loop Command

Run the full design review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **architecture-research-planner** (opus) — all substantive design doc edits (content, structure, sections) must go through this agent; the only exceptions are one-line header metadata updates — `**Status:**` (set on `APPROVED` per the Protocol Deviations status-header bullet below), `**Approved:**` (added alongside `**Status:**` at Step 1 — both branch 1 and branch 2, the latter at Step 5 after the bump — and at Step 3), and `**Revision:**` (incremented in Step 5 when `design_modified = true`) — all three use the Edit tool directly

## Prerequisite

Design doc exists at `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` with `**Status:** Draft`. No existing review file required — this command produces `design-review.md` itself.

**Status precondition:** Before Step 1, verify `**Status:** Draft` is present: run `grep '^\*\*Status:\*\* Draft' path/to/design.md`. If not found, stop immediately: "Cannot run /review-design-fix-loop — design.md is not in Draft state. Reset `**Status:**` to `Draft` before re-running."

**Open questions pre-flight (blocking gate):** Before Step 1, run:

```
Read ~/.claude/skills/workflows/design-open-questions-gate/SKILL.md
```

Do not proceed to Step 1 until the gate passes.

**Resolve `<issue-folder>`:**

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Resolve `<issue-folder>` once and echo it. Step 2's `/verify-docs` call and the `### Cap-pause` block's `review-planning-update` call both reuse this exact string instead of re-deriving it.

## Protocol Deviations

When running any review pass in this command (Steps 1 and 3), deviate from the `/review-design` protocol as follows — these steps are suppressed because the fix-loop manages them centrally:

- **Skip** the round-verdict step — `/review-design` states one per pass, and this loop states it once at whichever exit it reaches. Without this a three-round run emits four verdicts that may disagree, against a fragment specifying one line at the end of the run.
- **Skip** the planning-update step (Step 5 of this command handles it once at the end)
- **Skip** the push-planning step (Step 5 handles it)
- **Skip** the "ask user to open file" step (this command runs autonomously)
- **Skip** the "Phase gate (MANDATORY)" step (the loop continues without user input — this is the step in `/review-design` that blocks until the user invokes `/implement`; the fix-loop's autonomy is authorized by the Exception clause in CLAUDE.md Critical Rules)
- **Skip** the design doc status header update step (naming `**Status:**` and `**Approved:**`) — the fix-loop manages the header itself; it sets it in three places: when the initial review (Step 1) returns APPROVED on branch 1; on branch 2, at Step 5 after the revision bump; and on the fragment's APPROVED row in Step 3. (Note: `/review-iterate` uses the opposite convention — it retains the invoked command's header update rather than managing it centrally. The two commands diverge here intentionally.)

**Gate that remains active (not suppressed):** The open questions gate (Step 0 of `/review-design`) runs on every review pass (Steps 1 and 3). This is a separate invocation from the pre-Step-1 gate in the Prerequisite section — the gate re-evaluates on each pass because Step 2 may introduce new open questions despite the prohibition. If Step 2 introduces new open questions in `## 8. Open Questions` despite the prohibition in Step 2's agent instruction, the gate fires. When the gate fires during a loop pass (Step 3 — not Step 1, which cannot re-fire since the pre-Step-1 gate just passed), use this specific message instead of the gate's default:

```
Fix loop paused — Step 2 introduced new open questions in ## 8. Open Questions despite the prohibition.
Resolve via /design then re-invoke /review-design-fix-loop.
```

Then follow the **Gate re-fire handling** in Actions below. Do not proceed to Step 5.

## Actions

**Preamble:** Initialize `iteration = 0` and `design_modified = false` before Step 1. These are set exactly once at command start and never reset mid-run. Invariant: `**Revision:**` in `design.md` is incremented at most once per invocation — in Step 5 (or any earlier terminal stop path) — contingent on `design_modified = true`.

### Step 1: Initial review

Follow `/review-design` with the deviations listed above. Writes `design-review.md`.

**The header edit**, referenced by branches 1 and 2 below: use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc, and add an `**Approved:** <YYYY-MM-DD>, at Revision <N>, by design review` line below `**Revision:**` — reading the doc's current revision rather than assuming it. On branch 1 there is no revision bump, because the doc was not modified in this run; branch 2 amends both the revision and the wording, as stated there.

**Three exclusive branches. Evaluate in order and take the first that matches** — the finding counts decide, not the `**Status:**` string alone, because a Medium-only review and a High-bearing review both write `CHANGES REQUESTED`:

1. **`APPROVED`** → the header edit above, then Step 5. Skip Steps 2 and 3.
2. **`CHANGES REQUESTED` with zero Critical and zero High** — the Medium-only path → **Step 2 with `exit_to = Step 5`**, then Step 5. Skip Step 3. This path counts as no loop pass.
3. **`CHANGES REQUESTED` with one or more Critical or High, or `REJECTED`** → **Step 2 with `exit_to = Step 3`**, the full cycle. Do not update the design doc status header.

`exit_to` is Step 2's only parameter and it is mandatory: Step 2's own terminal lines name it rather than a literal step number, so branch 2 cannot be overridden by the step it delegates to.

**Branch 2 runs the open-questions gate once, between Step 2 and the approval write.** Step 2 edits `design.md` and may introduce new `## 8. Open Questions` items despite the prohibition; the gate that catches that is scoped to Step 3, and branch 2 has no Step 3. Without this the doc reaches `**Status:** Approved` carrying unresolved open questions — the Phase 2 blocking condition — and nothing downstream recovers it: `/verify-docs` has no open-question handling and `/implement`'s precondition 1(e) checks only *on-device* open questions.

```
Read ~/.claude/skills/workflows/design-open-questions-gate/SKILL.md
```

A fire routes to the **Gate re-fire handling** in Actions, with the same message the Protocol Deviations section states. Do not write the approval and do not proceed to Step 5.

**On branch 2 the orchestrator writes the approval itself, in two places.** **Perform this write only after Step 2 completes and its own gate passes — `/verify-docs` reporting no blockers, and `doc-metrics` showing no `OVER-CEILING` row — immediately before entering Step 5**; never before Step 2 runs. An early write publishes `APPROVED` planning state and sets the design doc's header on a doc whose fixes are blocked, turning a loud stop into a silently approved design. In `design-review.md`, overwrite `**Status:**` to `APPROVED`, `**Assessment:**` to `✅ Approve`, and `## Recommendation` to name the closed findings, then add a `## Mediums Fixed Without Re-Review` heading listing them. The `design.md` half is **not** written here: it is a numbered item inside Step 5, performed after the revision bump, because Step 2 modified the doc and the bump moves it to `N+1`. Step 5 sets `**Status:** Approved` and writes `**Approved:** <YYYY-MM-DD>, at Revision <N+1>, by design review (Mediums fixed without re-review)`, reading the bumped value rather than the pre-fix one. Branch 1's parenthetical — "the doc was not modified in this run" — is false here and must not be copied.

**What branch 2 gives up:** no review pass grades those fixes; it rests on `/verify-docs` reporting no blockers at the end of Step 2. Take branch 3 instead when Step 2's report says a fix **changed a heading, requirement ID, or contract read by more than one section**, or **added a subsection, option, or mechanism rather than removing text** — Step 2's agent instructions require that report. A design fix pass produced all seven of one round's Highs on this repo's own record.

### Step 2: Fix all findings

**Which findings to fix:** Fix all Critical, High, and Medium findings. For Low: fix those with a concrete fix direction stated in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **architecture-research-planner agent** with:
- The full design doc (`design.md`)
- The analysis doc (`analysis.md`) if it exists — for original decision context
- The full list of findings selected above
- **Report per finding, so the caller can choose its exit:** whether the fix changed a heading, requirement ID, or contract read by **more than one section**, and whether it **added** a subsection, option, or mechanism rather than removing text. Branch 2's decision to skip the re-review reads this and nothing else.
- Instruction: apply all fixes to `design.md` in one pass; stay at the architectural level; validate any Mermaid diagrams that are added or modified; do not insert RESOLVED markers or finding IDs into the design doc; do NOT add new items to `## 8. Open Questions` — if something cannot be resolved architecturally while applying fixes, flag it as an unaddressable finding instead; flag explicitly any finding that cannot be addressed; do not modify the `**Revision:**` or `**Status:**` header fields — these are managed by the command outside the agent invocation
- **Instruction — resolve by subtraction where subtraction is the honest fix:** rewriting or deleting text is a valid way to resolve a finding, not a lesser one. Reach for it first when the finding reports ambiguity, contradiction, redundancy, or an unsupported claim — the cause is usually text that should not be there, and adding a clarification on top leaves the original problem in place with a caveat attached. Add text when the finding reports a genuine gap; remove or rewrite it when the finding reports that existing text is wrong, unclear, or duplicated. Before deleting a section, check for inbound cross-references and update them in the same pass — an orphaned reference trips `/verify-docs` on the next step.

  This is not licence to skip a finding: every selected finding must still be resolved or explicitly flagged unaddressable. It changes *how* you may resolve it, not *whether*. Without it every confirmed finding becomes an append, and the document only ever grows.

- **Instruction — this command does not grow the document by default.** The unit is one invocation of the fix loop, not one Step 2 pass and not one finding: Step 3 re-enters Step 2 on every CHANGES REQUESTED, and a per-pass budget would forbid a legitimate addition in the third pass even when the first two removed more than it adds. Take one measurement before the first Step 2 and one after the last, and target a total no higher than the one you started from:

  ```bash
  doc-metrics <path-to-design.md>
  ```

  **Exit contract:** `0` means it ran — read the numbers. Any non-zero exit is a blocker, not a clean result; exit `127` means the package is not installed — `pip install -e ./tools/docgate`. Exit status never signals "over ceiling" or "register hits found", so do not wire `&&` to it.

  The exception is a genuine gap: a finding reporting missing information is resolved by adding it, and that pass legitimately grows. Name the finding IDs that justified the growth in your response. What this rule blocks is the other case — resolving an ambiguity or a contradiction by appending a clarification, where the words are added and the defect stays. If the total grew and no finding reported a gap, find the append and replace it with a rewrite before you finish.

  **Also report any deletion not attributable to a finding.** A flat total plus a required addition means something else was cut, and this instruction is what creates the pressure to cut it. List what you removed and which finding asked for it; if nothing asked, say so. Deleting load-bearing prose to fund an addition is the failure mode this rule introduces, and no other check in the loop can see it — the re-review checks the findings, `/verify-docs` checks form and length, and neither knows what the document used to say.

**After the agent completes, set `design_modified = true`.**

**If the architecture-research-planner flags any finding as unaddressable:** run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md` (the agent just completed, so the doc may have been partially modified — bump unconditionally). Then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`). This is a terminal stop. Surface the finding and output:
```
Design review loop paused — unaddressable finding
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after resolving the unaddressable finding via /design.
```
Do not proceed to Step 3.

**Run `/verify-docs`** on the modified design doc, passing the `<issue-folder>` resolved in the Prerequisite section. Without the folder, `/verify-docs` has nothing to enumerate — `git diff` never lists a planning doc — so both its scans run over an empty file list and it reports `Clean`, taking the citation gate and the register gate with it.
- If blockers are reported: invoke architecture-research-planner again scoped to fixing those blockers only, then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles (2 is sufficient; more signals a structural issue requiring design changes, not iterative fixes). If blockers clear within 2 cycles, proceed to `exit_to`. If blockers persist after 2 cycles, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`, then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`). This is a terminal stop. Surface the blocker and output:
```
Design review loop paused — consistency blockers after 2 fix cycles
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after resolving the doc consistency issues.
```
- If warnings only: proceed to `exit_to` (warnings are non-blocking) — Step 3 on branch 3, Step 5 on branch 2. Never a literal step number.

### Step 3: Re-review

```
Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md
```

Follow `/review-design` with the deviations listed above. **Pass the current `design-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `design-review.md`.

On the fragment's `APPROVED` row, before that row's route is taken, use the Edit tool to change `**Status:** Draft` to `**Status:** Approved` in the design doc, and add an `**Approved:** <YYYY-MM-DD>, at Revision <N>, by design review` line below `**Revision:**`. Read the current revision rather than assuming it — the bump has not run yet, so the value on the doc is the revision this pass reviewed.

**This file is parsed by two tests.** `tests/verify-workflow-safety.sh` asserts this Step 3 carries the fragment's `Read` pointer above, ahead of a review-pass launch sentence that begins with the word `Follow`, with no destination sentence or increment of its own, that neither this file's frontmatter nor its body still promises the deleted review pass that used to follow Step 3, that its `**Status:** Draft → Approved` edit sits here rather than on the review's removed final-clean-review step, that its Protocol Deviations status-header bullet and `## Agents` note the same two-step set with no third restatement, that every `Step <N>` reference in this file resolves to a heading here, and that the `### Cap-pause` and `### Stall stop` headings below exist and run their procedures in the order the fragment names. `tests/verify-config-consistency.sh` asserts the `Read` pointer above resolves to a non-empty file. Editing the step numbering, the status-header bullet, the pointer, or the launch sentence's opening word without re-running both is how this drifts silently.


### Stall stop

The blocker message this prints carries the verdict as its last line: `Another round: [yes|no] — [reason]`. A stall is an exit where a human decides whether to continue, and this block does not route through Step 5.

If the same root-cause area (same section + same component — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes (3 provides enough signal that the finding requires design-level intervention, not iterative fixes), run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`, then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`). This is a terminal stop. Surface the stall and output:
```
Design review loop paused — stall detected
Finding area [section/component] unresolved after 3 passes.
Iterations completed: [iteration]
Re-invoke /review-design-fix-loop after addressing the stalled finding via /design.
```

### Cap-pause

If `design_modified = true`, run:
```
Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md
```

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`)

Report to the user and stop. If the re-review that reached the cap returned `CHANGES REQUESTED`:
```
Design review loop paused — iteration cap reached
Iterations completed: [iteration]
N finding(s) open in planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md.
Another round: [yes|no] — [reason]
Resolve via /design, then re-invoke /review-design-fix-loop to continue.
```

If it returned `REJECTED`:
```
Design review loop paused — iteration cap reached
Iterations completed: [iteration]
planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md was rejected.
Another round: [yes|no] — [reason]
Redesign is required — resolve via /design, then re-invoke /review-design-fix-loop.
```

### Gate re-fire handling

Step 1 gate re-fire is not possible — the pre-Step-1 gate in the Prerequisite section just passed, so no new open questions exist at that point. This section covers only Step 3.

When the open questions gate fires during a review pass (Step 3): if `design_modified = true`, run `Read ~/.claude/skills/workflows/design-revision-bump/SKILL.md`. Then run the review-planning-update fragment (which includes push): `Read ~/.claude/skills/workflows/review-planning-update/SKILL.md` (`review_label = design review`, `approved_phase = implementing 🔨`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`). This is a terminal stop. Output:
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

**On branch 2 only, write the `design.md` header now — after the bump, never before it.** Set `**Status:** Draft` to `**Status:** Approved` and add `**Approved:** <YYYY-MM-DD>, at Revision <N+1>, by design review (Mediums fixed without re-review)`, reading `**Revision:**` after the bump above so the recorded number is the one the doc carries. Branch 1 wrote its header at Step 1 with no bump and reaches this step with nothing to do; branch 3 reaches it through the fragment's `APPROVED` row, which writes its own.

The verdict this step prints, and the signals its reason rests on:

```
Read ~/.claude/skills/workflows/round-verdict/SKILL.md
```


Verify the status marker:
```bash
head -20 planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md | grep -m 1 '^\*\*Status:\*\*'
```

**Branch on the value, do not print it unchecked.** If the marker is not `APPROVED`, stop and surface the mismatch instead of running the planning fragment or printing the completion line — branch 2 is the first route on which the orchestrator writes this marker itself, so it is the first on which the marker and the report can disagree.

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`, `issue_folder = <issue-folder>`)

Output:
```
Design review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 when no re-review ran)
Mediums fixed without re-review: [finding IDs, or "none"]
Another round: [yes|no] — [reason]
Design doc: [before] → [after] prose words ([+/-N]), register [before] → [after]
Design doc: not modified   (print this line instead when Step 1 returned APPROVED)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md
```

Both numbers come from the `TOTAL` row of one run before Step 2 and one after the last fix pass:

```bash
doc-metrics <path-to-design.md>
```

The delta enforces nothing here — Step 2 carries the net-non-growth instruction and `/verify-docs` carries the register gate — but it makes growth visible on every run. `wc -l` cannot: the repo bans manual line wrapping, so one paragraph is one line and a fix pass that adds 400 words to an existing paragraph shows a delta of 0. An earlier attempt at this rule reported `-0%` lines against a real `-2.1%` word change for exactly that reason. Prose words also exclude table rows, so converting a bloated paragraph into a table — the compression the rules ask for — registers as the reduction it is instead of as growth.

Stop. Do not proceed to `/implement` automatically.
