---
name: rust
description: Rust implementation and review guidance for safe, maintainable, and supportable Cargo projects. Use when writing, modifying, debugging, or reviewing Rust source, Cargo manifests, public crate APIs, dependencies, unsafe code, async or concurrent code, operational behavior, and Rust tests.
---

# Rust Programming Skill

Treat this file as the Rust-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, concurrency, observability, dependencies, I/O, compatibility, and test coverage.

## Cargo And Project Contract

- Inspect `Cargo.toml`, `Cargo.lock`, `rust-toolchain*`, workspace lint configuration, CI commands, and nearby code before editing.
- Identify workspace members, crate types, edition, MSRV, supported targets, feature matrix, `no_std` or `alloc` commitments, and whether the toolchain is pinned.
- Distinguish public library compatibility from application deployment requirements.
- Follow workspace dependency, resolver, lint, build-script, generated-code, and lockfile policy without unrelated resolution churn.

## Ownership And API Types

- Make ownership transfer explicit and keep visibility as narrow as possible.
- Accept `&str`, `&[T]`, or another borrowed view when ownership is unnecessary; return owned values when borrowing would couple unrelated lifetimes.
- Prefer returned values over output mutation. Use `&mut T` for required mutable output and `Option<&mut T>` only when omission is meaningful.
- Do not clone merely to satisfy the borrow checker; permit intentional cheap clones at genuine ownership boundaries.
- Use `Box`, `Rc`, `Arc`, cells, locks, and atomics only when their semantics are required.
- Prevent `Rc` and `Arc` cycles with `Weak` or a different ownership model; justify `Box::leak`, `mem::forget`, and other intentional process-lifetime leaks.
- Use newtypes and enums to encode constraints and avoid boolean-heavy APIs.
- Use `From` only for infallible conversions and `TryFrom` or `FromStr` for fallible validation.
- Use `AsRef` and `Borrow` only when their semantic contracts hold.
- Keep `Eq` and `Hash`, and `Ord` and `PartialOrd`, mutually consistent.
- Implement `Debug`, `Display`, `Error`, `Default`, and iterator traits when their semantics are honest and useful; redact sensitive `Debug` output.
- Mark caller-significant values and types `#[must_use]` when silent discard is likely a bug.
- Use `#[repr(C)]` only for a documented ABI or layout-interoperation contract; never use native layout directly as a wire or storage format.

## Results, Panics, And OS Errors

- Use `Option<T>` only when absence needs no reason and `Result<T, E>` for recoverable failure.
- Use typed public errors when callers need to branch; preserve `Error::source` and add context at meaningful boundaries.
- Keep timeout, cancellation, and partial-success outcomes distinct when callers need different handling.
- Avoid opaque boxed errors in public library APIs unless type erasure is intentional.
- Avoid `unwrap()` and `expect()` in production paths except for a locally proven invariant; state the invariant in a non-obvious `expect` message.
- Do not use `let _ = result` to hide a caller-significant `Result`; handle it or make best-effort discard explicit and justified.
- Capture `std::io::Error::last_os_error()` immediately after a failing raw syscall or FFI operation.
- Reserve panic for violated programmer invariants and never let panic cross an FFI boundary.

## Drop And Shutdown

- Never panic from `Drop` and avoid predictably blocking destructors.
- Provide explicit result-bearing `close`, `flush`, or `shutdown` when cleanup can fail or must await completion.
- Let `Drop` perform safe best-effort fallback cleanup and ensure dependent fields, tasks, callbacks, and foreign handles shut down in a safe order.
- Do not detach owned work silently; observe join results or transfer ownership to a documented supervisor.

## Unsafe Rust And FFI

- Deny unsafe code where unnecessary and centralize required unsafe operations behind small safe abstractions.
- Require an explicit `unsafe {}` block for every unsafe operation, including inside `unsafe fn`; deny `unsafe_op_in_unsafe_fn`.
- Put an adjacent `// SAFETY:` proof on every unsafe block and unsafe `Send` or `Sync` implementation.
- State validity, lifetime, alignment, aliasing, initialization, provenance, layout, unwind, and thread-safety assumptions.
- Document every public `unsafe fn` or unsafe trait with a `# Safety` section describing caller obligations.
- Validate pointers, lengths, alignment, ownership, and nullability at FFI boundaries and define allocation and release ownership.
- Do not hand-roll self-reference or erase lifetimes with `transmute` without an approved design and a complete proof covering initialization, pinning, aliasing, mutation, escape, unwind, and drop order.
- Prefer scoped guards, split ownership, typestate, stable handles, or a reviewed safe self-referential crate before manual unsafe code.
- Run Miri or the configured equivalent for changed unsafe abstractions and report unsupported FFI or execution paths.

Treat a missing or unprovable safety invariant as a correctness defect.

## Async And Rust Concurrency

- Treat future cancellation as normal control flow and preserve invariants if a future is dropped at any `.await`.
- Do not hold a synchronous mutex or read/write guard across `.await` unless the primitive and design explicitly support it.
- Keep blocking I/O and CPU-heavy work off executor threads through the runtime's blocking mechanism.
- Observe every owned task's result and panic; do not create detached tasks without documented supervision.
- Use channels, locks, and atomics according to communication semantics and document non-obvious memory ordering.
- Do not infer logical correctness solely from `Send` or `Sync`; verify lifecycle and ordering invariants.

## Cargo Features, Builds, And Public APIs

- Keep features additive where practical, document them, and avoid exposing optional dependency names as accidental public features.
- Record promised MSRV with `rust-version` and verify supported features on that toolchain.
- Keep build scripts deterministic and offline-capable, emit precise `rerun-if-*` directives, and write generated output only under `OUT_DIR` or project-approved locations.
- Treat proc macros and build scripts as executable dependencies and keep their public expansion or generated interface stable where promised.
- Use private fields, sealed traits, and newtypes when they preserve future evolution.
- Review public items, variants, trait items, generic bounds, layouts, features, MSRV, targets, and public dependency types for compatibility impact.
- Apply `#[non_exhaustive]` before stabilization only when downstream construction or matching should remain open.
- Deprecate and provide migration paths before removing supported APIs; temporarily re-export old paths when proportionate.
- Add `//!` crate or module documentation and `///` public API documentation, including errors, panics, safety, blocking, cancellation, ownership, and examples where relevant.
- Keep declarative macros hygienic, use `$crate` for internal paths, minimize exported names, and test expansion from a downstream crate.
- Preserve promised `no_std` or `alloc` support and keep target-specific `cfg` logic behind narrow modules.

## Rust Testing And Verification

- Keep focused unit tests near implementation details, integration harnesses in `tests/`, and deterministic doctests for public examples.
- Use `compile_fail` doctests or project-native UI tests for compile-time contracts.
- Assert exact successful values and specific error variants or properties rather than only `is_ok()` or `is_err()`.
- Cover the supported feature matrix, MSRV, target-specific behavior, and `no_std` or `alloc` configurations where applicable.
- Use property tests, fuzzing, concurrency model checking, fault injection, or Miri when risk and project tooling justify them.
- Run project-native commands first; otherwise use the applicable subset:

```text
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets
cargo test --workspace --all-targets
cargo test --workspace --doc
cargo doc --workspace --no-deps
```

- Make Clippy and rustdoc warnings fail through pinned-toolchain or repository lint policy.
- Verify supported feature combinations, declared MSRV, affected non-host targets, locked application resolution, dependency policy, and changed unsafe code.
