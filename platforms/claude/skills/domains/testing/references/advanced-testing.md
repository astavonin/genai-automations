# Advanced Testing Patterns

## Coverage

### What to Measure
- **Line coverage** — lines executed during tests
- **Branch coverage** — conditional branches taken
- **Path coverage** — execution paths through code

### Goals
- 80%+ for critical business logic
- 100% for public APIs
- Focus on meaningful coverage, not hitting a number

### Coverage Tools

| Language | Tools |
|----------|-------|
| C++ | gcov, lcov |
| Python | coverage.py (`pytest --cov`) |
| Go | `go test -cover` |
| Rust | cargo-tarpaulin |

## Test-Driven Development (TDD)

### Red-Green-Refactor Cycle
1. **Red** — write a failing test that describes the desired behavior
2. **Green** — write the minimal code to make the test pass
3. **Refactor** — improve the code while keeping tests green

### Benefits
- Design emerges from usage (tests are the first consumer of your API)
- High coverage by default
- Confidence in refactoring

## Integration Testing

### Database Testing
- Use a test database or in-memory database (SQLite, H2)
- Use fixtures or factories for test data
- Wrap tests in transactions and roll back after each test
- Never share state between integration tests

### API Testing
- Test the full request/response cycle
- Verify status codes, headers, and body
- Test error conditions and edge cases
- Use a test server or mock server (no real external calls)

## Performance Testing

### Benchmarking
- Measure performance-critical code paths
- Compare before/after for any optimization
- Track regressions in CI (fail if benchmark regresses >10%)

### Tools

| Language | Tools |
|----------|-------|
| C++ | Google Benchmark |
| Python | pytest-benchmark |
| Go | `go test -bench` |
| Rust | criterion |

## Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Tests depend on execution order | Brittle, hard to debug | Each test sets up its own state |
| Testing implementation details | Tests break on refactor | Test behavior and outcomes |
| No clear assertions | Test always passes or is meaningless | One assertion per behavior |
| Duplicating production logic | Tests don't catch bugs | Test outcomes, not implementation |
| Overly brittle mocks | Tests break on any change | Mock at boundaries, not internals |
