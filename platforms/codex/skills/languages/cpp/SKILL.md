---
name: cpp
description: C++ coding standards based on the C++ Core Guidelines. Use when writing, reviewing, or modifying C++ code to apply RAII, const correctness, memory safety, and modern C++ patterns.
---

# C++ Programming Skill

## Standards

Strictly follow the C++ Core Guidelines:
- https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines

## Key Principles

### Modern C++
- Use RAII for resource management
- Prefer smart pointers over raw pointers
- Use STL containers and algorithms
- Prefer `auto` where it improves readability
- Use `constexpr` for compile-time evaluation
- Prefer `{}` over `()` for variable initialization of user-defined types and smart pointers; `()` can be parsed as a function declaration. Exception: use `()` for standard library containers such as `std::string` and `std::vector` when the constructor is a fill or range constructor, because `{}` routes through `initializer_list` and can change semantics.
- Prefer static polymorphism over dynamic where practical

### Safety
- Avoid undefined behavior
- Use proper const correctness
- Initialize all variables
- Avoid C-style casts; use `static_cast`, `dynamic_cast`, and related casts explicitly
- Prefer range-based loops when they improve clarity

### Code Organization
- Use header guards or `#pragma once`
- Minimize header dependencies
- Forward declare where it meaningfully reduces coupling
- Keep headers narrow and readable

### Error Handling

#### Choose The Right Error Channel

| Situation | Mechanism |
|---|---|
| Operation may produce no result and no detail is needed | `std::optional<T>` |
| Binary pass/fail where the caller must branch | `[[nodiscard]] bool` |
| Multiple distinct failure modes the caller must dispatch on | `[[nodiscard]]` status enum |
| Value plus typed error reason in one return, when C++23 is available | `std::expected<T, E>` |
| Programmer error or violated invariant that cannot be recovered locally | Exception |

Treat I/O failures, network failures, and external API failures as expected outcomes, not exceptional control flow. Use exceptions only when they match the project's established style and represent truly exceptional or unrecoverable conditions.

If `std::expected<T, E>` is unavailable, use an existing project-native `Result`, `StatusOr`, or status-enum pattern. Do not introduce a new result wrapper for one feature unless it removes clear duplication and matches project conventions.

Use typed errors, status enums, or error codes for programmatic decisions. Human-readable strings are diagnostic detail; callers must not parse message text to decide control flow.

#### Caller-Handled Results

Apply `[[nodiscard]]` to every non-void function whose return value the caller must act on:
- Error-indicating `bool` returns
- Status or result enums
- Factory and query functions where the return value is the purpose of the call

When discarding such a return is genuinely intentional, cast to `void` and explain the reason:

```cpp
(void)flush();  // best-effort cleanup; result cannot affect shutdown
```

Callbacks and trampolines registered with external frameworks are exempt when the framework, rather than project code, consumes the return value.

`[[nodiscard]]` does not propagate from a virtual base declaration to overrides. Annotate every site explicitly when callers must act on the result: the base declaration, every override, and every test fake or mock that implements the interface.

#### Exception Boundaries

Do not allow exceptions to escape destructors, C callbacks, C ABI boundaries, thread entry points, or cleanup paths. Catch at those boundaries and convert the failure to the appropriate status/result/logging behavior with diagnostic context.

#### Output Parameters

Use references for required output parameters. A pointer implies that `nullptr` is valid and meaningful.

```cpp
// Avoid: pointer implies nullable.
bool checked_setopt(CURL* curl, CURLoption option, long value, std::string* detail);

// Prefer: reference communicates that detail is required.
bool checked_setopt(CURL* curl, CURLoption option, long value, std::string& detail);
```

Use a pointer only when the output argument is actually optional.

#### Error Detail Propagation

When chained operations share one error-detail string, pass a `std::string&` through the calls and let the first failure populate it:

```cpp
std::string detail;
if (!checked_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L, detail) ||
    !checked_setopt(curl, CURLOPT_CAINFO, ca_path, detail)) {
    LOGE("TLS setup failed: %s", detail.c_str());
    return error_result(detail);
}
```

Avoid allocating a new detail string per call in hot paths.

#### `errno` And System Calls

Capture `errno` immediately after the failing call; logging and helper calls may overwrite it.

```cpp
const int err = errno;
LOGE("open(%s) failed: %s", path, strerror(err));
```

Log enough context, such as function name, path, and relevant arguments, to diagnose the failure without reading the source.

### C++20 Patterns

#### Cooperative Cancellation

Prefer `std::stop_token`, `std::stop_source`, and `std::jthread` over raw `std::atomic<bool>` cancellation flags when a thread must be stopped from the outside.

```cpp
std::jthread worker([](std::stop_token token) {
    while (!token.stop_requested()) {
        // Work until cancellation is requested.
    }
});
```

Keep `std::atomic<bool>` cancellation flags only at C or external-framework boundaries where a `std::stop_token` cannot be passed through the callback contract.

#### Buffer Views

Prefer `std::span<T>` over raw pointer plus size pairs at API boundaries. Spans carry length, work with range-based loops and STL algorithms, and prevent caller-side length mismatches.

```cpp
void process(std::span<const std::byte> payload);
```

Use `std::span<const T>` for read-only views and `std::span<T>` for mutable views.

#### Type-Safe Formatting

Prefer `std::format` for strings built from runtime values when the project toolchain supports it. Fall back to `snprintf` only when writing into a fixed-size C buffer owned by an external API.

### Performance
- Pass large objects by const reference unless ownership transfer is intended
- Use move semantics where appropriate
- Avoid unnecessary copies
- Profile before optimizing

## Workflow

- Format with the project's C++ formatter, typically `clang-format`
- Run available static analysis, typically `clang-tidy`
- Use `testing` and `code-quality` skills alongside this skill when writing or reviewing code

## References

- C++ Core Guidelines: https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
