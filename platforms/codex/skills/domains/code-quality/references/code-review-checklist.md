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
- [ ] TODO comments are actionable and include enough context, such as an issue reference or concrete follow-up.
- [ ] Test comments are used only when the scenario would otherwise be hard to follow.
- [ ] Stale comments are removed or updated with the code change.
- [ ] Comments, docstrings, and test names do not reference review findings, gap numbers, fix rounds, or review history.
- [ ] No commented-out code is introduced or left behind.

## 3. Linter Suppressions

- [ ] Each suppression includes a concrete reason.
- [ ] The suppression scope is as narrow as possible.
- [ ] The code was improved instead of suppressed when the warning identified a real issue.
- [ ] Suppressions do not mask correctness, safety, or maintainability problems.

## 4. Formatting And Project Conventions

- [ ] The project's formatter has been applied to modified files.
- [ ] The code follows established repository conventions where they exist.
- [ ] New patterns are consistent with nearby code unless there is a clear reason to diverge.

## 5. C++ Error Handling, When Applicable

- [ ] Recoverable I/O, network, and external API failures use explicit return channels instead of exceptions.
- [ ] Code uses project-native `std::expected`, `Result`, `StatusOr`, or status-enum patterns instead of inventing one-off result wrappers.
- [ ] Programmatic control flow branches on typed errors, status enums, or error codes, not parsed diagnostic strings.
- [ ] Error-indicating `bool` returns, status/result enums, and factory/query returns that callers must act on are marked `[[nodiscard]]`.
- [ ] Intentional discards of `[[nodiscard]]` results are explicit and justified.
- [ ] Exceptions are caught and converted at destructors, C callbacks, C ABI boundaries, thread entry points, and cleanup paths.
- [ ] Required output parameters use references; pointers are reserved for truly optional outputs where `nullptr` is meaningful.
- [ ] Shared error-detail strings are propagated by reference through chained calls instead of allocating per call in hot paths.
- [ ] System-call failures capture `errno` immediately and log enough context to diagnose the failure.

## 6. Tests

- [ ] Tests cover the intended behavior change.
- [ ] Tests cover all public API paths affected by the change.
- [ ] Tests include each distinct failure mode for public functions or methods that can fail.
- [ ] Tests cover important error paths or edge cases when relevant.
- [ ] Assertions check concrete values or observable behavior, not only non-null values, existence, or call counts.
- [ ] Error-path assertions check the specific error type, code, or message.
- [ ] Test names match the scenario and outcome that the assertions actually verify.
- [ ] Unit tests are fast and isolated: no network calls, disk I/O, real databases, external processes, or arbitrary sleeps.
- [ ] Async or readiness tests use bounded polling, events, fake clocks, or health checks instead of bare `sleep`.
- [ ] Integration tests that use real components are tagged to run separately from unit tests.
- [ ] Integration tests do not call production or external service URLs.
- [ ] Flaky tests are fixed or removed; they are not skipped or ignored.
- [ ] Infrastructure dependencies use fakes or local/containerized real services instead of brittle internal mocks where practical.
- [ ] Tests remain readable and focused on behavior.
- [ ] Test setup avoids unnecessary complexity.

## 7. Review Output Expectations

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
