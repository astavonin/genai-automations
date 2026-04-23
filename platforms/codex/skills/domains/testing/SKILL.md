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

## Hard Requirements For Unit Tests

- Keep unit tests fast
- Avoid network calls, real databases, external processes, and arbitrary sleeps
- If a test needs real components, treat it as an integration test and separate it accordingly

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
3. Keep tests readable, deterministic, and focused on behavior
