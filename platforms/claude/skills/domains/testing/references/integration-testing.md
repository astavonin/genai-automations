# Integration Testing Reference

## Unit vs Integration — Decision Rule

| Use unit tests when | Use integration tests when |
|---------------------|---------------------------|
| Single component, no I/O | Two or more real components interact |
| Pure logic / data transformation | Real DB, broker, or HTTP dependency involved |
| Fast feedback loop needed | Contract between layers must be verified |

## Isolation Strategies

| Strategy | When to use |
|----------|-------------|
| DB transaction rollback | SQL DBs; rollback in teardown — fast, no truncation |
| Testcontainers | Real DB dialect matters; spin up per test suite |
| In-process fake (SQLite, miniredis) | When container overhead is too high |
| httptest / WireMock server | External HTTP APIs; never call real production URLs |

Never share mutable container/server state across tests.

## Language-Specific Tagging (run separately from unit tests)

**Go** — build tag in `_integration_test.go` files:
```go
//go:build integration
```
Run with: `go test -tags=integration ./...`

**Python** — pytest marker:
```python
@pytest.mark.integration
def test_user_creation_persists_to_db(): ...
```
Run with: `pytest -m integration`

**Rust** — separate `tests/` directory (integration tests):
```
src/
tests/
  integration_test.rs   # cargo test --test integration_test
```

**C++** — separate CMake target or test suite name prefix:
```cmake
add_executable(integration_tests ...)
```

## Testcontainers Quickstart

**Go:**
```go
func TestMain(m *testing.M) {
    pg, _ := postgres.Run(context.Background(), "postgres:16",
        postgres.WithDatabase("testdb"),
        testcontainers.WithWaitStrategy(wait.ForListeningPort("5432/tcp")),
    )
    defer pg.Terminate(context.Background())
    dsn, _ = pg.ConnectionString(context.Background(), "sslmode=disable")
    os.Exit(m.Run())
}
```

**Python:**
```python
@pytest.fixture(scope="session")
def pg_url():
    with PostgresContainer("postgres:16") as pg:
        yield pg.get_connection_url()
```

## Flaky Test Policy

- Flaky test = bug. Fix or delete immediately. Never `t.Skip()` or `@pytest.mark.skip`.
- Use deterministic readiness: `wait.ForListeningPort`, healthcheck endpoint, or bounded poll.
- Never use bare `sleep` as a wait strategy.
