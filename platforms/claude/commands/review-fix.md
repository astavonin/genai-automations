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

Run the **Consensus Review Protocol** (Steps 0, A–H) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Pre-read context** before launching agents:
- **Interface files not in the diff:** for each changed `.cc`/`.cpp`/`.c` file, also read its `.h`/`.hpp` if not in the diff
- **Full design doc** if one exists — pass the entire file

**Step 0 (do first, before any agents):** Write `planning/reviews/<fix-description>-fix-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** the fix diff range established in Step 1
- **Output File:** `planning/reviews/<fix-description>-codex-fix-review.md`
- **Requirements:** what the fix was supposed to solve (from Step 2)
- **Evidence:** run the project's build and test commands; capture exit codes + last 40 lines of output and paste here
- **Review Focus:** correctness, completeness, regressions, root cause, tests

> **🚫 HARD GATE — do not send this message until BOTH conditions are met:**
> 1. All Agent calls (3 reviewers) are present in this message.
> 2. The `codex-flow` Bash call (`run_in_background: true`) is present in this message.
>
> **No justification overrides this gate.** If `codex-flow` cannot launch, do not send the agent calls — surface the blocker first.

**Step A (single message):** Launch simultaneously:
- 3 × reviewer (opus) Agent calls with:
  - The fix diff (scoped per Step 1)
  - The problem statement (from Step 2)
  - Interface files and design doc (pre-read above)
  - The review checklist
  - Instruction: **review the fix only** — do not flag pre-existing issues outside the diff
- `codex-flow` Bash call with `run_in_background: true`:
  ```bash
  codex-flow review planning/reviews/<fix-description>-fix-review-request.md
  ```

Focus areas for a fix review:
- **Correctness:** Does the fix actually solve the stated problem?
- **Completeness:** Are all affected paths/cases covered?
- **Regressions:** Could the fix break existing behaviour?
- **Root cause:** Does it address the root cause or only a symptom?
- **Safety / Security:** No new vulnerabilities introduced
- **Tests:** Is the fix covered by a test?

Aggregate per protocol Steps B–H. Note: Step F (test-coverage agent) is optional for fix reviews — include it when the fix touches test files or adds new tests.

### Step 4: Output

**Write the report to `planning/reviews/<fix-description>-fix-review.md`** (use a short slug for `<fix-description>`, e.g. `tier-timeout-fix`).
After writing, ask the user if they want to `open <path>` the review file.

```markdown
# Fix Review

**Fix:** <one-line description of what was fixed>
**Problem:** <what was broken>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject
**Codex:** ✓ ran | ✗ not run — <reason if skipped>

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...
  **Required test:** <what input triggers the bug and what the test asserts> *(only for behavioral bugs)*

### High
- **H1** [attribute] Description...
  **Required test:** <description> *(only for behavioral bugs)*

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Codex-Only Findings

Findings raised by Codex that did not reach 2/3 Claude consensus. Include even if 0 — write "None."

- **X1** [severity] Description...

## Reverified Findings

Single-agent Claude findings and Codex-only findings that survived Step G reverification (≥1 of 2 verifiers confirmed). Include even if 0 — write "None."

- **V1** [severity] ✓ Reverified — Description...

## Recommendation
<rationale; if not approved, what must change — reference findings by ID e.g. "Fix C1, H1 before proceeding">
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity. IDs are stable within a review session.

## Behavioral Bug Test Requirement

Any finding that identifies **incorrect runtime behavior** MUST include a `**Required test:**` line as part of the finding body. This applies regardless of severity.

**Incorrect runtime behavior** means the code:
- Produces wrong output or corrupts data
- Silently accepts input that should be rejected
- Gets stuck or loops incorrectly
- Bypasses a stated security or correctness invariant

This does NOT apply to quality findings (naming, observability, performance, maintainability) that have no wrong-output consequence.

The `**Required test:**` line must describe the minimal test that would fail before the fix and pass after:
- What precondition / input triggers the bug
- What outcome the test asserts

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → fix is good to go
- ⚠️ **Request Changes:** One or more High findings → revise the fix
- ❌ **Reject:** One or more Critical findings → fix is incorrect or introduces new problems
