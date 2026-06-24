---
name: cpp
description: C++ implementation and review guidance for safe, modern, maintainable, and supportable code. Use when writing, modifying, debugging, or reviewing C++ source, public APIs, ownership, concurrency, ABI boundaries, build configurations, and tests.
---

# C++ Programming Skill

Treat this file as the C++-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, concurrency, observability, dependencies, I/O, compatibility, and test coverage.

## Language And Build Contract

- Inspect build files, presets, dependency manifests, generated-code policy, configured C++ standard, supported compilers and standard libraries, warning policy, sanitizers, targets, and project-native commands before editing.
- Use only language and library features supported by the project's declared standard and toolchain matrix. Do not raise the minimum standard or compiler requirement incidentally.
- Preserve project ABI, exception, RTTI, allocation, visibility, and static-versus-shared linkage policy.
- Keep compiler extensions and feature-test fallbacks narrow, explicit, and covered by supported configurations.

## Modern C++ And Ownership

- Use RAII for every acquired resource.
- Prefer values and standard containers; use smart pointers only when heap allocation or shared ownership is required.
- Use `std::unique_ptr` for single ownership and `std::shared_ptr` only for genuine shared lifetime. Use `std::weak_ptr` to break ownership cycles.
- Keep raw pointers and references non-owning unless an external API requires otherwise; document exceptional ownership transfer.
- Prefer the Rule of Zero; when special members are necessary, define or delete copy and move behavior consistently.
- Prefer standard library containers, algorithms, views, and utilities over custom equivalents.
- Prefer `auto` where it improves readability without hiding important type or ownership information.
- Use `constexpr` when compile-time evaluation improves correctness or removes runtime work without obscuring intent. Use `consteval` only when the supported standard and immediate-function semantics require it.
- Prefer static polymorphism when it materially simplifies ownership or performance; do not introduce templates merely to avoid a justified virtual interface.
- Initialize every object and avoid C-style casts. Use the narrowest explicit C++ cast that expresses the conversion.
- Apply const correctness to values, pointees, methods, and views; do not use `const` where it falsely implies deep immutability.
- Use `nullptr`, scoped `enum class`, and `override`; use `final` only when extension is intentionally prohibited.
- Avoid undefined behavior, dangling views, invalidated iterators, object slicing, strict-aliasing violations, and signed-overflow assumptions.
- Mark functions `noexcept` only when the contract is guaranteed, and preserve non-throwing move and destruction where containers and cleanup depend on it.
- Prefer `{}` for ordinary user-defined and smart-pointer initialization. Use `()` for standard-library fill or range constructors when braces would select `initializer_list` and change semantics.

## Headers, Modules, And Interfaces

- Keep headers narrow, self-contained, and protected with `#pragma once` or header guards.
- Minimize includes and use forward declarations only when they genuinely reduce coupling without making ownership or completeness rules fragile.
- Keep implementation details out of exported headers; use internal translation units or PImpl when ABI stability or compile-time isolation justifies it.
- Keep templates and inline definitions focused because they increase compile cost and expose implementation to consumers.
- Prefer returned values over output parameters when the result naturally forms one object.
- Use references for required output parameters; use pointers only when `nullptr` is a meaningful optional state.

## Error Channels

Choose the channel from caller needs:

| Situation | Mechanism |
|---|---|
| No result is expected and no reason is required | `std::optional<T>` |
| Binary pass/fail requires caller action | `[[nodiscard]] bool` |
| Caller branches over distinct failures | `[[nodiscard]]` status enum |
| Value plus typed failure, when available | `std::expected<T, E>` |
| Violated programmer invariant or project-defined exceptional failure | Exception or assertion according to project policy |

- Treat normal I/O, network, parsing, validation, and external API failures as explicit outcomes rather than exceptional control flow.
- Use the project-native `Result`, `StatusOr`, status enum, or expected-like type when `std::expected` is unavailable; do not invent a one-off result wrapper.
- Keep diagnostics separate from typed error semantics and never parse error strings for control flow.
- Apply `[[nodiscard]]` at every declaration and override whose result callers must act on, including test fakes and mocks.
- Make intentional discard explicit and justified, for example `(void)flush();  // best-effort cleanup`.
- Capture `errno` or equivalent OS error state immediately after the failing call before logging or helper calls can overwrite it.
- Include safe operation, resource, and argument context in the propagated error or boundary diagnostic.

## Exceptions, Cleanup, And Boundaries

- Do not allow exceptions to escape destructors, C callbacks, C ABI boundaries, thread entry points, or cleanup paths.
- Keep destructors non-throwing, bounded, and non-blocking where practical.
- Provide explicit result-bearing `close`, `flush`, or `shutdown` methods when cleanup can fail or wait for completion; let the destructor perform best-effort fallback cleanup.
- Define destruction and shutdown order for dependent members, threads, callbacks, and external handles.
- Catch exceptions at the first boundary that can translate them into the required status, diagnostic, or termination policy without losing context.

## Concurrency And Views

- Prefer `std::jthread`, `std::stop_token`, and `std::stop_source` for owned cooperative cancellation when the supported standard and toolchain provide them.
- Keep raw atomic cancellation flags for C or external callback boundaries where stop tokens cannot pass through the contract.
- Join or otherwise observe every owned thread; never allow a joinable `std::thread` to reach destruction.
- State memory order explicitly for non-trivial atomics and justify anything weaker than sequential consistency.
- Prefer `std::span<const T>` and `std::span<T>` over raw pointer-size pairs for bounded read-only and mutable views when supported; otherwise use the project-standard bounded-view abstraction.
- Prefer `std::string_view` only when the referenced character storage clearly outlives the view.

## Formatting, Layout, And ABI

- Prefer type-safe formatting such as `std::format` when supported; use fixed-buffer C formatting only at required external boundaries.
- Do not expose object layout, compiler-specific types, standard-library ABI details, or inline implementation unintentionally across stable binary boundaries.
- Review changes to exported classes, virtual functions, base classes, data members, alignment, packing, calling convention, exception policy, and symbol visibility for ABI impact.
- Use fixed-width integer types and explicit byte order for wire and persisted formats; never serialize object memory directly unless a controlled ABI contract proves it valid.

## Verification

- Run the project-native formatter, build, static analysis, and test commands first.
- Apply `clang-format` and run configured `clang-tidy`, compiler warnings, or `cppcheck` checks.
- Build every supported compiler, standard version, target, feature, and debug or release configuration affected by the change.
- Run unit and integration tests plus applicable AddressSanitizer, UndefinedBehaviorSanitizer, ThreadSanitizer, MemorySanitizer, or platform-equivalent analysis.
- Verify exported ABI or API compatibility with project tooling when the change affects a supported boundary.
