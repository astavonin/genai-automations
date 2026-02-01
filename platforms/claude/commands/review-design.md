---
name: review-design
description: Review design before implementation using reviewer agent
---

# Design Review Command

**MANDATORY CHECKPOINT:** Review design proposal before any code is written.

## Agent

**reviewer** (opus model)

## Skills Required

- domains/quality-attributes (8 quality attributes)

## Actions

1. Load design document from `planning/<goal>/milestone-XX/design/<feature>-design.md`
2. Invoke reviewer agent with design review checklist
3. Wait for user approval (MANDATORY)
4. Block until approved

## Review Checklist

Use: `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`

**Evaluate:**
- Supportability: Logging, error messages, debugging strategy
- Extendability: Modularity, abstractions, extension points
- Maintainability: Follows conventions, clarity, complexity
- Testability: Unit test strategy, isolation, edge cases
- Performance: No bottlenecks, resource usage, algorithms
- Safety: Error handling, resource management, thread safety
- Security: Input validation, no vulnerabilities, secrets handling
- Observability: Logging, metrics, tracing strategy

## Assessment

- ✅ **Approve:** Proceed to implementation
- ⚠️ **Request Changes:** Revise design and re-review
- ❌ **Reject:** Fundamental problems, return to Phase 2

## Usage

```
"I'll use the reviewer agent to review this design. Please use the Design Review
Checklist from ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
to evaluate the approach."
```

## Critical Rule

**NO code implementation without approval.**
