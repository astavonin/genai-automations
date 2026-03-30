# Test Organization by Language

## Directory Structure (unit vs integration)

```
project/
├── src/
├── tests/              # Python / Rust integration tests
│   └── integration/
├── *_test.go           # Go: unit tests alongside source
├── *_integration_test.go  # Go: tagged with //go:build integration
└── test/
    ├── unit/           # C++: unit test files
    └── integration/    # C++: separate CMake target
```

Integration test files must be tagged so they run separately. See `integration-testing.md`.



Language-specific conventions for structuring and naming test files and suites.

## C++

```cpp
// test_user.cpp
#include "user.h"
#include <gtest/gtest.h>

TEST(UserTest, LoginSucceedsWithValidCredentials) {
    User user("alice", "secret");
    EXPECT_TRUE(user.login("secret"));
}

TEST(UserTest, LoginFailsWithInvalidPassword) {
    User user("alice", "secret");
    EXPECT_FALSE(user.login("wrong_password"));
}

TEST(UserTest, LoginPreservesSessionOnFailure) {
    User user("alice", "secret");
    user.login("wrong_password");
    EXPECT_TRUE(user.hasActiveSession());
}
```

**One assertion per test** — each test focuses on a single behavior.

## Python

```python
# test_user.py
import pytest

class TestUser:
    def test_login_succeeds_with_valid_credentials(self):
        user = User("alice", "secret")
        assert user.login("secret") is True

    def test_login_fails_with_invalid_password(self):
        user = User("alice", "secret")
        assert user.login("wrong_password") is False

    @pytest.fixture
    def authenticated_user(self):
        user = User("alice", "secret")
        user.login("secret")
        return user
```

## Go

```go
// user_test.go
package user

import "testing"

func TestLoginSucceedsWithValidCredentials(t *testing.T) {
    u := NewUser("alice", "secret")
    if !u.Login("secret") {
        t.Error("expected login to succeed with valid credentials")
    }
}

// Table-driven tests for multiple cases
func TestLoginValidation(t *testing.T) {
    tests := []struct {
        name     string
        password string
        wantOk   bool
    }{
        {"valid credentials", "secret", true},
        {"wrong password", "wrong", false},
        {"empty password", "", false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            u := NewUser("alice", "secret")
            got := u.Login(tt.password)
            if got != tt.wantOk {
                t.Errorf("Login(%q) = %v, want %v", tt.password, got, tt.wantOk)
            }
        })
    }
}
```

## Rust

```rust
// user.rs
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn login_succeeds_with_valid_credentials() {
        let user = User::new("alice", "secret");
        assert!(user.login("secret").is_ok());
    }

    #[test]
    fn login_fails_with_invalid_password() {
        let user = User::new("alice", "secret");
        assert!(user.login("wrong").is_err());
    }
}
```
