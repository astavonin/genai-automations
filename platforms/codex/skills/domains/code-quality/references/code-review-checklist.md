# Code Quality Review Checklist

Use this checklist with the relevant language skill. Apply common sections to every language and the matching language-specific section where applicable.

## Contents

1. Readability and structure
2. Comments, suppressions, and formatting
3. Failure semantics and lifecycle
4. Concurrency and reliability
5. Observability and diagnostics
6. Dependencies and builds
7. I/O, data, and platform boundaries
8. Security and trust boundaries
9. Public compatibility
10. C++ checks
11. Python checks
12. Go checks
13. Rust checks
14. Dead symbol pass
15. Tests
16. Review output and severity

## 1. Readability And Structure

- [ ] Names communicate intent and the code is understandable without excessive comments.
- [ ] Hand-written functions stay focused; more than 80 physical lines triggers refactoring review, and a modified function over 100 lines has a cohesive split or explicit justification under the narrow exception policy.
- [ ] Modules, packages, and components have cohesive responsibilities and clear dependency direction.
- [ ] Public surfaces are narrow and do not leak incidental implementation dependencies.
- [ ] New abstractions solve demonstrated boundaries and reduce complexity.
- [ ] Project or ecosystem equivalents were considered before adding helpers, wrappers, macros, dependencies, or components.
- [ ] Extracted helpers replace same-scope inline duplicates.
- [ ] Time, randomness, storage, networking, processes, and configuration are explicit dependencies where tests need control.
- [ ] Mutable global state and ambient dependencies are avoided or have explicit ownership, synchronization, reset, and shutdown rules.

## 2. Comments, Suppressions, And Formatting

- [ ] Comments explain contracts, invariants, intent, trade-offs, or non-obvious behavior rather than restating code.
- [ ] Main interfaces and central data types document ownership, lifetime, concurrency, side effects, and valid-state constraints where relevant.
- [ ] TODOs are actionable; stale comments, commented-out code, and review-process labels are absent.
- [ ] Each lint or static-analysis suppression has a concrete reason and the narrowest practical scope.
- [ ] Suppressions do not hide correctness, safety, security, or maintainability problems.
- [ ] The project's formatter has been applied without unrelated churn.
- [ ] New patterns follow repository conventions unless divergence is justified.

## 3. Failure Semantics And Lifecycle

- [ ] Programmatic control flow uses typed errors, status values, or error codes rather than parsed diagnostics.
- [ ] Failure chains and actionable safe context survive propagation to the handling boundary.
- [ ] Timeout, cancellation, transient, permanent, invalid-input, conflict, and partial-success outcomes are distinct when callers need different behavior.
- [ ] Retries are bounded, use appropriate backoff, and apply only to idempotent operations or operations with idempotency protection.
- [ ] Failures are logged once at the handling or reporting boundary, not at every propagation layer.
- [ ] Fallible or predictably blocking cleanup has an explicit result-bearing API.
- [ ] Destructors, finalizers, and drop hooks are bounded, best-effort, and cannot throw or panic.
- [ ] Cleanup state transitions and shutdown order are explicit and safe when cleanup is omitted or repeated.
- [ ] Worker, task, thread, and background-operation results are observed or transferred to a documented supervisor.

## 4. Concurrency And Reliability

- [ ] Tasks, threads, workers, queues, buffers, retries, and in-flight work have owners and explicit limits.
- [ ] Backpressure, overload, timeout, cancellation, and resource-exhaustion behavior are defined.
- [ ] Background failure and cancellation propagate rather than silently abandoning work.
- [ ] Multiple-lock acquisition follows a defined order.
- [ ] User code, callbacks, logging hooks, and blocking work are not invoked while locks are held unless proven safe.
- [ ] Atomic ordering and cross-thread invariants are documented and tested when non-obvious.
- [ ] Coordination uses signals, events, fake time, or bounded polling rather than arbitrary sleeps.

## 5. Observability And Diagnostics

- [ ] Operator-visible failures use project-standard structured diagnostics with actionable context and stable fields.
- [ ] Correlation identifiers cross asynchronous and process boundaries when supported.
- [ ] Log levels are consistent and production paths avoid uncontrolled high-volume logging.
- [ ] Operationally relevant saturation, queue depth, retry, timeout, latency, task-health, health, and readiness signals exist.
- [ ] Metric-label cardinality is bounded.

## 6. Dependencies And Builds

- [ ] New dependencies and enabled features are necessary and project alternatives were considered.
- [ ] Maintenance, license, security, supported toolchains and targets, unsafe or native surface, transitive cost, and release stability were reviewed.
- [ ] Build scripts, code generators, compiler plugins, proc macros, and similar extensions receive executable-code review.
- [ ] Source forks, VCS dependencies, and wildcard versions are absent or have documented ownership and update strategy.
- [ ] Builds are deterministic and offline-capable where practical, with declared inputs and approved output paths.
- [ ] Build logic does not read undeclared host state, access secrets, or fetch unpinned network content.
- [ ] Lockfile and pinning changes are intentional and reproducible-build policy is preserved.
- [ ] Configured dependency, license, vulnerability, duplicate-version, and compatibility checks pass.

## 7. I/O, Data, And Platform Boundaries

- [ ] Untrusted sizes, counts, indices, paths, identifiers, recursion, allocation, and work are validated and bounded.
- [ ] Arithmetic and narrowing conversions cannot silently overflow, truncate, or change sign.
- [ ] Partial progress, interruption, short buffers, EOF, timeout, cancellation, and cleanup follow the boundary contract.
- [ ] Encoding, byte order, width, framing, ownership, and lifetime are explicit at wire, storage, ABI, and FFI boundaries.
- [ ] Durable schemas and configuration define versions, migration, defaults, unknown-field behavior, rollback, and compatibility.
- [ ] Platform-specific code is isolated and assumptions about filesystem, process, pointer width, endianness, and atomics are explicit.

## 8. Security And Trust Boundaries

- [ ] Trust boundaries are explicit and untrusted type, size, path, identifier, structure, encoding, and content are validated before sensitive use.
- [ ] Canonicalization and equivalent representations cannot bypass validation or authorization policy.
- [ ] Authentication and authorization coverage is explicit, centralized checks are demonstrably complete, and sensitive operations are unreachable without enforcement.
- [ ] Subprocess APIs receive argument sequences; any required shell use has a documented trust boundary and no untrusted interpolation.
- [ ] Errors, logs, traces, metrics, crash reports, and debug representations redact secrets and sensitive payloads.
- [ ] File, process, credential, network, and service permissions follow least privilege.
- [ ] Exploitable vulnerabilities, incompatible licenses, and other policy-blocking dependency findings are resolved before approval; lower-risk findings have a documented disposition.

## 9. Public Compatibility

- [ ] Source, binary, wire, storage, configuration, CLI, feature, toolchain, and platform compatibility commitments are identified.
- [ ] Public symbols, signatures, fields, variants, layouts, virtual or trait contracts, generic constraints, defaults, and dependency types were assessed for compatibility.
- [ ] Removed or renamed supported interfaces have deprecation and migration paths or an explicitly approved breaking-change plan.
- [ ] Public representation leaves reasonable room for future evolution.
- [ ] Promised old data, configuration, clients, or consumers are covered by compatibility tests.

## 10. C++ Checks

- [ ] Recoverable I/O, network, and external API failures use explicit project-native return channels rather than exceptions.
- [ ] Caller-significant `bool`, status, result, factory, and query returns are `[[nodiscard]]`; intentional discard is explicit and justified.
- [ ] Exceptions cannot escape destructors, C callbacks, C ABI boundaries, thread entry points, or cleanup paths.
- [ ] Required output parameters use references; pointers are reserved for truly optional outputs.
- [ ] Raw ownership is absent or justified; RAII owns every acquired resource.
- [ ] Special members follow the Rule of Zero or define and delete copy and move behavior consistently; const, casts, `noexcept`, overrides, and scoped enums express the contract accurately.
- [ ] No undefined behavior, dangling view, invalidated iterator, slicing, aliasing violation, or signed-overflow assumption is introduced.
- [ ] `errno` or equivalent OS error state is captured immediately after failure.
- [ ] Buffer APIs use bounded views such as `std::span` rather than raw pointer-size pairs where practical.
- [ ] Exported layout, inline code, templates, virtual interfaces, and compiler or standard-library requirements receive ABI and compatibility review.
- [ ] Thread lifetime uses structured ownership such as `std::jthread` where supported; non-obvious atomics name their memory-order contract.
- [ ] Applicable compiler warnings, static analysis, tests, sanitizers, and supported build configurations pass.

## 11. Python Checks

- [ ] Public and non-trivial code has useful annotations without unjustified `Any`, casts, ignores, protocols, overloads, or generic complexity.
- [ ] Mutable defaults are absent and sentinels distinguish omitted from explicit `None` when required.
- [ ] Data models match mutability, validation, and serialization needs and do not leak incidental third-party types.
- [ ] Context managers own scoped resources; `__del__` does not perform required fallible or blocking cleanup.
- [ ] Exceptions are specific, preserve chaining, and are caught only at a recovery, translation, or reporting boundary.
- [ ] Cancellation and termination exceptions are not swallowed or converted into success.
- [ ] Owned async tasks are awaited or supervised; blocking work stays off the event loop and synchronous locks do not cross `await`.
- [ ] Imports avoid wildcard use, circular coupling, unexpected side effects, and mutable module-global service state.
- [ ] Subprocess invocation avoids shell interpolation or documents and validates the trust boundary.
- [ ] Filesystem APIs preserve native paths, text and bytes boundaries are explicit, and external timestamps are timezone-aware.
- [ ] Package metadata, extras, entry points, public module paths, supported Python versions, formatting, linting, typing, packaging, and tests are verified where affected.

## 12. Go Checks

- [ ] Packages are cohesive; interfaces live at consumer boundaries and functions return concrete types unless abstraction is required.
- [ ] Zero values, constructors, pointer or value receivers, and nil versus empty behavior match the public contract.
- [ ] Typed nil pointers do not escape as non-nil interface values.
- [ ] Values containing synchronization state are never copied and retained slices, maps, buffers, functions, or pointers have explicit ownership.
- [ ] Errors preserve identity with wrapping and use `errors.Is` or `errors.As`; error strings are not control flow.
- [ ] Deferred `Close`, `Flush`, `Sync`, writer, encoder, and response-body errors are handled when correctness depends on them.
- [ ] Defers do not accumulate in unbounded loops.
- [ ] Context is first, propagated, never nil or stored as request state, and every derived cancel function is called.
- [ ] Goroutines, channels, worker pools, timers, and shared maps have owners, bounds, shutdown, and observed failures.
- [ ] Channel close ownership is unambiguous and constructors do not hide unmanaged goroutines.
- [ ] Reader and writer short-transfer contracts, response-body cleanup, path semantics, and serialization tags are handled correctly.
- [ ] Exported API, module path, Go version, build tags, replacements, formatting, vet, static analysis, tests, race detection, and module checks are verified where affected.

## 13. Rust Checks

- [ ] Ownership, borrowing, visibility, and lifetimes express the contract without convenience clones or unnecessary shared ownership.
- [ ] `Rc` or `Arc` cycles cannot leak; intentional process-lifetime leaks are justified.
- [ ] `From` is infallible, fallible conversion uses `TryFrom` or equivalent, and `AsRef` or `Borrow` honors its semantic contract.
- [ ] Equality, hashing, and ordering agree; `Debug` is useful without exposing secrets.
- [ ] Required mutable output uses `&mut T`, optional mutable output uses `Option<&mut T>`, and return values are preferred where clearer.
- [ ] Intentionally discarded `Result` values are explicit and justified.
- [ ] `std::io::Error::last_os_error()` is captured immediately after a failing raw syscall or FFI operation.
- [ ] Every unsafe operation has a narrow explicit block and adjacent `// SAFETY:` proof; `unsafe_op_in_unsafe_fn` is denied.
- [ ] Unsafe `Send` and `Sync` implementations and public unsafe APIs document complete caller and implementation obligations.
- [ ] FFI and self-referential designs prove validity, provenance, pinning, aliasing, unwind, ownership, and drop-order invariants.
- [ ] Async code does not hold unsupported synchronous guards across `.await`, discard join results, or block executor threads.
- [ ] Cargo features, MSRV, targets, doctests, public API, `no_std` or `alloc`, build scripts, proc macros, and dependency policy are verified where affected.
- [ ] Miri or configured equivalent checks changed unsafe abstractions, with unsupported paths reported.

## 14. Dead Symbol Pass

For each field, member, parameter, named constant, or non-local variable introduced or modified:

- [ ] It has a production read-site beyond construction or initialization.
- [ ] Test fixtures that merely construct the type are not counted as read-sites.
- [ ] Written-but-never-read symbols are removed or have an explicit compatibility reason.
- [ ] Discarded API parameters are flagged when the contract implies they should affect behavior.

## 15. Tests

- [ ] Tests cover the intended behavior and affected public API paths.
- [ ] Each distinct failure mode and independently rejected validation behavior has a concrete negative test as defined by the testing skill.
- [ ] Assertions verify exact values, state changes, error types, or observable behavior rather than existence or call count alone.
- [ ] Test names match the scenario and asserted outcome.
- [ ] Unit tests are fast and isolated; integration tests are separated and do not call production services.
- [ ] Async and readiness tests use deterministic synchronization.
- [ ] Cleanup, cancellation, timeout, saturation, partial I/O, and background failure are tested where relevant.
- [ ] Regression tests reproduce fixed behavioral bugs when practical.
- [ ] Flaky tests are fixed or removed rather than ignored.

## 16. Review Output Expectations

- [ ] Findings focus on concrete correctness, reliability, supportability, security, or maintainability risks.
- [ ] Runtime-behavior findings include a `Required test:` line with the trigger and asserted outcome.
- [ ] Style feedback is raised only when it affects readability or consistency.
- [ ] Suggested fixes are concrete and proportional.

## Severity Guidance

| Level | Meaning |
|---|---|
| `Critical` | Correctness, safety, or security failure that can cause severe harm, data loss, or systemic breakage. |
| `High` | Substantial correctness, reliability, supportability, compatibility, or design defect that must be fixed before approval. |
| `Medium` | Material test, maintainability, clarity, or consistency defect that must be fixed before approval. |
| `Low` | Non-blocking improvement not required for correctness or approval. |
