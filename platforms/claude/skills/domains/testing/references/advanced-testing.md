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

See `integration-testing.md` for: isolation strategies, testcontainers quickstart, language-specific build tags/markers, and flaky test policy.

**Step comments:** Integration tests require numbered step comments describing the logical flow. See `~/.claude/skills/domains/code-quality/references/comments.md` → **Integration Test Cases**.

**Coverage:** All primary flows + at least one error/failure path per component boundary.

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
