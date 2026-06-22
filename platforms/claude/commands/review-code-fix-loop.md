---
name: review-code-fix-loop
description: Run initial code review, fix all findings, re-review until APPROVED, then run one final clean review and print the report
---

# Code Review Fix Loop Command

Run the full code review cycle autonomously: initial review → fix all findings → re-review → repeat until APPROVED → final clean review + report.

## Agents

- **reviewer** (opus) — all review passes (full 3+1 consensus protocol each time)
- **coder** (sonnet) — fix all findings between review passes; never use `isolation: "worktree"`

## Prerequisite

Implementation exists on the branch. No existing review file required — this command produces `code-review.md` itself.

## Actions

### Step 1: Initial review

Declare: "I'll use reviewer agent for the initial code review..."

Follow `/review-code` exactly — full 3+1 consensus + Codex, all mandatory passes (Test Quality, Cross-Site Consistency, Dead Symbol). Writes `code-review.md`.

If result is `APPROVED`: proceed directly to Step 5 (report and stop). Step 1's output is already a clean report — no final re-review needed.

If result is `CHANGES REQUESTED` or `REJECTED`: proceed to Step 2.

### Step 2: Fix all findings

Declare: "I'll use coder agent to fix all findings from the current review..."

**Which findings to fix:** Fix all Critical and High findings. For Medium and Low: fix those with a concrete `fix:` field in the review; skip advisory-only Medium/Low findings (no actionable code change possible). Do not ask the user — apply this rule consistently.

Invoke **coder agent** with:
- The full list of findings selected above
- The full design doc if one exists (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`)
- The code review checklist (`~/.claude/skills/domains/quality-attributes/references/review-checklist.md`) so the agent understands the standards being applied
- Instruction: fix all listed findings in one pass; do not leave any selected finding unaddressed without flagging it explicitly

**After the coder agent completes, verify the build:**
```
Read the project's build command from its CLAUDE.md, README.md, or dev.sh
Run the build command
```
If the build fails: invoke coder agent again scoped to the build failure before proceeding to Step 3. Do not re-review with a broken build.

### Step 3: Re-review

Declare: "I'll use reviewer agent for re-review pass N..." (track N starting from 1)

Follow `/review-code` exactly — same full protocol as Step 1. **Pass the current `code-review.md` as prior review context** so agents can verify prior findings are addressed. Overwrites `code-review.md`.

If result is `APPROVED`: proceed to Step 4.

If result is `CHANGES REQUESTED` or `REJECTED`: return to Step 2 with the new finding list.

**Stall detection:** If the same root-cause area (same file + same component, not same finding ID — IDs reset each pass) appears in 3 consecutive re-review passes without being resolved, surface a blocker to the user and pause: "Finding in [area] has not been resolved after 3 passes — manual intervention needed." Do not continue the loop automatically.

### Step 4: Final clean review

Declare: "I'll use reviewer agent for the final clean review..."

Run the full `/review-code` protocol one final time. **Critical:** instruct all reviewer agents and Codex to treat this as a fresh review — do NOT read or reference the existing `code-review.md` from prior passes. This pass must be conducted as if no prior review exists, producing a report uncontaminated by prior-finding language.

Overwrites `code-review.md` with the final clean report.

If this final clean review returns `CHANGES REQUESTED` or `REJECTED`: report the findings to the user and stop. Do not automatically re-enter the fix loop — output:
```
Final clean review: CHANGES REQUESTED — N finding(s).
The fix loop converged but the clean pass found new issues. Review the findings and invoke /review-code-fix-loop again to address them.
```

### Step 5: Report and stop

Verify the status marker is present in `code-review.md`:
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
Iterations: N  (0 if approved on first pass)
Final report: planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md
```

Stop. Do not proceed to `/verify` automatically — the user drives the next step.
