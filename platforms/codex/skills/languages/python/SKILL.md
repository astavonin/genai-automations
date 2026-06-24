---
name: python
description: Python implementation and review guidance for typed, idiomatic, maintainable, and supportable code. Use when writing, modifying, debugging, or reviewing Python modules, public APIs, asynchronous code, packaging, dependencies, and tests.
---

# Python Programming Skill

Treat this file as the Python-specific contract. Apply the shared `code-quality` and `testing` skills for structure, lifecycle, concurrency, observability, dependencies, I/O, compatibility, and test coverage.

## Language And Project Contract

- Inspect `pyproject.toml`, lockfiles, supported Python versions, type-checker configuration, package layout, and project-native commands before editing.
- Preserve the project's formatter, import, docstring, typing, exception, and packaging conventions.
- Keep imports free of unexpected process, network, filesystem, registration, or configuration side effects.
- Put executable entry behavior behind an explicit function and `if __name__ == "__main__":` where direct execution is supported.

## Types And APIs

- Type public and non-trivial function signatures, important attributes, callbacks, and generic boundaries.
- Avoid introducing `Any` merely to silence the type checker; contain unavoidable dynamic values at validated boundaries.
- Use `Protocol` for genuine structural contracts and abstract base classes only when runtime identity or shared implementation is required.
- Keep generics and overloads proportionate; prefer a clear concrete API over type-level cleverness.
- Use `None` only when absence is part of the contract; use a private sentinel when omitted and explicitly-null have different meanings.
- Use enums or typed configuration objects instead of boolean-heavy or loosely structured dictionaries at stable boundaries.
- Use dataclasses, named tuples, typed dictionaries, or project-standard models according to mutability, validation, and serialization needs.
- Never use mutable objects as default argument values; create them inside the function or with a factory.
- Keep public return shapes stable and avoid leaking implementation-only third-party types.

## Pythonic Resource And Data Handling

- Prefer context managers for resources and transactions; implement context management when ownership naturally has scoped acquisition and release.
- Prefer returned values over output mutation. Mutate caller-owned containers only when the API explicitly communicates in-place behavior.
- Use iterators and generators for streaming or potentially large data, but document one-shot consumption and cleanup behavior.
- Use `pathlib.Path` or `os.PathLike` for filesystem APIs and preserve platform-native path semantics.
- Use timezone-aware timestamps at external boundaries and make units explicit for durations and numeric values.
- Preserve the distinction between text and bytes; decode and encode only at explicit boundaries with defined error behavior.

## Exceptions And Cleanup

- Raise specific exception types with actionable messages and safe context.
- Preserve causality with exception chaining when translating failures; use `raise ... from ...` deliberately.
- Catch the narrowest exception set at the first layer that can recover, translate, or report meaningfully.
- Avoid bare `except`, broad `except Exception` around large regions, and silent exception swallowing.
- Re-raise cancellation and termination exceptions after required cleanup; do not convert them into ordinary success or retry.
- Use `finally` only when cleanup cannot be expressed safely with a context manager.
- Context-manager exit methods should propagate exceptions unless deliberate suppression is part of the documented contract.
- Do not let `__del__` perform required, fallible, or blocking cleanup; provide explicit `close` or context management.
- Make intentionally ignored return values or cleanup failures explicit and justified.

## Async And Concurrency

- Await every owned task or transfer it to a documented supervisor; retain references so task failures are observable.
- Prefer structured concurrency such as the project's task-group mechanism when supported.
- Propagate cancellation and deadlines through async call chains and preserve invariants at every cancellation point.
- Keep blocking I/O and CPU-heavy work off the event-loop thread using project-approved executors or worker processes.
- Do not hold synchronous locks across `await` or mix threading and async synchronization without a documented boundary.
- Use processes, threads, and async tasks according to workload and runtime constraints; do not assume the GIL provides application-level synchronization.

## Imports, Packaging, And Compatibility

- Use explicit imports and avoid wildcard imports outside deliberate package re-export surfaces.
- Keep package boundaries cohesive and avoid circular imports, import-time service locators, and mutable module-level singletons.
- Preserve public module paths, call signatures, exception contracts, serialization shapes, CLI behavior, and supported Python versions according to project compatibility policy.
- Deprecate public APIs before removal and provide a migration path when compatibility is promised.
- Keep `pyproject.toml`, dependency metadata, extras, entry points, package data, and lockfiles intentional and internally consistent.
- Put imports under `TYPE_CHECKING` only when they are needed solely for static analysis and runtime annotation evaluation cannot require them.
- Pass argument sequences to subprocess APIs and avoid `shell=True`; when a shell is required, validate inputs and document the trust boundary.

## Verification

- Run project-native formatting, linting, typing, packaging, and test commands first.
- Run the configured formatter and import sorter, then the configured linter.
- Run strict-enough `mypy`, `pyright`, or project-equivalent analysis over affected packages and tests.
- Run unit and integration tests on affected supported Python versions and dependency or optional-extra combinations.
- Build distributions and validate imports, entry points, package data, and metadata when packaging changes.
- Run configured security, dependency, and compatibility checks.
