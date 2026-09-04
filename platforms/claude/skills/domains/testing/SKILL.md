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

### Observed Failure Regression Coverage (mandatory)
The section above covers failure modes you **anticipate**. This one covers failures that **actually happened**.

Every observed failure produces two deliverables: the fix, and a test that reproduces the failure. A fix without a covering test is incomplete work — it does not pass `/verify` and is not approvable in `/review-code` or `/review-fix`. The only alternative is a user-approved waiver in one of five narrow categories.

`~/.claude/skills/workflows/regression-test/SKILL.md` is the single source of truth: trigger list, unit-vs-integration selection table, red/green evidence format, the on-disk ledger, review severities, and the waiver schema. Read it when fixing any failure that occurred rather than working from a summary.

Two points that interact with rules elsewhere in this file:
- **Default to integration.** Observed failures are usually composition failures: the units worked, their interaction did not. A unit test that mocks the exact boundary the bug crossed re-encodes the bug's assumption instead of catching it.
- **Flaky tests.** "Delete flaky tests immediately" (below) removes the symptom; it does not discharge this rule. Delete the non-deterministic test, then add a deterministic test of the underlying race or record a category-4 waiver whose compensating control is an invariant assertion.

### Composition Failure Coverage (mandatory when a dependency gains a new failure mode)
When a component you call gains a new failure mode — such as a new null or empty return, error value, exception, rejected async result, or enum variant — the test file owning the *caller* must add a test that:
1. Simulates the dependency returning or raising the new failure through a fake, stub, configured return value, or equivalent project-native test hook
2. Asserts no irreversible caller-side state was committed (persisted configuration, disk state, durable records, or committed phases remain unchanged)
3. Asserts no crash-loop, replay-loop, or error-exit entry point was created

This requirement applies even when the originating function has no direct unit test of its own (e.g. FSM actions invoked indirectly). Startup, resume, replay, and recovery paths count as callers. The component's test file cannot see how the caller handles the failure — that test belongs in the caller's test file.

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

### How many tests is the right number

**The targets above are for production code. Scale them by the change's class**, defined in `~/.claude/skills/domains/architecture/SKILL.md` → Change Class and declared in the design doc header.

Every test is a permanent cost, not a one-time one: it is read on each failure, rewritten on each refactor, and debugged when it goes flaky. That cost is worth paying for a path the code actually takes and for a failure the code is documented to produce. It is not worth paying for a hypothetical path whose setup needs elaborate scaffolding, a fake wrapping another fake, or a production rewrite to make it reachable.

| Class | Test the paths the code takes | Test documented failure modes | Test every conceivable failure mode |
|---|---|---|---|
| `CI` | yes | yes | no |
| `TEST` | yes | yes | no |
| `PRODUCT-NEW` | yes | yes | yes |
| `PRODUCT-SHIPPED` | yes | yes | yes |

A documented failure mode is the floor at every class — what scales is the third column, the modes nobody has documented and nothing has hit. In `CI`, order the work so the failures that would pass silently get covered first; a red pipeline announces itself, so the silent one earns its test soonest. That is a priority, not an exemption — the loud documented failures are still under the floor.

`PRODUCT-SHIPPED` additionally requires one test pinning each compatibility guarantee the design names — the only class where anything outside the repo already depends on the change.

For `CI` and `TEST`, a path you decline to test is **stated as uncovered** in design §6 → Tests Not Written, with what reaching it would cost. Declining is a decision a reviewer can argue with; omitting silently is indistinguishable from an oversight.

## Summary

1. Write unit tests first; add integration tests at component boundaries
2. Focus on behavior, not implementation
3. Keep tests simple and readable
4. Test edge cases and error conditions
5. Unit tests: fast, isolated, no I/O; integration tests: real deps, tagged separately
6. Maintain tests as you maintain code; delete flaky tests immediately — then cover the underlying race per item 7
7. Every failure you actually observed gets a test that reproduces it — usually integration, proven red before the fix

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
