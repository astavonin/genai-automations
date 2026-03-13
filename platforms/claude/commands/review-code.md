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

## Actions

1. Run the **Consensus Review Protocol** (Steps A–E) against the implementation
   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
2. Format consolidated findings as a markdown review report (see Output Format below)
3. Block until approved

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

**Subject:** <feature / PR title>
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

- ✅ **Approve:** Zero Critical and zero High findings → proceed to `/verify`
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → redesign needed

## Next Step

After approval, use `/verify` to run tests and static analysis.
