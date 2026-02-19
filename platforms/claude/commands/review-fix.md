---
name: review-fix
description: Review a targeted fix (CI failure, local issue) — not the full MR
---

# Fix Review Command

Review a specific fix in isolation — a CI failure resolution, a bug fix, or a correction
to a previous implementation. Scope is the fix only, not surrounding unchanged code.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Skills Required

- `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- `~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

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

```bash
codex review "DO NOT make any changes. Only print your findings. This is a targeted fix review — only review the changes in the diff, not pre-existing code. Check: does the fix correctly solve the problem? Are there regressions? Missing cases? Rate each finding Critical, High, Medium, or Low."
```

Aggregate once all four have returned per the consensus protocol.

### Step 4: Output

```markdown
# Fix Review

**Fix:** <one-line description of what was fixed>
**Problem:** <what was broken>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- ...

### High
- ...

### Medium / Low
- ...

## Recommendation
<rationale; if not approved, what must change>
```

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → fix is good to go
- ⚠️ **Request Changes:** One or more High findings → revise the fix
- ❌ **Reject:** One or more Critical findings → fix is incorrect or introduces new problems
