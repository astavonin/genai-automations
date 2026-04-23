# Code Review Checklist

Use this checklist when evaluating implementation quality across the eight quality attributes.

## 1. Implementation Correctness

- [ ] The implementation matches the intended behavior or approved design.
- [ ] Core invariants are enforced in code, not only implied by comments.
- [ ] Error paths and edge cases are handled explicitly.
- [ ] New failure modes are either prevented or surfaced clearly.

## 2. Quality Attributes

### Supportability
- [ ] Errors are actionable and not silently discarded.
- [ ] Debugging a failure does not require guessing hidden state.
- [ ] Operationally relevant paths emit enough signal to diagnose problems.

### Extendability
- [ ] The code is modular enough to support the next likely change.
- [ ] Abstractions are justified and not prematurely generic.
- [ ] New behavior can be added without rewriting unrelated parts.

### Maintainability
- [ ] Naming is clear and consistent.
- [ ] Complexity is proportional to the problem.
- [ ] Comments explain intent where needed, not obvious mechanics.
- [ ] The code follows established project patterns.

### Testability
- [ ] Important logic is testable in isolation.
- [ ] Unit tests cover happy paths, edge cases, and failure paths.
- [ ] Integration tests exist for real component boundaries when relevant.
- [ ] Tests are deterministic and appropriately separated by scope.

### Performance
- [ ] Algorithms and data structures are appropriate for expected scale.
- [ ] Hot paths avoid unnecessary work, allocations, or I/O.
- [ ] Resource usage is reasonable for the problem.

### Safety
- [ ] Resource cleanup is correct (`RAII`, `defer`, context managers, etc.).
- [ ] Concurrency or shared-state risks are handled when applicable.
- [ ] The implementation avoids undefined behavior or equivalent unsafe states.

### Security
- [ ] Inputs are validated at trust boundaries.
- [ ] Secrets are not hardcoded or leaked through logs.
- [ ] The change does not introduce obvious injection or privilege-escalation risks.

### Observability
- [ ] Important behavior and failures can be observed through logs, metrics, traces, or equivalent signals.
- [ ] Operational diagnosis is possible without invasive debugging.

## 3. Verification

- [ ] Project formatting has been applied.
- [ ] Relevant lint or static-analysis tooling has been considered.
- [ ] Tests that should exist are present or their absence is called out explicitly.

## Severity Guidance

| Level | Meaning |
|---|---|
| `critical` | Unsafe, insecure, or fundamentally incorrect behavior. |
| `major` | Significant gap in correctness, testability, safety, or maintainability. |
| `minor` | Localized issue that should be tightened before relying on the change heavily. |
| `suggestion` | Optional improvement that is not required for correctness. |
