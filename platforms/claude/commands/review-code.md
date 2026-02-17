---
name: review-code
description: Review code after implementation using reviewer agent
---

# Code Review Command

**MANDATORY CHECKPOINT:** Review implementation after code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Skills Required

- `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- `~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

## Actions

1. Run the **Consensus Review Protocol** (Steps A–D) against the implementation
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
- ...

### High
- ...

### Medium / Low
- ...

## Recommendation
<rationale and required actions if not approved>
```

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → proceed to `/verify`
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → redesign needed

## Next Step

After approval, use `/verify` to run tests and static analysis.
