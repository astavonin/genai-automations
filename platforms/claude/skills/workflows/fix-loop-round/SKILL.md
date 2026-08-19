---
name: fix-loop-round
description: Shared fragment — the review-and-branch round every fix loop's Step 3 runs, bounded by the iteration cap stated below. Called by review-code-fix-loop, review-design-fix-loop, review-article-fix-loop at Step 3. Caller specifies its `### Cap-pause` and `### Stall stop` blocks, the `iteration` counter its preamble initialises, the Step 2 and Step 5 the branch table routes to, and the four per-verdict message values.
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, review, fix-loop, cap]
---

# Fix-Loop Round — Shared Fragment

A **round** is one review pass of a fix-loop invocation. The initial review at a loop's Step 1 is round 0 and carries no `iteration`; this fragment is read at Step 3, before every later round, so the pass it runs at `iteration = N` is round N. It increments the counter, runs the review pass, and branches on the result — the one procedure `review-code-fix-loop.md`, `review-design-fix-loop.md`, and `review-article-fix-loop.md` all read here instead of stating three times.

**Iteration cap:** `3`

## The Round

| # | Position |
|---|---|
| 1 | increment `iteration` |
| 2 | run the review pass |
| 3 | branch on the result |

Position 3 takes the first matching row:

| Verdict | Condition | Next |
|---|---|---|
| APPROVED | any | Step 5 |
| not APPROVED | stall condition met | the calling loop's `### Stall stop` |
| not APPROVED | `iteration` below the cap | Step 2 |
| not APPROVED | `iteration` at or above the cap | the calling loop's `### Cap-pause` |

Two things about this table are load-bearing. Position 1 is `iteration`'s only increment site — a caller that keeps its own increment line in Step 3 counts a round twice and fires the cap a cycle early. The two `not APPROVED` cap rows read `at or above the cap`, not `equal to it` — an overshooting counter would otherwise run one round past the pause.

## The Cap-Pause Block

Every loop holds a `### Cap-pause` heading, the name this table's cap row routes to. Its shape is fixed here and restated in no loop: the loop's own cleanup and revision steps, in the order its other terminal stops already use, then `review-planning-update` with all five parameters (`issue_folder` included), then the message below with its four values filled in. What reaches it is whatever verdicts the calling loop's own review command admits beyond APPROVED — `CHANGES REQUESTED` and `REJECTED` for a three-state loop, `CHANGES REQUESTED` alone for a loop whose review command's File Overwrite Convention has no `REJECTED` state.

One message form per verdict the loop can reach. Four values are filled in per loop, read off that loop's own other paused stops rather than invented fresh here: the **label** on the first line, the **report path**, the **command** name, and the **recovery** action.

`CHANGES REQUESTED` form, shown with `/review-code-fix-loop`'s values:

```
[label] paused — iteration cap reached
Iterations completed: [iteration]
N finding(s) open in [report path].
[recovery]
```

`REJECTED` form — a rejection is not N findings to fix by hand, so this form names the report as rejected and sends the user to redesign instead of to a manual fix:

```
[label] paused — iteration cap reached
Iterations completed: [iteration]
[report path] was rejected.
[recovery]
```

A loop that never reaches `REJECTED` at the cap needs only the first form.

## Caller Must Specify (at the Read call site)

- **`iteration`** — a counter the caller's preamble initialises to `0` before Step 1 and never resets mid-run; position 1 above is its only increment site.
- **`### Cap-pause`** — a heading the caller provides, in the shape `## The Cap-Pause Block` above fixes.
- **`### Stall stop`** — a heading the caller provides, stating both its own stall condition and its own procedure; this fragment routes to it by name and defines neither.
- **Step 2 and Step 5** — the caller's fix step and its report-and-stop step; the Next column above routes to them by number.
- **the message's four values** — `label`, `report path`, `command`, `recovery` — filled in per loop, per verdict, from that loop's own other paused stops.
- **the `Read` call precedes the launch sentence** — the caller's Step 3 reads this fragment before running its own review pass; a launch sentence read first runs the pass twice, once on its own and once again as this fragment's position 2.

**What this contract is checked by.** Four of the six obligations above are asserted by `tests/verify-workflow-safety.sh`: the two headings and the order their procedures run in, the `Step 2` / `Step 5` numbers the Next column names, and that the `Read` call precedes the launch sentence. A fifth — the `iteration` preamble initialisation — is asserted separately, by the same suite's check on each loop's preamble. The message's four values are not asserted as a group: a wrong fill is visible in the block that holds it, and this repo's test-authoring rule extracts no guard for a value that cannot drift silently — the one exception is the article loop's report path, which `tests/verify-config-consistency.sh` checks as a prohibited hardcoded form rather than a required one.

**This file is parsed by two tests.** `tests/verify-workflow-safety.sh` asserts that position 1 of `## The Round` names `iteration` as its increment, that the branch table has exactly one APPROVED row and three `not APPROVED` rows in stall-then-below-cap-then-at-or-above-cap order with each `Next` cell anchored to its own column, that the cap row reads `at or above` rather than `equal to`, that the `Step 5` and `Step 2` names above resolve in every loop that reads this fragment, and that the `### Cap-pause` / `### Stall stop` names match the headings each loop provides. `tests/verify-config-consistency.sh` asserts the `## Caller Must Specify` heading above keeps its mandatory wording — an optional-parameter reword of that heading anywhere under `skills/` fails that suite. Editing the position table, the branch table, the cap value, or the heading wording without re-running both is how this drifts silently.
