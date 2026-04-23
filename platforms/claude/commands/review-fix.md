---
name: review-fix
description: Review a targeted fix (CI failure, local issue) — not the full MR
---

# Fix Review Command

Review a specific fix in isolation — a CI failure resolution, a bug fix, or a correction
to a previous implementation. Scope is the fix only, not surrounding unchanged code.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

Read review skills before starting:
```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

## Actions

### Step 1: Establish Fix Scope

Identify exactly what changed. Use the narrowest scope that covers the fix:

```bash
git diff HEAD          # uncommitted fix
git diff HEAD~1        # last commit only
git diff <base>..<fix> # specific range
```

Show the user the scope (file list + line ranges) and confirm it matches the fix
being reviewed. Do not include unrelated changes.

### Step 2: State the Problem Being Fixed

Before reviewing, explicitly state:
- What was the original problem (CI failure, bug, logic error, etc.)
- What the fix does to address it

This anchors the review — findings irrelevant to the fix are out of scope.

### Step 3: Multi-Agent Consensus Review

Run the **Consensus Review Protocol** (Steps A–E) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Launch simultaneously: Steps A–D (Claude) and Step E (Codex) in parallel.**

Pass to each reviewer agent:
- The fix diff (scoped per Step 1)
- The problem statement (from Step 2)
- The review checklist
- Instruction: **review the fix only** — do not flag pre-existing issues outside the diff

Focus areas for a fix review:
- **Correctness:** Does the fix actually solve the stated problem?
- **Completeness:** Are all affected paths/cases covered?
- **Regressions:** Could the fix break existing behaviour?
- **Root cause:** Does it address the root cause or only a symptom?
- **Safety / Security:** No new vulnerabilities introduced
- **Tests:** Is the fix covered by a test?

**Step E: Codex cross-model verification**

Follow Step E of the consensus protocol exactly. Before calling `codex-flow`, generate
`planning/reviews/<fix-description>-fix-review-request.md` from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** the fix diff range established in Step 1
- **Output File:** `planning/reviews/<fix-description>-codex-fix-review.md`
- **Requirements:** what the fix was supposed to solve (from Step 2)
- **Evidence:** the fix diff
- **Review Focus:** correctness, completeness, regressions, root cause, tests

Then invoke:
```bash
codex-flow review planning/reviews/<fix-description>-fix-review-request.md
```

Aggregate once all four have returned per the consensus protocol.

### Step 4: Output

**Write the report to `planning/reviews/<fix-description>-fix-review.md`** (use a short slug for `<fix-description>`, e.g. `tier-timeout-fix`).
After writing, ask the user if they want to `open <path>` the review file.

```markdown
# Fix Review

**Fix:** <one-line description of what was fixed>
**Problem:** <what was broken>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...

### High
- **H1** [attribute] Description...

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Recommendation
<rationale; if not approved, what must change — reference findings by ID e.g. "Fix C1, H1 before proceeding">
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity. IDs are stable within a review session.

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → fix is good to go
- ⚠️ **Request Changes:** One or more High findings → revise the fix
- ❌ **Reject:** One or more Critical findings → fix is incorrect or introduces new problems
