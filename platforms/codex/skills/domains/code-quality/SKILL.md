---
name: code-quality
description: Shared engineering, supportability, and code-quality rules covering structure, errors, lifecycle, concurrency, observability, dependencies, compatibility, comments, suppressions, and formatting. Use when writing or reviewing code in any supported language.
---

# Code Quality Skill

Treat this skill as the shared implementation and code-review contract. Apply it together with the relevant language skill and the `testing` skill.

## Readability And Structure

- Prefer code that needs minimal comments and names that communicate intent.
- Keep hand-written functions focused; use branch count, nesting, state transitions, ownership, and lifecycle responsibilities as stronger signals than line count alone.
- Treat 80 physical lines as a refactoring prompt. A modified hand-written function over 100 physical lines requires either a cohesive split or an explicit review justification.
- Limit size exceptions to declarative tables, state-machine dispatch, or cohesive test scenarios where extraction would obscure behavior. Generated code is outside this rule and should not be edited manually.
- Prefer cohesive modules or packages with a clear dependency direction and narrow public surfaces.
- Keep implementation details and incidental dependency types out of public interfaces.
- Prefer concrete types until a demonstrated substitution, extension, or test boundary requires abstraction.
- Avoid speculative interfaces, excessive generic machinery, hidden global state, and micro-components without a genuine ownership, policy, build, or reuse boundary.
- Inject clocks, randomness, storage, networking, process execution, and configuration when deterministic testing or alternate implementations require control.
- Search the project and ecosystem before adding a helper, wrapper, macro, or dependency; migrate same-scope duplicates when introducing a shared abstraction.

## Failure Semantics And Lifecycle

- Use typed errors, status values, or error codes for caller decisions; keep diagnostic text separate from control flow.
- Preserve the original failure chain and add safe operation or resource context only at meaningful abstraction boundaries.
- Classify timeout, cancellation, transient, permanent, conflict, invalid-input, and partial-success outcomes when callers require different recovery behavior.
- Log a failure once at the boundary that handles, reports, or abandons it; do not log the same failure at every propagation layer.
- Bound retries by count or deadline, use appropriate backoff, and retry only idempotent operations or operations with an idempotency mechanism.
- Provide an explicit result-bearing `close`, `flush`, or `shutdown` path when cleanup can fail or predictably block.
- Keep destructors, finalizers, and drop hooks non-throwing or non-panicking, bounded, and best-effort.
- Define cleanup state transitions, idempotency, and shutdown order across dependent resources, callbacks, tasks, threads, and foreign handles.
- Observe worker and background-operation results or deliberately transfer them to a documented supervisor.

## Concurrency And Reliability

- Give every task, thread, worker, and background operation an owner, concurrency limit, cancellation path, timeout policy, and shutdown behavior.
- Bound queues, channels, buffers, retries, and in-flight work; define backpressure, overload, and resource-exhaustion behavior.
- Propagate cancellation and background failures instead of silently abandoning work.
- Define lock ordering when multiple locks can be acquired.
- Do not call user code, callbacks, logging hooks, or blocking operations while holding a lock unless reentrancy and latency are proven safe.
- Document and test non-obvious atomic memory ordering and cross-thread state invariants.
- Use explicit signals, events, fake time, or bounded polling instead of arbitrary sleeps for coordination.

## Observability And Diagnostics

- Use the project's existing logging, tracing, metrics, and health mechanisms.
- Emit structured diagnostics at external boundaries, state transitions, retries, timeouts, overload, degraded operation, and final failure where operators need visibility.
- Include stable fields such as component, operation, resource, peer, attempt, elapsed time, and outcome when relevant.
- Propagate correlation or request identifiers across asynchronous and process boundaries when supported.
- Choose severity consistently and avoid high-volume per-item logging in production paths.
- Expose operationally relevant saturation, queue depth, retry, timeout, latency, task-health, health, and readiness signals with bounded metric-label cardinality.

## Dependencies And Reproducible Builds

- Minimize direct and transitive dependencies and enable only required features or components.
- Before adding a dependency, evaluate project alternatives, maintenance, license, security history, supported toolchains and targets, unsafe or native surface, transitive cost, and release stability.
- Treat build scripts, code generators, compiler plugins, proc macros, and similar build-time extensions as executable dependencies requiring review.
- Avoid wildcard versions and unjustified source forks or VCS dependencies; document ownership and update strategy for exceptions.
- Keep builds deterministic and offline-capable where practical. Declare build inputs precisely, write generated output only to approved locations, and do not read undeclared host state or secrets.
- Follow repository lockfile and pinning policy, avoid incidental dependency churn, and use locked resolution for reproducible application builds.
- Run configured dependency, license, vulnerability, duplicate-version, and compatibility checks.

## I/O, Data, And Platform Boundaries

- Validate untrusted sizes, counts, indices, recursion depths, allocation requests, paths, and identifiers before use.
- Use checked arithmetic and fallible narrowing or signedness conversions when overflow or truncation is possible.
- Handle partial progress, interruption, short buffers, EOF, timeout, cancellation, and cleanup according to the boundary contract.
- Make encoding, byte order, numeric width, framing, ownership, and lifetime explicit at wire, storage, ABI, and FFI boundaries.
- Version durable schemas and configuration; define migration, defaulting, unknown-field, rollback, and compatibility behavior.
- Isolate platform-specific code and document assumptions about filesystem, process, pointer-width, endianness, and atomic behavior.
- Bound memory, CPU, I/O, retry, and recursion work derived from external input.

## Security And Trust Boundaries

- Identify trust boundaries and validate untrusted type, size, path, identifier, structure, encoding, and content before sensitive use. Canonicalize only when the boundary contract defines how equivalent representations are handled.
- Enforce authentication and authorization at a defined entry boundary and ensure every sensitive operation is unreachable without that check. Centralized middleware is acceptable when coverage is explicit and testable.
- Pass argument sequences to subprocess APIs. Use a shell only when its semantics are required, and never interpolate untrusted values into shell commands.
- Never expose secrets, credentials, tokens, private keys, or unrestricted sensitive payloads in errors, logs, traces, metrics, crash reports, or debug representations.
- Apply least privilege to files, processes, credentials, network access, and service identities.
- Run configured dependency vulnerability and license checks. Treat exploitable or policy-blocking vulnerabilities and incompatible licenses as blockers; assess lower-risk findings according to project policy and documented exposure.

## Public Compatibility

- Identify source, binary, wire, storage, configuration, CLI, feature, toolchain, and platform compatibility commitments before changing them.
- Review public symbols, signatures, fields, variants, layouts, virtual or trait contracts, generic constraints, defaults, and dependency types for compatibility impact.
- Deprecate supported interfaces and provide migration paths before removal or rename; preserve compatibility shims when proportionate.
- Keep extension points intentional and avoid exposing internal representation that prevents future evolution.
- Test supported old data, configuration, clients, or consumers when compatibility is promised.

## Performance Discipline

- Avoid accidental quadratic behavior, unbounded growth, unnecessary copying or allocation, and blocking work on latency-sensitive paths.
- Profile before optimizing and benchmark optimized builds with a representative workload.
- Require before-and-after evidence and a documented trade-off when performance work adds complexity, unsafe behavior, or maintenance cost.

## Comments, Suppressions, And Formatting

- Use `references/comments.md` as the canonical comment and public-documentation policy.
- Use `references/linter-suppressions.md` when adding or reviewing a suppression; every suppression requires a concrete reason and the narrowest practical scope.
- Use `references/formatting.md` for formatter selection and scope; format every modified file without unrelated churn.
- Keep review-process metadata out of source files, comments, docstrings, and test names.

## Review Workflow

- Use `references/code-review-checklist.md` for implementation review.
- Prefer concrete correctness, reliability, supportability, and maintainability findings over style-only feedback.
- Treat unexplained suppressions, stale comments, hidden failures, unbounded work, discarded background errors, secret exposure, dependency drift, and missing formatting as defects.

Use these canonical references for comment, suppression, and formatting rules:

- `references/comments.md`
- `references/linter-suppressions.md`
- `references/formatting.md`
