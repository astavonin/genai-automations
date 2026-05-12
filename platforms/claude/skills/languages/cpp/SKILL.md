---
name: cpp
description: C++ coding standards based on the C++ Core Guidelines. Use when writing, reviewing, or modifying C++ code to apply RAII, const correctness, memory safety, and modern C++ patterns.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: languages
  tags: [cpp, c++, programming]
---

# C++ Programming Skill

## Standards

**Strictly follow The C++ Core Guidelines:**
- https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines

## Key Principles

### Modern C++
- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Use STL containers and algorithms
- Prefer `auto` for type deduction where it improves readability
- Use `constexpr` for compile-time evaluation
- Prefer static polymorphism over dynamic

### Safety
- Avoid undefined behavior
- Use proper const correctness
- Initialize all variables
- Avoid C-style casts (use static_cast, dynamic_cast, etc.)
- Use range-based for loops

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

## Formatting

Apply clang-format using project configuration.

## Static Analysis

Run clang-tidy for code quality checks.

## References

- C++ Core Guidelines: https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
