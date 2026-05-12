# Scope

Codex is used for architecture/design work and for implementation work in selected languages.

Active implementation focus:
- C++
- Python
- Go

Keep the scope narrow to these languages unless explicitly expanded.

# Communication Style

- Focus on technical accuracy and consistency.
- Prefer clear interfaces, explicit invariants, and concrete files/paths.
- Be concise, but do not omit required interface or enforcement details.

# Design Doc Workflow

Use `skills/architecture-research-planner/` when producing or updating design documents.

## Required Outcomes

Every command/workflow design doc should make these items explicit when relevant:
- command or workflow entry point
- required request fields
- outputs
- writable paths or mutation rules
- enforcement mechanism for hard invariants
- validation and failure behavior
- at least one worked example or canonical template

## Mandatory Consistency Pass

Before finalizing a design doc, verify that every introduced field, flag, path, or invariant appears in all relevant places:
1. interface or request section
2. runtime behavior section
3. validation/failure section
4. canonical template or example
5. enforcement description when the rule is hard

# Coding Workflow

When implementing or reviewing code:
- use `skills/languages/cpp/` for C++
- use `skills/languages/python/` for Python
- use `skills/languages/go/` for Go
- use `skills/domains/testing/` when writing or reviewing tests
- use `skills/domains/code-quality/` for comments, suppressions, and formatting expectations
- for C++, treat recoverable I/O, network, and external API failures as explicit typed return outcomes; mark caller-handled non-void results `[[nodiscard]]`; keep diagnostics separate from error semantics; catch exceptions at C/ABI/thread/cleanup boundaries
- document all main interfaces, types, and data structures with short explanatory comments that clarify role, invariants, or constraints; do not add placeholder comments
- keep functions and methods at or below 80 lines where practical; never create or leave a modified function over 100 lines
- cover public API paths, distinct failure modes, edge cases, and behavioral correctness scenarios with concrete tests
- when a review finding identifies incorrect runtime behavior, include a `Required test:` line describing what input or precondition triggers the bug and what outcome the test asserts

Prefer language-idiomatic solutions, explicit validation, and project-native tooling.

# Active Skills

- `skills/architecture-research-planner/`
- `skills/workflows/architecture-review/`
- `skills/reviewer/`
- `skills/domains/architecture/`
- `skills/domains/quality-attributes/`
- `skills/domains/testing/`
- `skills/domains/code-quality/`
- `skills/languages/cpp/`
- `skills/languages/python/`
- `skills/languages/go/`

# Critical Rules

- Do not let prompt wording stand in for runtime enforcement when a hard invariant is required.
- Separate confirmed facts from proposed behavior.
- For workflow docs, ensure request fields, templates, and examples stay aligned.
- For code changes, apply the project's formatter and use the project's test and lint tooling when available.
- Do not accept happy-path-only tests for code paths that can fail; missing failure-scenario coverage is a correctness gap.
- Do not rely on vacuous assertions such as non-null checks, existence checks, or call counts without verifying concrete behavior.
