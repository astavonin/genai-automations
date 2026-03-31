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
