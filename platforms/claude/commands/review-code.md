---
name: review-code
description: Review code after implementation using reviewer agent
---

# Code Review Command

**MANDATORY CHECKPOINT:** Review implementation after code is written.

## Agent

**reviewer** (opus model)

## Skills Required

- domains/quality-attributes (8 quality attributes)

## Actions

1. Invoke reviewer agent with code review checklist
2. Evaluate implementation against 8 quality attributes
3. Block until approved

## Review Checklist

Use: `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`

**Evaluate:**
- **Supportability:** Logging, error messages, debugging
- **Extendability:** Modularity, abstractions, future-proofing
- **Maintainability:** Code clarity, naming, complexity
- **Testability:** Unit tests, test coverage, edge cases
- **Performance:** No bottlenecks, efficient algorithms
- **Safety:** Error handling, resource management, thread safety
- **Security:** Input validation, no vulnerabilities
- **Observability:** Logging, metrics, tracing

**Also Check:**
- Design adherence (matches approved design)
- Code quality and standards
- Test coverage and quality
- Static analysis compliance

## Assessment

- ✅ **Approve:** Proceed to verification
- ⚠️ **Request Changes:** Fix issues and return for re-review
- ❌ **Reject:** Fundamental problems, redesign needed

## Usage

```
"I'll use the reviewer agent to perform code review. Please use the Code Review
Checklist from ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
to evaluate the implementation."
```

## Next Step

After approval, use `/verify` to run tests and static analysis.
