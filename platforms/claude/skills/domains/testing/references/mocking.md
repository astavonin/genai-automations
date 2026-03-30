# Mocking and Stubbing Guide

## Test Double Taxonomy

| Type | Returns | Verifies calls? | Use when |
|------|---------|-----------------|----------|
| **Stub** | Canned values | No | Control indirect inputs |
| **Fake** | Real logic (simplified) | No | Fast in-proc replacement (e.g. in-memory DB) |
| **Spy** | Real behavior + records | After the fact | Verify side effects without breaking behavior |
| **Mock** | Canned values | Yes (expectations upfront) | Verify exact interaction contract |

Prefer **fakes** for infrastructure (DB, cache); prefer **mocks** only when the interaction protocol itself is what's under test.

## When to Mock

Mock dependencies that are:
- **External** — databases, APIs, file systems, network calls
- **Slow** — anything that makes tests take seconds instead of milliseconds
- **Non-deterministic** — time, random number generators, external state
- **Hard to reproduce** — error conditions, race conditions, network failures

## When NOT to Mock

Do not mock:
- Simple value objects or data structures
- Pure functions with no side effects
- Internal implementation details (test behavior, not wiring)
- Things that are cheap and deterministic to use directly

## Mock Frameworks by Language

| Language | Frameworks |
|----------|-----------|
| C++ | Google Mock, FakeIt |
| Python | `unittest.mock`, `pytest-mock` |
| Go | `testify/mock`, `gomock` |
| Rust | `mockall`, `mockito` |

## Examples

### Python (unittest.mock)

```python
from unittest.mock import patch, MagicMock

def test_send_email_on_registration():
    with patch("myapp.email.send") as mock_send:
        register_user("alice@example.com")
        mock_send.assert_called_once_with(
            to="alice@example.com",
            subject="Welcome"
        )
```

### Go (testify/mock)

```go
type MockEmailService struct {
    mock.Mock
}

func (m *MockEmailService) Send(to, subject string) error {
    args := m.Called(to, subject)
    return args.Error(0)
}

func TestRegistrationSendsEmail(t *testing.T) {
    mockEmail := new(MockEmailService)
    mockEmail.On("Send", "alice@example.com", "Welcome").Return(nil)

    svc := NewUserService(mockEmail)
    svc.Register("alice@example.com")

    mockEmail.AssertExpectations(t)
}
```

### Rust (mockall)

```rust
#[cfg(test)]
use mockall::{automock, predicate::*};

#[automock]
trait EmailService {
    fn send(&self, to: &str, subject: &str) -> Result<(), Error>;
}

#[test]
fn registration_sends_email() {
    let mut mock = MockEmailService::new();
    mock.expect_send()
        .with(eq("alice@example.com"), eq("Welcome"))
        .times(1)
        .returning(|_, _| Ok(()));

    let svc = UserService::new(mock);
    svc.register("alice@example.com").unwrap();
}
```
