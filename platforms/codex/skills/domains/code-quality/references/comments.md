# Comment Philosophy

## Core Principle

Write self-documenting code that needs minimal comments.

## Before Adding a Comment

Ask yourself:
1. Can I rename variables/functions to make this clearer?
2. Can I extract this into a well-named function?
3. Can I simplify the logic?
4. Is the comment explaining WHAT (obvious) or WHY (useful)?

## When Comments Are Necessary

### Classes
```cpp
// Manages SRT streaming connections with automatic reconnection
class SrtStreamManager {
    // ...
};
```

### Non-Obvious Methods
```python
def calculate_backoff(attempt: int) -> float:
    # Exponential backoff with jitter to prevent thundering herd
    return min(300, (2 ** attempt) + random.uniform(0, 1))
```

### TODOs
```rust
// TODO(issue-123): Refactor to use async/await when tokio 1.0 stable
fn process_sync() {
    // ...
}
```

### Test Cases
```go
func TestUserLogin(t *testing.T) {
    // Verify that invalid credentials return 401 and preserve session
    // ...
}
```

### Complex Algorithms
```cpp
// Boyer-Moore string search: skip ahead based on bad character rule
// to avoid checking every position
int search(const std::string& haystack, const std::string& needle) {
    // ...
}
```

## What NOT to Comment

### Usage Examples
```python
# BAD: Comment shows usage
class Database:
    # Usage: db = Database("localhost")
    #        db.connect()
    #        db.query("SELECT * FROM users")
    def __init__(self, host: str):
        # ...
```

Tests should document usage instead.

### Complexity Notes
```cpp
// BAD: Comment acknowledges complexity
// This function is complex because it handles multiple edge cases
void processData(Data& data) {
    // 50 lines of complex logic
}
```

Simplify the function instead, or extract helper functions.

### Responsibility Lists
```java
// BAD: Comment lists responsibilities
/**
 * UserService handles:
 * - User authentication
 * - User registration
 * - Password reset
 * - Email verification
 */
public class UserService {
    // ...
}
```

Code structure and method names should make this clear.

### Obvious Information
```python
# BAD: Comment restates the code
# Increment counter by 1
counter += 1

# Get user by ID
user = database.get_user(user_id)
```

## Comment Style by Language

### C++
```cpp
// Single-line comments for brief explanations
/*
 * Multi-line comments for longer descriptions
 * (though prefer breaking into smaller, self-documenting pieces)
 */
```

### Python
```python
# Single-line comments

def function(arg: str) -> int:
    """Docstring for function/class/module.

    Describe parameters, return value, and behavior.
    Follow Google or NumPy style.
    """
    pass
```

### Go
```go
// Single-line comments (no multi-line style)
// Use multiple single-line comments if needed

// Package documentation goes before package declaration
package main
```

### Rust
```rust
// Single-line comments
/// Documentation comments for public APIs (shows in rustdoc)
//! Module-level documentation

/* Multi-line comments less common */
```

## Summary

**Good code reads like prose. Comments are for insights, not translations.**
