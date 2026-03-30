---
name: go
description: Go coding standards based on Effective Go and Go Code Review Comments. Use when writing, reviewing, or modifying Go code to apply idiomatic patterns, error handling, and concurrency best practices.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: languages
  tags: [go, golang, programming]
---

# Go Programming Skill

## Standards

**Follow Effective Go:**
- https://go.dev/doc/effective_go

**Follow Go Code Review Comments:**
- https://github.com/golang/go/wiki/CodeReviewComments

**Follow Official Go Style Guide:**
- https://google.github.io/styleguide/go/

## Key Principles

### Code Style
- Use gofmt for formatting (enforced)
- MixedCaps for exported names
- Short variable names in small scopes
- Package names: lowercase, no underscores
- Interface names: single-method interfaces end in -er

### Error Handling
- Always check errors, never ignore
- Return errors, don't panic
- Wrap errors with context
- Use `defer` for cleanup

### Concurrency
- Share memory by communicating (use channels)
- Don't communicate by sharing memory
- Use `sync` package when needed
- Be mindful of goroutine lifetimes

### Code Organization
- One package per directory
- Keep packages focused and cohesive
- Minimize dependencies
- Use internal/ for private packages

### Testing
- Use table-driven tests
- Test files named `*_test.go`
- Use `testing` package
- Benchmark critical code

### Performance
- Avoid premature optimization
- Use profiling tools (pprof)
- Be aware of allocations
- Pool frequently allocated objects if needed

## Formatting

Run gofmt (or goimports) automatically.

## Static Analysis

Run go vet, golint, and staticcheck for code quality.

## References

- Effective Go: https://go.dev/doc/effective_go
- Go Code Review Comments: https://github.com/golang/go/wiki/CodeReviewComments
- Go Style Guide: https://google.github.io/styleguide/go/
