---
name: design
description: Create design proposal for implementation
---

# Design Command

Create detailed design proposal based on requirements and research findings.

## Agent

Main conversation (no specialized agent)

## Skills Required

- domains/architecture (architecture patterns)
- domains/quality-attributes (quality considerations)

## Actions

1. Analyze requirements and constraints
2. Propose implementation approach
3. List files to be modified/created
4. Explain technical rationale
5. Document trade-offs and alternatives

## Output

**File:** `planning/<goal>/milestone-XX/design/<feature>-design.md`

**Contains:**
- Proposed approach
- Architecture diagrams (Mermaid)
- Alternative approaches considered
- Design rationale
- File modification list
- Trade-offs analysis

## Key Principle

Design files describe **HOW** to implement (architecture, approach), not **WHAT** to do (that's in status.md).

## Next Step

After design is complete, use `/review-design` to get approval before implementation.
