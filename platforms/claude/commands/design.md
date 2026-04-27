---
name: design
description: Create design proposal for implementation
---

# Design Command

Create detailed design proposal based on requirements and research findings.

## Agent

**architecture-research-planner (opus)** — all design doc work, including initial creation and applying review fixes, must be delegated to this agent. Never write or edit design files inline with Write/Edit tools in the main conversation.

## Skills Required

- domains/architecture (architecture patterns)
- domains/quality-attributes (quality considerations)

## Actions

0. Declare agent use: "I'll use architecture-research-planner agent to create/update the design document..."
1. Spawn architecture-research-planner with:
   - The research analysis from Phase 1 (if available)
   - The DESIGN-TEMPLATE.md structure
   - The goal, milestone, feature context
   - For post-review fixes: the review report and enumerated findings to address
2. Agent produces the design file following the template (all 9 sections required)

## Output

**File:** `planning/<goal>/milestone-XX/design/<feature>-design.md`

**Structure:** Follow `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md` exactly. All nine sections are required; sections 7 and 8 may be omitted only when there are genuinely no alternatives or open questions, with a one-line note explaining why.

**Contains:**
- Header metadata (goal, milestone + GL/GH ref, feature ref, branch, status, revision)
- Problem statement
- Goals and non-goals
- Implementation context (repo, requirements, constraints, verification command, context files)
- Architecture overview with Mermaid diagram
- Detailed design
- Files changed table
- Trade-offs and alternatives
- Open questions
- Test plan (unit table + integration table + exclusions)

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
