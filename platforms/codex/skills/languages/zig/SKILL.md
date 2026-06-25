---
name: zig
description: Zig implementation and review guidance for safe, modern, maintainable, and supportable code. Use when writing, modifying, debugging, or reviewing Zig source, allocators, error handling, comptime patterns, build system, and tests.
---

# Zig Programming Skill

Treat this file as the Zig-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, observability, dependencies, I/O, compatibility, and test coverage.

## Language And Build Contract

- Inspect `build.zig`, `build.zig.zon`, the declared minimum Zig version, target options, and optimize options before editing.
- Use only language and standard-library features available in the project's minimum Zig version. Do not raise the minimum version incidentally.
- Run `zig fmt` on every modified file. Run `zig build` and `zig build test` to verify before committing.
- Follow the Zig Style Guide: 4-space indentation, `camelCase` for functions and variables, `PascalCase` for types, `SCREAMING_SNAKE_CASE` for constants.

## Allocators And Memory

- Every function that allocates must accept an explicit `std.mem.Allocator` parameter. There is no implicit global allocator; the standard library is usable on freestanding targets as a result.
- Use `Unmanaged` container variants (`std.ArrayListUnmanaged`, `std.HashMapUnmanaged`, etc.) that accept the allocator per call. Managed variants of `std.ArrayList`, `std.ArrayHashMap`, `std.HashMap`, and others that store the allocator internally are deprecated in Zig 0.14.0; consult the 0.14.0 release notes for the complete list.
- Choose the allocator that matches the build mode and workload:
  - `std.heap.DebugAllocator` — Debug and ReleaseSafe; detects leaks, double-free, use-after-free with stack traces. Renamed from `GeneralPurposeAllocator` after a rewrite in 0.14.0; new code should use the new name.
  - `std.heap.SmpAllocator` — ReleaseFast multithreaded; near-glibc-malloc performance; thread-safe singleton. New in 0.14.0.
  - `std.heap.ArenaAllocator` — batch-allocate then `deinit`-all-at-once; no individual frees required.
  - `std.heap.FixedBufferAllocator` — stack or comptime-sized buffer; no OS allocation.
  - `std.testing.allocator` — test builds only; `@compileError` prevents use in non-test code.
- Use `defer` to call `deinit` or `destroy` on the same object and in the same scope where it is initialized, unless ownership is explicitly transferred.
- Do not pair every allocation with an immediate `defer free` when an `ArenaAllocator` or pool owns the lifetime; use the allocator's batch-release mechanism instead.

## Error Handling

- Error unions (`!T` or `ErrorSet!T`) are non-ignorable. Assigning to `_` is a compile error; every result must be handled via `try`, `catch`, or an explicit branch.
- Use `try` to propagate errors to the caller when the current scope cannot recover.
- Use `catch |err| switch (err) { ... }` to dispatch on specific errors; `switch` over a named error set must exhaustively cover all members — the compiler lists unhandled members.
- Define named error sets for public APIs so callers can write exhaustive switches. Infer error sets (`!T`) for private or internal functions where the set is unstable.
- Errors are typed values comparable to named constants. Do not use strings or sentinel integers as error carriers.
- Do not convert error unions into optional values unless the error detail is genuinely irrelevant to all callers.

## Comptime And Generics

- Generic types and functions are ordinary functions that accept `comptime` parameters and return a type or value. There is no separate template syntax.
- Use `@typeInfo(T)` for compile-time dispatch over all Zig types; it returns a tagged union covering every type category. Switch over it exhaustively.
- Use `@compileError("message")` to reject unsupported types in generic code with a user-visible compile-time message.
- Use `@typeName(T)` in `@compileError` messages to identify the offending type.
- Evaluate expressions at comptime using `comptime { }` blocks or `comptime` parameters. Prefer comptime over runtime branching when all inputs are compile-time known.
- Do not over-apply comptime: prefer clear runtime logic when the comptime version does not reduce code size, binary size, or improve correctness.

## Safety And Build Modes

Zig has four distinct safety outcomes — not a simple safe/unsafe binary:

| Situation | Outcome |
|---|---|
| Illegal behavior at compile time | Always a compile error |
| Detectable illegal behavior in Debug / ReleaseSafe | Calls panic handler — well-defined, not UB |
| Undetectable illegal behavior in Debug / ReleaseSafe | True undefined behavior even in safe modes |
| Any illegal behavior in ReleaseFast / ReleaseSmall | Always undefined behavior |

- Do not write code that relies on safety checks to mask bugs — safe modes still contain undetectable UB.
- `@setRuntimeSafety(false)` disables checks at block granularity within a safe build mode. Use it only in verified hot paths and document why. Note: does not propagate into inlined function bodies (issue #12971).
- Build the project in all relevant optimize modes (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`) when the change touches safety-sensitive paths.

## Build System

- `build.zig` is a plain Zig file defining a DAG of concurrently-executed steps. No cmake, make, shell, or msvc dependency is needed.
- Use `b.standardTargetOptions(.{})` and `b.standardOptimizeOption(.{})` to expose `-Dtarget` and `-Doptimize` flags; do not hardcode target or optimize values.
- Wire test suites via `b.addTest` → `b.addRunArtifact` → `test_step.dependOn` so `zig build test` runs all suites concurrently. Each `dependOn` call is independent, so multiple suites run in parallel:

```zig
const unit_tests = b.addTest(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
const integration_tests = b.addTest(.{
    .root_source_file = b.path("src/integration.zig"),
    .target = target,
    .optimize = optimize,
});
const test_step = b.step("test", "Run all test suites");
test_step.dependOn(&b.addRunArtifact(unit_tests).step);
test_step.dependOn(&b.addRunArtifact(integration_tests).step);
```

- Use `b.dependency` to consume packages declared in `build.zig.zon`; use `dep.module("name")` to expose them as modules.

## Package Management

- `build.zig.zon` is the package manifest. The `hash` field is the authoritative package identity. In Zig 0.14.0+ the hash format embeds the package name, version, fingerprint ID, and total unpacked size alongside a SHA-256 over the files listed in `paths`. Packages come from a hash, not a URL; a URL is one possible mirror.
- Use `zig fetch --save <url>` to add dependencies; this fetches, computes the hash, and writes both `url` and `hash` to `build.zig.zon`.
- When updating a dependency URL, delete the existing `hash` first. Keeping the old hash asserts the old content exists at the new URL; a mismatch blocks the build.
- Do not manually edit `hash` values.

## Testing

- Test functions return `!void` (`anyerror!void`). Use `try` to propagate test failures; `std.testing` assertions return named error values on failure — they do not panic.
- Use `std.testing.allocator` for all heap allocations in tests. It is a `DebugAllocator` (in 0.14.0) with 10-frame stack-trace capture, double-free detection, and leak detection. A `@compileError` prevents use outside test builds.
- Cover OOM paths with `std.testing.checkAllAllocationFailures`: it runs the test function N+1 times (one baseline, N with each allocation targeted to fail) and verifies no leaks on any failure path.
- Prefer testing individual functions over integration tests for low-level logic. Use `zig build test` to run all suites.
- Test error paths explicitly: use `try std.testing.expectError(expected_error, actual_result)` rather than asserting non-error.

## Concurrency

- `async`/`await` regressed with the move to the self-hosted compiler in Zig 0.11 and remains unavailable in 0.12, 0.13, and 0.14. Do not use it.
- A new async I/O design targeting Zig 0.16 distinguishes `io.async` (schedules without guaranteed parallelism) from `io.concurrent` (guarantees concurrent execution). When 0.16 ships, use `io.concurrent` in producer-consumer patterns to avoid deadlocks on single-threaded executors.
- For current parallel workloads, use `std.Thread` with explicit synchronization via `std.Thread.Mutex`, `std.Thread.Semaphore`, or `std.atomic`.

## Verification

- Run `zig fmt` on all modified files.
- Run `zig build` with the project's standard target and optimize options.
- Run `zig build test` to execute all test suites.
- Build in `Debug` and `ReleaseSafe` to exercise safety checks; build in `ReleaseFast` or `ReleaseSmall` for performance-sensitive paths.
- Run `zig build` with `-Dtarget=<cross-target>` for any cross-compilation targets the project supports.
