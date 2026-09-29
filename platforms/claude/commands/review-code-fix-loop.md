---
name: review-code-fix-loop
description: Run initial code review, fix all findings, re-review until APPROVED or the iteration cap, then print the report
---

# Code Review Fix Loop Command

Run the full code review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED or the iteration cap → report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **coder** (sonnet) — fix all findings between review passes; never use `isolation: "worktree"`

## Prerequisite

Implementation exists on the branch. No existing review file required — this command produces `code-review.md` itself.

## Protocol Deviations

When running any review pass in this command (Steps 1 and 3), deviate from the `/review-code` protocol as follows — these steps are suppressed because the fix-loop manages them centrally:

- **Skip** the planning-update step (Step 5 of this command handles it once at the end)
- **Skip** the push-planning step (Step 5 handles it)
- **Skip** the "ask user to open file" step (this command runs autonomously)
- **Skip** the "Phase gate (MANDATORY)" step (the loop continues without user input — this is Step 7 in `/review-code` that blocks until the user invokes `/verify`; the fix-loop's autonomy is authorized by the Exception clause in CLAUDE.md Critical Rules)

## Actions

**Preamble:** Initialize `iteration = 0` before Step 0. This counter is set exactly once at command start and is never reset mid-run.

### Step 0: Resolve the issue folder

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Resolve `<issue-folder>` once and echo it. Every later step reuses this exact string — Step 1's review pre-reads the ledger from it, and Step 2 passes it to the coder. Re-deriving it per step is what produces silent ledger misses.

### Step 1: Initial review

Follow `/review-code` with the deviations listed above. Writes `code-review.md`.

**Three exclusive branches. Evaluate in order and take the first that matches** — the finding counts decide, not the `**Status:**` string alone, because a Medium-only review and a High-bearing review both write `CHANGES REQUESTED`:

1. **`APPROVED`** → proceed directly to Step 5. Skip Steps 2 and 3.
2. **`CHANGES REQUESTED` with zero Critical and zero High** — the Medium-only path → **Step 2 with `exit_to = Step 5`**, then Step 5. Skip Step 3. This path counts as no loop pass.
3. **`CHANGES REQUESTED` with one or more Critical or High, or `REJECTED`** → **Step 2 with `exit_to = Step 3`**, the full cycle.

`exit_to` is Step 2's only parameter and it is mandatory: Step 2's own terminal lines name it rather than a literal step number, so branch 2 cannot be overridden by the step it delegates to.

**On branch 2, the orchestrator writes the approval itself.** **Perform this write only after Step 2 completes and its own gate passes — the build check Step 2 runs, and `/verify-docs` where Step 2 invoked it — immediately before entering Step 5**; never before Step 2 runs. An early write publishes `APPROVED` planning state and satisfies `/implement`'s precondition 2 even when Step 2 then blocks, turning a loud stop into a silently approved issue. Overwrite three fields in `code-review.md` together — `**Status:**` to `APPROVED`, `**Assessment:**` to `✅ Approve`, and `## Recommendation` to name the closed findings — then add a `## Mediums Fixed Without Re-Review` heading listing every finding the pass closed. Writing `**Status:**` alone leaves a report whose header approves and whose body still demands the fixes that were just made.

**What branch 2 gives up, stated so it is a choice and not an accident:** no review pass grades those fixes. It rests on Step 2's own gate — the build check — passing at the end of Step 2. Take branch 3 instead when Step 2's report says a fix **touched a symbol, heading, or config value read at more than one site**, or **added a branch, flag, or section rather than removing text** — Step 2's agent instructions require that report, so this is a decision on evidence, not a guess. A fix pass has been the dominant source of the next round's findings in four of the nine rounds this repo has logged.

Step 2's "fix all Critical, High, and Medium" governs a pass that *runs*. On branch 2 the pass runs for the Mediums alone.

### Step 2: Fix all findings

**Which findings to fix:** Fix all Critical, High, and Medium findings. For Low: fix those with a concrete `fix:` field in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **coder agent** with:
- The full list of findings selected above
- The full design doc if one exists (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`)
- The code review checklist (`~/.claude/skills/domains/quality-attributes/references/review-checklist.md`)
- **The resolved `<issue-folder>` path** (resolved in Step 0 above) — the coder writes the ledger only when given this path; per `~/.claude/skills/workflows/regression-test/SKILL.md` → The Ledger → Who writes it, this loop appends an entry for any defect that reproduces mid-loop, so omitting the path silently drops that entry
- Instruction: fix all listed findings in one pass; flag explicitly any finding that cannot be addressed; apply these test requirements:
  - **Report per finding, so the caller can choose its exit:** whether the fix touched a symbol, heading, or config value read at **more than one site**, and whether it **added** a branch, flag, or section rather than removing text. Branch 2's decision to skip the re-review reads this and nothing else; without it the caller has no evidence and defaults to skipping.
  - **Critical and High findings, and any `Required test:` line (mandatory, discharge applies):** every fix for a Critical or High finding includes a test change, unless a clause in `### Out of Scope` of `~/.claude/skills/workflows/regression-test/SKILL.md` names the case or the user has approved a waiver. The same discharge retires the `**Required test:**` obligation named in this bullet's own heading: a finding's named test is not owed when the fix lands under a clause or an approved waiver, and neither obligation outranks the other. State the discharge in your fix response, against the finding ID it answers — the clause by name, or the waiver the user approved. Where one pass fixes several findings, attribute each discharge to its finding; an unattributed claim discharges nothing. A fix by deletion leaving nothing assertable is one of those cases, and a `**Required test:**` line that turns out vacuous is category 6.
  - **Do not self-serve a waiver.** If you judge that a category holds, including category 6, flag the finding instead of fixing it: this command surfaces it and the user decides outside the loop. Every recorded waiver carries `## Waiver`'s full requirements — the category, the user's approval under the approval test there, and a compensating control.
  - **The discharge governs the test, not the ledger.** A defect you reproduced by running the code is an observed failure under item 3 and owes its entry whatever shape its fix takes; a finding never reproduced owes none and lives in the fix response alone.

`tests/verify-config-consistency.sh` checks that this step carries the discharge wording above and no longer carries the trigger-6 bullet or the old absolute test mandate.

**If the coder agent flags any finding as unaddressable:** surface it to the user immediately and wait for a decision before proceeding to `exit_to` — do not silently continue into the next review pass.

**If the fix pass touched any file under `planning/` or `docs/`, run `/verify-docs`, passing the `<issue-folder>` resolved in Step 0.** Code-review fixes reach design docs and READMEs — a changed contract updates `design.md`, a ledger entry lands in `observed-failures.md` — and nothing else in this loop checks citation form or cross-reference integrity there. Skip this when the pass touched only code and tests.

Passing the folder is not optional: `/verify-docs` cannot discover planning docs without it (`git diff` never lists them, since the global gitignore keeps `planning/` untracked), and both of its scans — citation form and prose metrics — resolve it directly. Invoked without it they check nothing and the command reports `Clean`.

- If blockers are reported: invoke architecture-research-planner scoped to those blockers only (design docs and `docs/` are never edited with Write/Edit directly), then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles. If blockers persist, surface a blocker: "Doc consistency blockers remain after 2 fix cycles — manual intervention needed." Pause and wait for user.
- If warnings only: continue to the build check below.

**After the coder agent completes, verify the build.** Read the project's build command from its `CLAUDE.md`, `README.md`, or `dev.sh`, then run it.

- If the build passes: proceed to `exit_to` — Step 3 on branch 3, Step 5 on branch 2. Never a literal step number: a hardcoded Step 3 here overrides the caller's branch and spends the round the Medium-only path exists to save.
- If the build fails: invoke coder agent again scoped to the build failure only. Cap at 3 consecutive build-fix attempts; if the build still fails after 3 attempts, surface a blocker: "Build failed after 3 fix attempts — manual intervention needed." Pause and wait for user.

### Step 3: Re-review

```
Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md
```

Follow `/review-code` with the deviations listed above. **Pass the current `code-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `code-review.md`.

Pass the coder's fix response alongside the prior `code-review.md` — it records, per finding ID, the clause or approved waiver claimed as a discharge. Where the re-review accepts a discharge for a Critical or High finding, record the accepted clause or waiver on that finding's resolution line in `code-review.md`.

**This file is parsed by two tests.** `tests/verify-workflow-safety.sh` asserts this Step 3 carries the fragment's `Read` pointer above, ahead of a review-pass launch sentence that begins with the word `Follow`, with no destination sentence or increment of its own, that neither this file's frontmatter nor its body still promises the deleted review pass that used to follow Step 3, that every `Step <N>` reference in this file resolves to a heading here, and that the `### Cap-pause` and `### Stall stop` headings below exist and run their procedures in the order the fragment names. `tests/verify-config-consistency.sh` asserts the `Read` pointer above resolves to a non-empty file. Editing the step numbering, the headings, the pointer, or the launch sentence's opening word without re-running both is how this drifts silently.

### Stall stop

If the same root-cause area (same file + same component — not finding ID, which resets each pass) appears unresolved in 3 consecutive passes, surface a blocker: "Finding area [file/component] unresolved after 3 passes — manual intervention needed." Pause and wait for user.

### Cap-pause

Run the review-planning-update fragment (which includes push):
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`, `issue_folder = <issue-folder>`)

Report to the user and stop. If the re-review that reached the cap returned `CHANGES REQUESTED`:
```
Code review loop paused — iteration cap reached
Iterations completed: [iteration]
N finding(s) open in planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md.
Fix them manually, or re-invoke /review-code-fix-loop to continue.
```

If it returned `REJECTED`:
```
Code review loop paused — iteration cap reached
Iterations completed: [iteration]
planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md was rejected.
Redesign is required — resolve via /design, then re-invoke /review-code-fix-loop.
```

### Step 5: Report and stop

Verify the status marker — read it and **branch on the value**, do not print it unchecked:
```
Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
```
(`review_file = planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md`)

**If the marker is not `APPROVED`, stop and surface the mismatch** instead of running the fragment or printing the completion line. Branch 2 is the first route on which the orchestrator writes this marker itself, so it is the first route on which the marker and the report can disagree — a failed or skipped write would otherwise set the phase to `changes requested 🔄` while the output still read `complete: APPROVED`.

Run the review-planning-update fragment:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`, `issue_folder = <issue-folder>`)

Push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Output:
```
Code review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 when no re-review ran)
Mediums fixed without re-review: [finding IDs, or "none"]
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md
```

The Mediums line is the disclosure the unreviewed-fix risk rests on — it reaches the person deciding whether to proceed, which the in-file heading alone does not.

Stop. Do not proceed to `/verify` automatically.
