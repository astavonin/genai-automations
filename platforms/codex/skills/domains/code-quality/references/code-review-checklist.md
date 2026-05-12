# Code Quality Review Checklist

Use this checklist for the narrowed Codex scope: code changes, tests, and review feedback focused on readability, comments, suppressions, and formatting.

## 1. Readability And Structure

- [ ] The code is understandable without excessive comments.
- [ ] Names communicate intent clearly.
- [ ] Functions and methods stay focused on one responsibility.
- [ ] Functions and methods stay at or below 80 lines where practical.
- [ ] No new or modified function or method exceeds 100 lines.
- [ ] Complex control flow or indirection is justified.
- [ ] New abstractions reduce complexity instead of hiding it.

## 2. Comments

- [ ] All main interfaces, types, and data structures have short explanatory comments that clarify role, invariants, or constraints.
- [ ] Comments explain intent, trade-offs, or non-obvious behavior.
- [ ] Comments do not restate the code line-by-line.
- [ ] Comments are not added only to satisfy a comment quota.
- [ ] TODO comments include enough context to be actionable.
- [ ] Test comments are used only when the scenario would otherwise be hard to follow.
- [ ] Stale comments are removed or updated with the code change.

## 3. Linter Suppressions

- [ ] Each suppression includes a concrete reason.
- [ ] The suppression scope is as narrow as possible.
- [ ] The code was improved instead of suppressed when the warning identified a real issue.
- [ ] Suppressions do not mask correctness, safety, or maintainability problems.

## 4. Formatting And Project Conventions

- [ ] The project's formatter has been applied to modified files.
- [ ] The code follows established repository conventions where they exist.
- [ ] New patterns are consistent with nearby code unless there is a clear reason to diverge.

## 5. Tests

- [ ] Tests cover the intended behavior change.
- [ ] Tests cover all public API paths affected by the change.
- [ ] Tests include each distinct failure mode for public functions or methods that can fail.
- [ ] Tests cover important error paths or edge cases when relevant.
- [ ] Assertions check concrete values or observable behavior, not only non-null values, existence, or call counts.
- [ ] Error-path assertions check the specific error type, code, or message.
- [ ] Test names match the scenario and outcome that the assertions actually verify.
- [ ] Tests remain readable and focused on behavior.
- [ ] Test setup avoids unnecessary complexity.

## 6. Review Output Expectations

- [ ] Findings focus on real risks, regressions, or maintainability issues.
- [ ] Any finding that identifies incorrect runtime behavior includes a `Required test:` line describing the input or precondition that triggers the bug and the outcome the test asserts.
- [ ] Style-only feedback is raised only when it affects readability or project consistency.
- [ ] Suggested fixes are concrete and proportional to the issue.

Behavioral runtime bugs include wrong output, data corruption, silent invalid-input acceptance, liveness failures, and security or correctness invariant bypasses. Quality-only findings without a wrong-output consequence do not need a `Required test:` line.

## Severity Guidance

| Level | Meaning |
|---|---|
| `critical` | The change introduces a correctness, safety, or severe maintainability problem. |
| `major` | A substantial readability, test, or suppression issue needs correction, including missing failure-scenario tests for security, data integrity, or resource-management behavior. |
| `minor` | The change is workable but should be tightened for clarity or consistency. |
| `suggestion` | Optional improvement that is not required for correctness. |
