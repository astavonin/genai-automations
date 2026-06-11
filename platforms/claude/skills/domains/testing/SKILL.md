---
name: testing
description: Testing strategies and best practices covering unit, integration, and e2e tests. Use when writing tests or reviewing test coverage to apply AAA pattern, proper test naming, mocking, and appropriate test granularity.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: domains
  tags: [testing, unit-tests, tdd, coverage]
---

# Testing Skill

Testing strategies, patterns, and best practices for comprehensive test coverage.

## Testing Pyramid

```
       /\
      /  \    E2E Tests (Few)
     /____\
    /      \  Integration Tests (Some)
   /________\
  /          \ Unit Tests (Many)
 /____________\
```

## Unit Testing Best Practices

### AAA Pattern
```
Arrange - Set up test data and conditions
Act     - Execute the code under test
Assert  - Verify the expected outcome
```

### Test Naming
Name tests after **behavior and expected outcome**, not the function name:
- Good: `test_user_login_with_invalid_credentials_returns_401`
- Bad: `test_login`

### Test Independence
- No shared state between tests
- Tests can run in any order
- Use setup/teardown for common initialization

### Speed and Isolation (hard requirements)
- Each unit test must complete in **≤ 3 seconds**
- No network calls, no disk I/O, no external processes, no real databases
- No `sleep` or time-based waits
- If a test needs any of the above, it is an integration test — move it and tag it accordingly

### Edge Cases
Always test: empty input, null/None values, max/min values, invalid input, error conditions.

### Failure Scenario Coverage (mandatory)
Every public function or method that can fail MUST have at least one test per distinct failure mode:
- Invalid or out-of-range input
- Dependency or resource errors (network failure, DB unavailable, file not found)
- Boundary violations (empty collection, max size exceeded, zero divisor)
- Concurrent or ordering violations (if applicable)
- **Input guard completeness:** for every allowlist/blocklist/range check, enumerate all distinct categories of unsafe input and write a negative test per category — not just one representative value. A guard that blocks `"` but not `\` or `;` is incomplete even if a negative test exists.

A happy-path-only test suite is a correctness gap regardless of line coverage percentage.

### Assertion Correctness (mandatory)
- Assert **concrete expected values**, not just non-null or existence (`assert result is not None` is not a correctness check)
- Error-path assertions MUST check the specific error type, code, or message — not just that "some error occurred"
- Test name MUST match what the assertions actually verify — a mismatch is a correctness bug, not a style issue
- Ask: would this test fail if the implementation returned a wrong-but-non-null value or a different error?

### Behavioral Correctness (mandatory)
Write explicit tests for every scenario where incorrect runtime behavior is possible:
- **Wrong output or data corruption** — e.g., response body from a redirect written into a download file
- **Silent acceptance of invalid input** — e.g., treating an HTTP 3xx or 4xx as success
- **Liveness violations** — e.g., a complete-file condition that retries infinitely instead of returning early
- **Security or correctness invariant bypasses** — e.g., TLS version silently downgraded

These are not optional edge cases — they are required test cases. Each must:
- Have a name that identifies the behavioral invariant being asserted (e.g., `maps_redirect_to_permanent_redirect_with_zero_bytes`)
- Set up the exact precondition that would trigger the incorrect behavior
- Assert the correct outcome explicitly (status code, byte count, returned value)

## Integration Testing

Use integration tests when two or more real components interact (DB, HTTP, broker). Use unit tests for isolated logic.

**Requirements:**
- Real deps (testcontainers, test DB) — no mocking at the infrastructure boundary
- No shared mutable state between tests; clean up in teardown
- Flaky tests are bugs — fix or delete immediately, never `t.Skip()` or `@pytest.mark.skip`
- Use deterministic readiness waits (poll + timeout), never bare `sleep`

**Tagging (mandatory — must run separately from unit tests):**
- Go: `//go:build integration` in `*_integration_test.go` files
- Python: `@pytest.mark.integration` on each test function
- Rust: place in `tests/` directory; run with `cargo test --test <name>`
- C++: separate CMake target or `Integration` test suite name prefix

**Isolation strategies (pick one per dependency type):**
- DB: transaction rollback in teardown, or testcontainers per suite
- HTTP: in-process test server (`httptest.NewServer`, `TestClient`) — no real external calls
- Other: in-process fake (e.g. miniredis) when container overhead is too high

## Coverage Goals

| Scope | Target |
|-------|--------|
| Critical business logic (unit) | 80%+ line + branch |
| Public API surface (unit) | 100% |
| Integration paths (happy + error) | All primary flows + at least one error path |

Focus on meaningful coverage: a covered line is not a tested behavior.

## Summary

1. Write unit tests first; add integration tests at component boundaries
2. Focus on behavior, not implementation
3. Keep tests simple and readable
4. Test edge cases and error conditions
5. Unit tests: fast, isolated, no I/O; integration tests: real deps, tagged separately
6. Maintain tests as you maintain code; delete flaky tests immediately

## Test Doubles

| Type | Use when |
|------|----------|
| **Fake** | Infrastructure replacement (in-memory DB, fake cache) — preferred for infra |
| **Stub** | Control indirect inputs; return canned values |
| **Spy** | Verify side effects without replacing real behavior |
| **Mock** | Verify exact interaction protocol — use only when the call contract itself is under test |

Prefer fakes over mocks for infrastructure dependencies. Over-mocking hides real integration failures.

## References (examples and lookup — not rules)

- `references/test-organization.md` — language-specific file layout
- `references/mocking.md` — framework usage examples (Go, Python, C++)
- `references/advanced-testing.md` — TDD, performance, anti-patterns
- `references/integration-testing.md` — testcontainers quickstart, directory structure
