---
name: testing
description: Testing strategies and best practices covering unit and integration tests. Use when writing tests or reviewing test coverage to apply AAA structure, behavior-focused names, proper isolation, concrete assertions, and appropriate test granularity.
---

# Testing Skill

Testing should prove behavior, not just execute lines. A test is useful only when it would fail for a plausible wrong implementation.

## Unit Tests

- Use the AAA structure: Arrange, Act, Assert
- Name tests after behavior and expected outcome
- Keep tests independent and order-insensitive
- Cover edge cases and error paths, not just happy paths
- Cover all public API behavior that can affect correctness
- Prefer table-driven tests where they make edge cases clearer, especially in Go

## Hard Requirements For Unit Tests

- Keep unit tests fast
- Each unit test should complete in 3 seconds or less
- Avoid network calls, disk I/O, real databases, external processes, and arbitrary sleeps
- Do not use `sleep` or time-based waits to observe async behavior; use bounded polling, explicit events, fake clocks, or readiness signals
- If a test needs real components, treat it as an integration test and separate it accordingly

## Failure Scenario Coverage

Every public function or method that can fail must have at least one test per distinct failure mode:
- invalid or out-of-range input
- dependency or resource errors, such as network failure, unavailable database, or missing file
- boundary violations, such as empty collection, max size exceeded, or zero divisor
- concurrent or ordering violations, where applicable
- input guard completeness: for every allowlist, blocklist, or range check, enumerate each distinct unsafe input category and write a negative test for each category, not just one representative value

A happy-path-only test suite is a correctness gap regardless of line coverage percentage.

## Assertion Correctness

- Assert concrete expected values or observable behavior, not just non-null values or existence.
- Error-path assertions must check the specific error type, code, or message, not just that some error occurred.
- Test names must match what the assertions actually verify.
- Each assertion should fail if the implementation returns a wrong-but-non-null value, accepts invalid input, or returns the wrong error.
- Do not rely on call counts without verifying the arguments, outputs, state change, or externally visible behavior that matters.

## Behavioral Correctness

Write explicit tests for every scenario where incorrect runtime behavior is possible:
- wrong output or data corruption
- silent acceptance of invalid input
- liveness violations, such as retry loops that should terminate
- security or correctness invariant bypasses

Each behavioral-correctness test must:
- name the invariant or behavior being asserted
- set up the exact precondition that would trigger the bug
- assert the correct outcome explicitly, such as status code, byte count, returned value, error type, or state transition

## Integration Tests

Use integration tests when two or more real components interact, such as a database, HTTP server, broker, filesystem boundary, or process boundary.

Requirements:
- Prefer real dependencies at infrastructure boundaries, such as testcontainers, test databases, in-process HTTP servers, or project-native fakes.
- Do not call real production or external service URLs.
- Keep state isolated and clean up after the test.
- Use deterministic readiness checks with polling plus timeout, health checks, or explicit signals; never bare `sleep`.
- Treat flaky tests as bugs to fix, not tests to ignore or skip.
- Tag integration tests so they run separately from unit tests.

Tagging examples:
- Go: `//go:build integration` in `*_integration_test.go`
- Python: `@pytest.mark.integration`
- C++: separate CMake target or an `Integration` suite prefix

Isolation strategies:
- SQL database: transaction rollback in teardown, isolated schema, or testcontainer per suite
- HTTP: in-process test server or WireMock-style local server
- Cache/broker: in-process fake when behavior is sufficient, otherwise a containerized real service

## Test Doubles

| Type | Use when |
|---|---|
| Fake | Replacing infrastructure with a simplified in-process implementation, such as an in-memory database or cache |
| Stub | Returning canned values to control indirect inputs |
| Spy | Recording side effects while preserving simple behavior |
| Mock | Verifying an exact interaction protocol that is itself the contract under test |

Prefer fakes over mocks for infrastructure dependencies. Over-mocking hides real integration failures and makes refactors noisy.

## Coverage Guidance

| Scope | Target |
|---|---|
| Critical business logic | 80%+ line and branch coverage where practical |
| Public API surface | 100% of behaviorally meaningful paths |
| Integration boundaries | Primary flows plus at least one error path per boundary |

- Prefer meaningful behavioral coverage over superficial line coverage
- Ensure public API behavior is covered where practical

## Summary

1. Write unit tests for isolated logic
2. Add integration tests at real component boundaries
3. Cover public API paths, failure modes, and behavioral invariants
4. Keep assertions concrete, falsifiable, and aligned with test names
5. Keep unit tests fast and isolated; keep integration tests tagged and deterministic
6. Keep tests readable and focused on behavior
