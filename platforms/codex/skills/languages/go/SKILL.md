---
name: go
description: Go implementation and review guidance for idiomatic, maintainable, concurrent, and supportable code. Use when writing, modifying, debugging, or reviewing Go packages, exported APIs, goroutines, modules, dependencies, and tests.
---

# Go Programming Skill

Treat this file as the Go-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, concurrency, observability, dependencies, I/O, compatibility, and test coverage.

## Language And Module Contract

- Inspect `go.mod`, `go.sum`, `go.work`, build tags, supported Go version, package layout, lint configuration, and project-native commands before editing.
- Treat `gofmt` formatting as mandatory and use `goimports` when the project uses it.
- Keep package names short, lowercase, and free of underscores; avoid stutter between package and exported names.
- Keep packages cohesive and use `internal/` for implementation packages that must not become public contracts.
- Avoid `init` side effects and mutable package globals. Make initialization, dependencies, and lifecycle explicit.

## APIs, Types, And Ownership

- Accept interfaces at the consumer boundary and return concrete types unless callers require abstraction.
- Keep interfaces small and behavior-focused. When only tests need substitution and no production contract requires an interface, prefer function-type injection or a minimal in-process fake; define a consumer-owned interface when it makes a genuine boundary clearer.
- Prefer useful zero values and constructors only when validation, required dependencies, or invariants demand them.
- Keep pointer-versus-value receiver choice consistent for a type. Use pointer receivers for mutation, identity, synchronization, or expensive copies.
- Never copy a value containing a mutex, atomic, condition variable, or other non-copyable synchronization state.
- Document ownership when retaining caller-provided slices, maps, buffers, functions, or pointers beyond the call.
- Distinguish nil and empty slices, maps, pointers, and interfaces when serialization or API behavior exposes the difference.
- Do not return a typed nil pointer as a non-nil interface value.
- Use typed options or configuration structs instead of long boolean or positional parameter lists.
- Document exported packages, types, functions, methods, constants, and variables with useful Go documentation comments.

## Errors And Cleanup

- Return errors for routine failures and reserve panic for violated internal invariants or unrecoverable process policy.
- Wrap errors with `%w` when preserving identity and add operation or resource context that helps the caller.
- Use `errors.Is` and `errors.As` for programmatic decisions; never compare or parse error strings.
- Use sentinel errors or typed errors only when callers need a stable branchable contract.
- Check every relevant error, including deferred `Close`, `Flush`, `Sync`, encoder, writer, and response-body failures.
- When a deferred cleanup error matters, join it with or assign it to the named return rather than silently discarding it.
- Avoid accumulating `defer` calls inside unbounded loops; extract one iteration into a helper or close explicitly.
- Recover panic only at a boundary that can restore invariants and produce the required failure behavior; do not use recover as ordinary control flow.
- Keep cleanup idempotent where callers may invoke it repeatedly and ensure owned goroutines terminate before resources they use are released.

## Context And Concurrency

- Put `context.Context` first, propagate it unchanged unless deriving cancellation or deadline, and never pass `nil`.
- Do not store request contexts in long-lived structs or use context values for ordinary configuration or required dependencies.
- Use private typed keys for context values and reserve them for request-scoped metadata.
- Call every returned cancel function on all paths.
- Give every goroutine an owner, termination condition, concurrency limit, and observed result.
- Prefer structured synchronization such as an error group, wait group, or explicit supervisor according to project conventions.
- Make the sender responsible for closing a channel; do not close receive-only ownership or close a channel merely to signal one consumer when context or another primitive is clearer.
- Bound channels and worker pools and define overload behavior; avoid goroutine-per-item growth without a proven upper bound.
- Protect maps and shared state explicitly; do not rely on timing or channel usage that fails to establish ownership.
- Avoid starting goroutines in constructors unless ownership and shutdown are explicit in the returned type.
- Stop owned tickers and cancel timers when their work ends according to the supported Go runtime contract.

## I/O, Serialization, And Modules

- Handle short reads and writes according to `io.Reader` and `io.Writer` contracts; use standard helpers when they encode the required full-transfer behavior.
- Close response bodies and other acquired resources on every path, while preserving cleanup failures when they affect correctness.
- Use `filepath` for native paths and `path` for slash-separated protocol paths.
- Make JSON and other serialization tags part of compatibility review; define nil, empty, omitted, unknown-field, and numeric behavior.
- Keep `go.mod`, `go.sum`, module paths, toolchain directives, build tags, replacements, and vendoring changes intentional.
- Do not leave local `replace` directives in code intended for release unless the project explicitly owns that policy.

## Testing And Verification

- Prefer table-driven tests and subtests when they make behavior combinations clearer.
- Call `t.Helper()` in test helpers and use `t.Cleanup()` for owned cleanup.
- Use `t.Parallel()` only when the test and all shared fixtures are genuinely isolated.
- Use fuzz tests for parsers, decoders, validation, and other broad input spaces where useful.
- Benchmark measured hot paths with stable inputs and allocation reporting when allocation behavior matters.
- Run `gofmt` or `goimports`, `go vet`, and configured `staticcheck` or `golangci-lint` checks.
- Run `go test ./...`, applicable integration tests, and `go test -race ./...` for concurrent code where the target supports it.
- Verify supported build tags, Go versions, operating systems, architectures, module tidiness, generated code, and vulnerability checks when affected.
