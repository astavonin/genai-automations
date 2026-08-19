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

If result is `APPROVED`: proceed directly to Step 5. Step 1's output is already a clean report — skip Steps 2 and 3.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2.

### Step 2: Fix all findings

**Which findings to fix:** Fix all Critical, High, and Medium findings. For Low: fix those with a concrete `fix:` field in the review; skip advisory-only entries. Apply this rule without asking the user.

Invoke **coder agent** with:
- The full list of findings selected above
- The full design doc if one exists (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`)
- The code review checklist (`~/.claude/skills/domains/quality-attributes/references/review-checklist.md`)
- **The resolved `<issue-folder>` path** (resolved in Step 0 above) — the coder writes the ledger only when given this path, and the Step 3 re-review flags a missing ledger entry as High, so omitting it deadlocks the loop
- Instruction: fix all listed findings in one pass; flag explicitly any finding that cannot be addressed; apply these test requirements:
  - **Critical and High findings (mandatory):** every fix for a Critical or High finding must include new or modified tests. Use unit tests for isolated logic and integration tests when the finding involves component interaction, external state, or runtime composition. No Critical or High finding is considered fixed without a corresponding test change.
  - **Any severity with `Required test:` line:** implementing the described test is mandatory as part of the fix.
  - **Findings confirmed to reproduce (observed-failure trigger 6):** for any finding describing incorrect runtime behaviour that you confirm reproduces, append a resolved entry to `<issue-folder>/observed-failures.md` per `~/.claude/skills/workflows/regression-test/SKILL.md`. The next review pass checks for it and rates its absence High.

**If the coder agent flags any finding as unaddressable:** surface it to the user immediately and wait for a decision before proceeding to Step 3 — do not silently continue into the next review pass.

**If the fix pass touched any file under `planning/` or `docs/`, run `/verify-docs`, passing the `<issue-folder>` resolved in Step 0.** Code-review fixes reach design docs and READMEs — a changed contract updates `design.md`, a ledger entry lands in `observed-failures.md` — and nothing else in this loop checks citation form or cross-reference integrity there. Skip this when the pass touched only code and tests.

Passing the folder is not optional: `/verify-docs` cannot discover planning docs without it (`git diff` never lists them, since the global gitignore keeps `planning/` untracked), and both of its scans — citation form and prose metrics — resolve it directly. Invoked without it they check nothing and the command reports `Clean`.

- If blockers are reported: invoke architecture-research-planner scoped to those blockers only (design docs and `docs/` are never edited with Write/Edit directly), then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles. If blockers persist, surface a blocker: "Doc consistency blockers remain after 2 fix cycles — manual intervention needed." Pause and wait for user.
- If warnings only: continue to the build check below.

**After the coder agent completes, verify the build.** Read the project's build command from its `CLAUDE.md`, `README.md`, or `dev.sh`, then run it.

- If the build passes: proceed to Step 3.
- If the build fails: invoke coder agent again scoped to the build failure only. Cap at 3 consecutive build-fix attempts; if the build still fails after 3 attempts, surface a blocker: "Build failed after 3 fix attempts — manual intervention needed." Pause and wait for user.

### Step 3: Re-review

```
Read ~/.claude/skills/workflows/fix-loop-round/SKILL.md
```

Follow `/review-code` with the deviations listed above. **Pass the current `code-review.md` as prior review context** — this is intentional so agents can verify prior findings are addressed. Overwrites `code-review.md`.

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

Verify the status marker:
```bash
head -20 planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md | grep -m 1 '^\*\*Status:\*\*'
```

Run the review-planning-update fragment:
```
Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
```
(`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`)

Push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Output:
```
Code review loop complete: APPROVED
Iterations: [iteration]  (fix+re-review cycles; 0 if approved on first pass)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md
```

Stop. Do not proceed to `/verify` automatically.
