---
name: testing
description: Testing strategies and best practices covering unit and integration tests. Use when writing tests or reviewing test coverage to apply AAA structure, proper isolation, and appropriate test granularity.
---

# Testing Skill

## Unit Tests

- Use the AAA structure: Arrange, Act, Assert
- Name tests after behavior and expected outcome
- Keep tests independent and order-insensitive
- Cover edge cases and error paths, not just happy paths
- Cover all public API behavior that can affect correctness

## Hard Requirements For Unit Tests

- Keep unit tests fast
- Avoid network calls, real databases, external processes, and arbitrary sleeps
- If a test needs real components, treat it as an integration test and separate it accordingly

## Failure Scenario Coverage

Every public function or method that can fail must have at least one test per distinct failure mode:
- invalid or out-of-range input
- dependency or resource errors, such as network failure, unavailable database, or missing file
- boundary violations, such as empty collection, max size exceeded, or zero divisor
- concurrent or ordering violations, where applicable

A happy-path-only test suite is a correctness gap regardless of line coverage percentage.

## Assertion Correctness

- Assert concrete expected values or observable behavior, not just non-null values or existence.
- Error-path assertions must check the specific error type, code, or message, not just that some error occurred.
- Test names must match what the assertions actually verify.
- Each assertion should fail if the implementation returns a wrong-but-non-null value, accepts invalid input, or returns the wrong error.

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

- Use integration tests when real components interact
- Prefer deterministic setup and readiness checks
- Keep state isolated and clean up after the test
- Treat flaky tests as bugs to fix, not tests to ignore

## Coverage Guidance

- Aim for high coverage on critical business logic
- Prefer meaningful behavioral coverage over superficial line coverage
- Ensure public API behavior is covered where practical

## Summary

1. Write unit tests for isolated logic
2. Add integration tests at real component boundaries
3. Cover public API paths, failure modes, and behavioral invariants
4. Keep assertions concrete, falsifiable, and aligned with test names
5. Keep tests readable, deterministic, and focused on behavior
