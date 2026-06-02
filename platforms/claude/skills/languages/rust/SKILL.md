---
name: rust
description: Rust coding standards based on Rust API Guidelines. Use when writing, reviewing, or modifying Rust code to apply ownership patterns, error handling with Result/Option, and zero-cost abstractions.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: languages
  tags: [rust, programming]
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

### Borrow Checker as Design Partner

The borrow checker is a design signal, not an obstacle. When it pushes back, evaluate whether the design needs rethinking before reaching for workarounds.

**Preferred patterns (work with the borrow checker):**
- **Scoped guard / RAII guard** — return a struct that borrows the owner for the duration of a scoped operation, like `Mutex::lock() → MutexGuard`. This encodes "resource active in this scope" in the type system and prevents misuse at compile time. Example: `session.streaming() → CaptureStream<'_>` instead of storing a self-referential stream field.
- **Split ownership** — separate the long-lived owner from the short-lived borrower; pass both explicitly to call sites that need both.
- **Typestate / state machine** — encode lifecycle stages as distinct types; illegal transitions become compile errors.
- **Restructure data** — if field A needs to borrow field B, consider whether they can be separated into independent structs with a clear ownership hierarchy.

**Escalating workarounds (use only when idiomatic patterns are exhausted, in this order):**
1. `ouroboros` or `self_cell` — safe but adds a dependency and generates opaque code; appropriate when the guard pattern is genuinely unsuitable.
2. `Arc<Mutex<T>>` shared ownership — when multiple independent owners are truly needed.
3. `unsafe` + `Pin<Box<T>>` with transmuted lifetime — last resort; requires a documented safety invariant and a clear reason why safe alternatives fail.

**Red flags that warrant redesign discussion:**
- Recreating an expensive resource on every call instead of reusing it (e.g., re-opening a stream per frame, re-establishing a connection per request). This defeats streaming/pooling architectures and is often the symptom of a missing scoped guard.
- `std::mem::transmute` used to erase a lifetime (e.g., `'a → 'static`) without a pinned owner and documented invariant.
- `Option<ResourceType<'static>>` inside a struct where `'static` is achieved via transmute.
- Storing both an owner and a borrow of that owner in the same struct without `ouroboros`/`self_cell`.

**Tradeoff analysis — when borrow checker tension arises, evaluate all options before implementing:**

| Approach | Safety | Dependencies | Ergonomics | When to use |
|----------|--------|--------------|------------|-------------|
| Scoped guard (`T<'_>`) | ✅ | None | ✅ | Scoped exclusive access to a resource |
| Typestate | ✅ | None | ⚠️ | Lifecycle stages that must be explicit |
| Split ownership | ✅ | None | ⚠️ | Caller can manage both lifetimes |
| `ouroboros`/`self_cell` | ✅* | External | ⚠️ | True self-referential need, safe required |
| `Arc<Mutex<T>>` | ✅ | None | ⚠️ | Shared multi-owner access |
| `unsafe` + `Pin` | ❌* | None | ✅ | Last resort with documented invariant |

*Safe externally; uses `unsafe` internally.

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

- Rust API Guidelines: https://rust-lang.github.io/api-guidelines/
- The Rust Book: https://doc.rust-lang.org/book/
