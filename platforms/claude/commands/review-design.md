---
name: review-design
description: Review design before implementation using reviewer agent
---

# Design Review Command

**MANDATORY CHECKPOINT:** Review design proposal before any code is written.

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

Every design review file MUST contain exactly one status marker as the **first non-empty line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji, no verb/noun mixing.

This marker is machine-readable and used by the `/implement` gate (`head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`). A review without the canonical marker will cause the compaction gate to skip at `/implement`.

## Actions

1. Load design document from `planning/<goal>/milestone-XX/design/<feature>-design.md`
2. Run the **Consensus Review Protocol** (Steps A–E) against the design document
   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
3. Format consolidated findings as a markdown review report (see Output Format below)
4. **Write the report to `planning/<goal>/milestone-XX/reviews/<feature>-design-review.md`**

5. **Verify the status marker** before declaring the review complete:
   ```bash
   head -20 planning/<goal>/milestone-XX/reviews/<feature>-design-review.md | grep -m 1 '^\*\*Status:\*\*'
   ```
   - If the marker is found with a canonical state (`APPROVED`, `CHANGES REQUESTED`, or `REJECTED`) → proceed.
   - If the marker is missing or malformed → **do not declare the review complete**. Surface an error and either re-invoke the reviewer agent or ask the user to add the marker manually before continuing.

6. After writing, ask the user if they want to `open <path>` the review file
7. Wait for user approval (MANDATORY)
8. Block until approved

## Final Step — Push planning to backup

After the review file is written and the marker verified, push planning state to backup:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment: run `projctl sync push`. On failure, surface the standard warning and continue — do not fail this skill.

## Review Scope

Each of the 3 agents evaluates all 8 quality attributes:
- Supportability: Logging, error messages, debugging strategy
- Extendability: Modularity, abstractions, extension points
- Maintainability: Follows conventions, clarity, complexity
- Testability: Unit test strategy, isolation, edge cases
- Performance: No bottlenecks, resource usage, algorithms
- Safety: Error handling, resource management, thread safety
- Security: Input validation, no vulnerabilities, secrets handling
- Observability: Logging, metrics, tracing strategy

## Output Format

Produce a markdown report using the reviewer agent's standard template:

```markdown
# Design Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature name>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description...
- **C2** [attribute] Description...

### High
- **H1** [attribute] Description...
- **H2** [attribute] Description...

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Recommendation
<rationale and required actions if not approved; reference findings by ID e.g. "Fix C1, H2 before proceeding">
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity (C1, C2, H1, H2, M1, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → proceed to implementation
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → return to Phase 2

## Critical Rule

**NO code implementation without approval.**
