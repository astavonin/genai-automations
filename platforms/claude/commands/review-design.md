---
name: review-design
description: Review design before implementation using reviewer agent
---

# Design Review Command

**MANDATORY CHECKPOINT:** Review design proposal before any code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Skills Required

- `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- `~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

## Actions

1. Load design document from `planning/<goal>/milestone-XX/design/<feature>-design.md`
2. Run the **Consensus Review Protocol** (Steps A–E) against the design document
   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
3. Format consolidated findings as a markdown review report (see Output Format below)
4. Wait for user approval (MANDATORY)
5. Block until approved

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

**Subject:** <feature name>
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

- ✅ **Approve:** Zero Critical and zero High findings → proceed to implementation
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → return to Phase 2

## Critical Rule

**NO code implementation without approval.**
