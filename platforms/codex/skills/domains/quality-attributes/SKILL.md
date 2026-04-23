---
name: quality-attributes
description: Quality attributes for evaluating architecture, design, and workflow proposals.
---

# Quality Attributes Skill

Use these quality attributes to evaluate architecture and design documents.

## The 8 Quality Attributes

### 1. Supportability
Can operators and developers diagnose problems from the design?

### 2. Extendability
Can the design evolve without unnecessary rework?

### 3. Maintainability
Is the design understandable, structured, and consistent?

### 4. Testability
Does the design define how behavior and invariants can be validated?
When a coverage target can be extracted from the repository, design, or review context, treat `>= 80%` as the expected minimum unless the project states a stricter rule.

### 5. Performance
Are performance implications, hot paths, or scale boundaries acknowledged where relevant?

### 6. Safety
Are failure modes, invariants, and edge cases handled explicitly?

### 7. Security
Does the design avoid unsafe assumptions and define trust boundaries clearly?

### 8. Observability
Does the design explain how behavior and failures can be observed?

## Design-Doc-Specific Checks

For workflow and command designs, also verify:
- required inputs are explicit
- outputs are explicit
- writable paths are explicit
- hard invariants name an enforcement mechanism
- validation and failure behavior are specified

## Reference Checklist

Use `references/review-checklist.md` for the narrowed design and architecture review checklist.
`references/design-review-checklist.md` remains as a compatibility alias.
