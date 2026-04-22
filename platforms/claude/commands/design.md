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

0. Read workflow and domain skills to ensure phase context:
   ```
   Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
   Read ~/.claude/skills/domains/architecture/SKILL.md
   Read ~/.claude/skills/domains/quality-attributes/SKILL.md
   ```

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

**After writing:** Ask the user if they want to `open <path>` the design file.

## Key Principle

Design files describe **HOW** to implement (architecture, approach), not **WHAT** to do (that's in status.md).

## Final Step — Push planning to backup

After writing the design file, push planning state to backup using the shared push fragment:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment: run `projctl sync push`. On failure, surface the standard warning and continue — do not fail this skill.

## Next Step

After design is complete, use `/review-design` to get approval before implementation.
