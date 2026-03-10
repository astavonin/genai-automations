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

### Edge Cases
Always test: empty input, null/None values, max/min values, invalid input, error conditions.

## Coverage Goals
- 80%+ for critical business logic
- 100% for public APIs
- Focus on meaningful coverage, not hitting a number

## Summary

1. Write tests first or alongside code
2. Focus on behavior, not implementation
3. Keep tests simple and readable
4. Test edge cases and error conditions
5. Use appropriate granularity (unit → integration → e2e)
6. Maintain tests as you maintain code

## References

See `references/` directory for:
- Language-specific test organization examples (`test-organization.md`)
- Mocking guide — when and how to mock (`mocking.md`)
- Advanced patterns — TDD, integration, performance, anti-patterns (`advanced-testing.md`)
