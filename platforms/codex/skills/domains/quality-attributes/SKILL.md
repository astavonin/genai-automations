---
name: quality-attributes
description: Eight quality attributes for guiding software design and implementation and for evaluating reviews: supportability, extendability, maintainability, testability, performance, safety, security, and observability. Use during development as well as during design reviews and code reviews.
---

# Quality Attributes Skill

Use these quality attributes to guide architecture/design proposals, code implementations, and reviews.

For coding tasks, this skill is not optional review material. It is an always-on development constraint that should shape implementation choices, error handling, testing strategy, operational signals, and security boundaries while writing code.

## The 8 Quality Attributes

### 1. Supportability
Can operators and developers diagnose, debug, and fix problems?

### 2. Extendability
Can the design or code evolve without unnecessary rework?

### 3. Maintainability
Is the design or code understandable, structured, and consistent?

### 4. Testability
Can behavior and invariants be validated with clear, reliable tests?

### 5. Performance
Are performance implications, hot paths, or scale boundaries handled appropriately where relevant?

### 6. Safety
Are failure modes, invariants, resource handling, and edge cases handled explicitly?

### 7. Security
Does the design or implementation avoid unsafe assumptions and define trust boundaries clearly?

### 8. Observability
Can behavior and failures be observed in development and production?

## Design Review Checks

For workflow and command designs, also verify:
- required inputs are explicit
- outputs are explicit
- writable paths are explicit
- hard invariants name an enforcement mechanism
- validation and failure behavior are specified

## Development Checks

During implementation, ensure:
- the code structure supports likely future changes without unnecessary abstraction
- important behavior can be validated with unit and integration tests where appropriate
- failure handling, cleanup, and invariants are explicit in code
- trust boundaries, input validation, and secret handling are addressed
- operationally relevant behavior emits enough signal to debug and monitor
- obvious performance and resource regressions are avoided

## Code Review Checks

For code reviews, also verify:
- the implementation follows the intended design and project conventions
- tests exist for important behavior and edge cases
- error handling, cleanup, and invariants are explicit in code
- input validation, secrets handling, and injection risks are addressed
- logging, metrics, or debug signals exist where operationally relevant
- obvious performance or resource regressions are not introduced

## Reference Checklists

Use:
- `references/design-review-checklist.md` for design and architecture reviews
- `references/code-review-checklist.md` for implementation and code reviews
