---
name: rust
description: Rust API Guidelines and best practices
---

# Rust Programming Skill

## Standards

**Follow Rust API Guidelines:**
- https://rust-lang.github.io/api-guidelines/

**Follow The Rust Book:**
- https://doc.rust-lang.org/book/

## Key Principles

### Ownership & Borrowing
- Understand ownership, borrowing, and lifetimes
- Prefer borrowing over cloning
- Use references for read-only access
- Use mutable references when modification needed
- Follow lifetime elision rules

### Error Handling
- Use `Result<T, E>` for recoverable errors
- Use `Option<T>` for optional values
- Propagate errors with `?` operator
- Panic only for programming errors
- Provide context with error types

### Type Safety
- Leverage Rust's type system
- Use newtypes for domain modeling
- Make illegal states unrepresentable
- Use enums for variants
- Use pattern matching extensively

### Code Organization
- One module per file or directory
- Use `pub` for public APIs
- Use `pub(crate)` for crate-internal items
- Keep modules focused and cohesive

### Testing
- Unit tests in same file (in `mod tests`)
- Integration tests in `tests/` directory
- Use `#[test]` attribute
- Use `#[cfg(test)]` for test-only code

### Performance
- Zero-cost abstractions
- Avoid unnecessary allocations
- Use iterators (lazy evaluation)
- Profile before optimizing
- Use `cargo bench` for benchmarks

## Formatting

Run rustfmt automatically.

## Static Analysis

Run clippy for lints and best practices.

## References

See `references/` directory for Rust patterns and idioms.
