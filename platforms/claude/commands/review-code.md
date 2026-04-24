---
name: review-code
description: Review code after implementation using reviewer agent
---

# Code Review Command

**MANDATORY CHECKPOINT:** Review implementation after code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

Read review skills before starting:
```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

## Status Marker Convention (§4)

Every code review file MUST contain exactly one status marker as the **first non-empty line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji, no verb/noun mixing.

This marker is machine-readable and used by the `/implement` gate (`head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`). A review without the canonical marker will cause the compaction gate to skip at `/implement`.

## File Overwrite Convention (§7.4)

This skill always writes a **single** file `<feature>-code-review.md`, **overwriting** any prior content. No versioning suffixes (`-v1`, `-v2`). No appending. Each run replaces. Git history in `planning/` preserves prior reviews if needed. The gate always reads the single latest file.

## Actions

1. Run the **Consensus Review Protocol** (Steps A–E) against the implementation
   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
2. Format consolidated findings as a markdown review report (see Output Format below)
3. **Write the report to `planning/<goal>/milestone-XX/reviews/<feature>-code-review.md`** (overwriting any prior version)

4. **Verify the status marker** before declaring the review complete:
   ```bash
   head -20 planning/<goal>/milestone-XX/reviews/<feature>-code-review.md | grep -m 1 '^\*\*Status:\*\*'
   ```
   - If the marker is found with a canonical state (`APPROVED`, `CHANGES REQUESTED`, or `REJECTED`) → proceed.
   - If the marker is missing or malformed → **do not declare the review complete**. Surface an error and either re-invoke the reviewer agent or ask the user to add the marker manually before continuing.

5. After writing, ask the user if they want to `open <path>` the review file
6. Block until approved

## Final Step — Push planning to backup

After the review file is written and the marker verified, push planning state to backup:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment. If the push fails, surface the elevated warning (see §6.3):

```
⚠️  workflow-safety: planning push failed after /review-code
    reason: projctl sync push returned non-zero (backup may be unavailable)
    recovery: run `projctl sync push` manually; also run `projctl sync status`
              before /complete to verify no drift has accumulated across machines
```

Do not fail this skill — return success after surfacing the warning.

## Review Scope

Each of the 3 agents evaluates:
- **Supportability:** Logging, error messages, debugging
- **Extendability:** Modularity, abstractions, future-proofing
- **Maintainability:** Code clarity, naming, complexity
- **Testability:** Unit tests, test coverage, edge cases
- **Performance:** No bottlenecks, efficient algorithms
- **Safety:** Error handling, resource management, thread safety
- **Security:** Input validation, no vulnerabilities
- **Observability:** Logging, metrics, tracing
- **Design adherence:** Matches approved design
- **Standards compliance:** Coding standards and static analysis

## Output Format

Produce a markdown report:

```markdown
# Code Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature / PR title>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...
- **C2** [attribute] Description...

### High
- **H1** [attribute] Description...

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Codex-Only Findings

Findings raised by Codex that did not reach 2/3 Claude consensus. Include even if 0 — write "None."

- **X1** [severity] Description...

## Test-Coverage Findings

Findings from the test-coverage agent not already present in the consensus section.

- **T1** [severity] Description...

## Recommendation
<rationale and required actions if not approved; reference findings by ID e.g. "Fix C1, H2 before proceeding">
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity (C1, C2, H1, H2, M1, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → proceed to `/verify`
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → redesign needed

## Next Step

After approval, use `/verify` to run tests and static analysis.
