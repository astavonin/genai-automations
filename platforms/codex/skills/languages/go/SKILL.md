---
name: go
description: Go coding standards based on Effective Go and Go Code Review Comments. Use when writing, reviewing, or modifying Go code to apply idiomatic patterns, explicit error handling, and concurrency best practices.
---

# Go Programming Skill

## Standards

Follow:
- Effective Go: https://go.dev/doc/effective_go
- Go Code Review Comments: https://github.com/golang/go/wiki/CodeReviewComments
- Google Go Style Guide: https://google.github.io/styleguide/go/

## Key Principles

### Code Style
- Treat `gofmt` formatting as mandatory
- Use clear package names: lowercase and without underscores
- Keep names concise in small scopes and descriptive at boundaries
- Prefer small, focused interfaces

### Error Handling
- Check errors explicitly
- Return errors instead of panicking for normal failure paths
- Wrap errors with context where helpful
- Use `defer` for cleanup

### Concurrency
- Prefer communicating over shared mutable state
- Use channels and goroutines deliberately
- Be explicit about goroutine lifetime and cancellation
- Use `context.Context` for cancellation and request scope when applicable

### Code Organization
- Keep packages cohesive
- Use `internal/` for non-public packages when the project structure supports it
- Prefer composition over inheritance-style abstractions

### Testing and Performance
- Prefer table-driven tests
- Use benchmarks for hot paths only when needed
- Measure before optimizing

## Workflow

- Format with `gofmt` or `goimports`
- Run configured analysis such as `go vet`, `staticcheck`, or `golangci-lint`
- Use `testing` and `code-quality` skills alongside this skill when writing or reviewing code

## References

- Effective Go: https://go.dev/doc/effective_go
- Go Code Review Comments: https://github.com/golang/go/wiki/CodeReviewComments
- Google Go Style Guide: https://google.github.io/styleguide/go/
