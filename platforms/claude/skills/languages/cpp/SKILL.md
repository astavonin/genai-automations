---
name: cpp
description: C++ implementation and review guidance for safe, modern, maintainable, and supportable code. Use when writing, modifying, debugging, or reviewing C++ source, public APIs, ownership, concurrency, ABI boundaries, build configurations, and tests.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: languages
  tags: [cpp, c++, programming]
---

# C++ Programming Skill

Treat this file as the C++-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, concurrency, observability, dependencies, I/O, compatibility, and test coverage.

## Language And Build Contract

- Inspect build files, presets, dependency manifests, generated-code policy, configured C++ standard, supported compilers and standard libraries, warning policy, sanitizers, targets, and project-native commands before editing.
- Use only language and library features supported by the project's declared standard and toolchain matrix. Do not raise the minimum standard or compiler requirement incidentally.
- Preserve project ABI, exception, RTTI, allocation, visibility, and static-versus-shared linkage policy.
- Keep compiler extensions and feature-test fallbacks narrow, explicit, and covered by supported configurations.

## Key Principles

### Modern C++
- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Use STL containers and algorithms
- Prefer `auto` for type deduction where it improves readability
- Use `constexpr` when compile-time evaluation improves correctness or removes runtime work without obscuring intent. Use `consteval` only when the supported standard and immediate-function semantics require it.
- Prefer static polymorphism over dynamic

### Safety
- Avoid undefined behavior
- Use proper const correctness
- Initialize all variables
- Avoid C-style casts (use static_cast, dynamic_cast, etc.)
- Use range-based for loops
- Prefer `{}` over `()` for variable initialization of user-defined types and smart pointers — `()` can be parsed as a function declaration (most vexing parse). Exception: use `()` for standard library containers (`std::string`, `std::vector`, etc.) when the constructor is a fill or range constructor, because `{}` routes through `initializer_list` and changes semantics.

### Code Organization
- Header guards or `#pragma once`
- Minimize header dependencies
- Forward declarations where possible
- Keep header files clean and minimal
- One file - one class where possible

### Error Handling

#### Choose the right error channel

| Situation | Mechanism |
|---|---|
| Operation may produce no result; no detail needed | `std::optional<T>` |
| Binary pass/fail; caller branches on the result | `[[nodiscard]] bool` |
| Multiple distinct failure modes the caller must dispatch on | `[[nodiscard]]` status enum |
| Value + typed error reason in one return (C++23) | `std::expected<T,E>` |
| Truly unrecoverable programmer error (logic bug, invariant violation) | Exception |

Never use exceptions for I/O failures, network errors, or external API results — those are expected outcomes, not exceptional ones.

If `std::expected<T,E>` is unavailable, use an existing project-native `Result`, `StatusOr`, or status-enum pattern. Do not introduce a new result wrapper for one feature unless it removes clear duplication and matches project conventions.

Use typed errors, status enums, or error codes for programmatic decisions. Human-readable strings are diagnostic detail; callers must not parse message text to decide control flow.

#### `[[nodiscard]]`

Apply `[[nodiscard]]` to every non-void function whose return value the caller **must** act on:
- Error-indicating `bool` returns
- Status/result enums
- Factory and query functions where the return is the only purpose

When a discard is genuinely intentional, cast to `void` and explain why:
```cpp
(void)flush();  // best-effort; aborting anyway, result does not affect control flow
```

Trampolines and callbacks registered with external frameworks (libcurl, POSIX signal handlers) are exempt — the framework consumes their return value, not our code.

`[[nodiscard]]` does **not** propagate from a virtual base to its overrides. Annotate every site explicitly: the base declaration, every override, and every test fake/mock that implements the interface.

#### Exception boundaries

Do not allow exceptions to escape destructors, C callbacks, C ABI boundaries, thread entry points, or cleanup paths. Catch at those boundaries and convert the failure to the appropriate status/result/logging behavior with diagnostic context.

#### Output parameters: pointer vs reference

Use `std::string&` (reference) for required output parameters — a pointer implies the argument is optional (`nullptr` = don't care).

```cpp
// Wrong: pointer implies nullable
bool checked_setopt(CURL* curl, CURLoption option, long value, std::string* detail);

// Right: reference communicates "always required"
bool checked_setopt(CURL* curl, CURLoption option, long value, std::string& detail);
```

Use a pointer only when `nullptr` is a valid and meaningful argument.

#### Error detail propagation in chained operations

When multiple calls share one outcome string, pass `std::string&` down and let the first failure fill it. Combine with short-circuit evaluation to stop at the first error:

```cpp
std::string detail;
if (!checked_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L, detail) ||
    !checked_setopt(curl, CURLOPT_CAINFO, ca_path, detail)) {
    LOGE("TLS setup failed: %s", detail.c_str());
    return error_result(detail);
}
```

Do not allocate a new string per call in a hot path.

#### `errno` and system call errors

Capture `errno` immediately after the failing call — any subsequent call (including logging helpers) may clobber it:

```cpp
const int err = errno;
LOGE("open(%s) failed: %s", path, strerror(err));
```

Log `strerror(err)` with enough context (function name, path, relevant arguments) to diagnose without source access.

### C++20 Patterns

#### Cooperative cancellation — `std::stop_token` / `std::stop_source` / `std::jthread`

Prefer `std::stop_token` over `std::atomic<bool>` cancel flags when a thread must be told to stop from outside.

```cpp
// Wrong: raw atomic flag, no standard interop
std::atomic<bool> cancel{false};
std::thread worker([&] { while (!cancel.load()) { /* ... */ } });
cancel = true;
worker.join();

// Right: structured cancellation with jthread auto-join
std::jthread worker([](std::stop_token token) {
    while (!token.stop_requested()) { /* ... */ }
});
// worker.request_stop() + join() happen automatically in ~jthread
```

Use `std::stop_token` for new code. Keep `std::atomic<bool>` only at C API boundaries (e.g., libcurl write callbacks) where the token cannot be passed through the framework.

#### Buffer views — `std::span`

Replace raw pointer + size pairs with `std::span<T>`. Spans carry length, support range-for, and compose with STL algorithms without copying.

```cpp
// Wrong: pointer + size — caller must track length separately
void process(const char* data, size_t len);

// Right: span expresses both, caller cannot mismatch them
void process(std::span<const char> data);
```

Use `std::span<const T>` for read-only views, `std::span<T>` for mutable. Prefer `std::span` at API boundaries; internal helpers may still take iterators.

#### Type-safe formatting — `std::format`

Prefer `std::format` over `sprintf`/string concatenation. It is type-safe, does not require a format string matching argument types, and avoids buffer management.

```cpp
// Wrong: format string must match types manually; buffer management is manual
char buf[256];
snprintf(buf, sizeof(buf), "offset=%lu size=%lu", offset, size_bytes);

// Right: types checked at compile time, no buffer
std::string msg = std::format("offset={} size={}", offset, size_bytes);
```

Use `std::format` for any string built from runtime values. Fall back to `snprintf` only when writing into a fixed-size C buffer owned by an external API (e.g., `CURLOPT_ERRORBUFFER`).

### Performance
- Pass large objects by const reference
- Use move semantics where appropriate
- Avoid unnecessary copies
- Profile before optimizing

## ABI, Layout, And Formatting

- Apply `clang-format` using the project configuration to every modified file.
- Do not expose object layout, compiler-specific types, standard-library ABI details, or inline implementation unintentionally across stable binary boundaries.
- Review changes to exported classes, virtual functions, base classes, data members, alignment, packing, calling convention, exception policy, and symbol visibility for ABI impact.
- Use fixed-width integer types and explicit byte order for wire and persisted formats; never serialize object memory directly unless a controlled ABI contract proves it valid.
- Prefer type-safe formatting such as `std::format` when supported; use fixed-buffer C formatting only at required external boundaries.

## Verification

- Run the project-native formatter, build, static analysis, and test commands first.
- Apply `clang-format` and run configured `clang-tidy`, compiler warnings, or `cppcheck` checks.
- Build every supported compiler, standard version, target, feature, and debug or release configuration affected by the change.
- Run unit and integration tests plus applicable AddressSanitizer, UndefinedBehaviorSanitizer, ThreadSanitizer, MemorySanitizer, or platform-equivalent analysis.
