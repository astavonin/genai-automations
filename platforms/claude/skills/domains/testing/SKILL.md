---
name: testing
description: Testing strategies and best practices
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

### Unit Tests
- **Scope:** Single function/method/class
- **Speed:** Fast (milliseconds)
- **Coverage:** Most of your tests
- **Isolation:** Mock dependencies

### Integration Tests
- **Scope:** Multiple components together
- **Speed:** Moderate (seconds)
- **Coverage:** Critical paths
- **Isolation:** Real dependencies (databases, services)

### End-to-End Tests
- **Scope:** Complete user workflows
- **Speed:** Slow (minutes)
- **Coverage:** Critical user journeys
- **Isolation:** Full system

## Unit Testing Best Practices

### AAA Pattern
```
Arrange - Set up test data and conditions
Act     - Execute the code under test
Assert  - Verify the expected outcome
```

### Test Naming
Be descriptive about what is tested and expected:
```python
# Good
def test_user_login_with_invalid_credentials_returns_401():
    pass

# Bad
def test_login():
    pass
```

### One Assertion Per Test
Focus each test on a single behavior:
```cpp
// Good
TEST(UserTest, LoginFailsWithInvalidPassword) {
    EXPECT_FALSE(user.login("wrong_password"));
}

TEST(UserTest, LoginPreservesSessionOnFailure) {
    user.login("wrong_password");
    EXPECT_TRUE(user.hasActiveSession());
}

// Bad (testing multiple behaviors)
TEST(UserTest, LoginBehavior) {
    EXPECT_FALSE(user.login("wrong_password"));
    EXPECT_TRUE(user.hasActiveSession());
    EXPECT_EQ(user.getLoginAttempts(), 1);
}
```

### Test Independence
Each test should be independent:
- No shared state between tests
- Can run in any order
- Use setup/teardown for common initialization

### Edge Cases
Test boundary conditions:
- Empty input
- Null/None values
- Maximum values
- Minimum values
- Invalid input
- Error conditions

## Test Organization

### Language-Specific Conventions

**C++:**
```cpp
// test_user.cpp
#include "user.h"
#include <gtest/gtest.h>

TEST(UserTest, LoginSucceedsWithValidCredentials) {
    // ...
}
```

**Python:**
```python
# test_user.py
import pytest

class TestUser:
    def test_login_succeeds_with_valid_credentials(self):
        # ...
```

**Go:**
```go
// user_test.go
package user

import "testing"

func TestLoginSucceedsWithValidCredentials(t *testing.T) {
    // ...
}
```

**Rust:**
```rust
// user.rs
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn login_succeeds_with_valid_credentials() {
        // ...
    }
}
```

## Mocking and Stubbing

### When to Mock
- External dependencies (databases, APIs)
- Slow operations
- Non-deterministic behavior (time, random)
- Hard to reproduce conditions (errors)

### When NOT to Mock
- Simple value objects
- Pure functions
- Internal implementation details

### Mock Frameworks
- **C++:** Google Mock, FakeIt
- **Python:** unittest.mock, pytest-mock
- **Go:** testify/mock, gomock
- **Rust:** mockall, mockito

## Test Coverage

### What to Measure
- Line coverage: Lines executed
- Branch coverage: Conditional branches taken
- Path coverage: Execution paths through code

### Coverage Goals
- 80%+ for critical code
- 100% for public APIs
- Focus on meaningful coverage, not just numbers

### Coverage Tools
- **C++:** gcov, lcov
- **Python:** coverage.py
- **Go:** go test -cover
- **Rust:** cargo-tarpaulin

## Test-Driven Development (TDD)

### Red-Green-Refactor Cycle
1. **Red:** Write failing test
2. **Green:** Write minimal code to pass
3. **Refactor:** Improve code while keeping tests green

### Benefits
- Design emerges from tests
- High test coverage by default
- Confidence in refactoring

## Integration Testing

### Database Testing
- Use test database or in-memory database
- Fixtures for test data
- Transactions for isolation
- Clean up after tests

### API Testing
- Test full request/response cycle
- Verify status codes, headers, body
- Test error conditions
- Use test server or mock server

## Performance Testing

### Benchmarking
- Measure performance-critical code
- Compare before/after optimizations
- Track performance regressions

### Tools
- **C++:** Google Benchmark
- **Python:** pytest-benchmark
- **Go:** go test -bench
- **Rust:** criterion

## Testing Anti-Patterns

### Avoid:
- Tests that depend on execution order
- Tests that test implementation details
- Tests that are brittle and break often
- Tests without clear assertions
- Tests that duplicate production code logic

## Summary

1. **Write tests first or alongside code**
2. **Focus on behavior, not implementation**
3. **Keep tests simple and readable**
4. **Test edge cases and error conditions**
5. **Use appropriate test granularity (unit/integration/e2e)**
6. **Maintain tests as you maintain code**

## References

See `references/` directory for detailed testing patterns and examples.
