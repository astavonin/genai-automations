---
name: architecture-review
description: Architecture and design review workflow focused on quality, trade-offs, consistency, and enforceable constraints.
---

# Architecture Review Workflow Skill

Review architecture proposals, workflow designs, and technical plans with evidence-based analysis.

## Required Inputs

- design doc or proposal
- current system constraints and context
- known risks, trade-offs, or alternatives

## Workflow

1. Clarify the problem, scope, and decision being proposed.
2. Review the design against architecture and quality-attribute guidance.
3. Trace every required field, path, flag, and hard invariant across command entry, contract, runtime behavior, validation, examples, and enforcement.
4. Report findings, open questions, and recommendation.

## References

Use:
- `~/.codex/skills/domains/architecture/SKILL.md`
- `~/.codex/skills/domains/quality-attributes/SKILL.md`
- `~/.codex/skills/domains/quality-attributes/references/review-checklist.md`
- `references/architecture-review-template.md`

## Guardrails

- Review only; do not implement changes.
- Prefer evidence over speculation.
- Treat missing field propagation across sections as a first-class design finding, not a minor editorial issue.
- Treat missing enforcement for hard constraints as a design finding.
