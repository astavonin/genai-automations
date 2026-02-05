---
name: architecture-review
description: Architecture review workflow focused on design quality, trade-offs, and evolution.
---

# Architecture Review Workflow Skill

Review architecture proposals or existing system designs with evidence-based analysis.

## When To Use
- Reviewing architecture/design documents
- Evaluating system boundaries or integration changes
- Assessing architectural refactors

## Required Inputs
- Design doc or proposal
- Current system constraints and context
- Known risks, trade-offs, or alternatives

## Workflow

1. **Intake & Scope**
   - Clarify the problem statement and success criteria
   - Identify affected components and integration points

2. **Design Review**
   - Use `~/.codex/skills/domains/architecture/SKILL.md`
   - Apply quality-attributes checklist where relevant

3. **Trade-offs & Risks**
   - Identify cost/benefit and operational impacts
   - Highlight gaps, unknowns, and assumptions

4. **Output**
   - Provide structured findings and recommendations

## Output Template

Use: `references/architecture-review-template.md`

## Guardrails
- Review only; do not implement changes
- Separate confirmed facts from hypotheses
- Prefer evidence over speculation
