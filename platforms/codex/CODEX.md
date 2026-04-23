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

When implementing or reviewing code, skill selection is explicit:
- C++ request: MUST use `skills/languages/cpp/`
- Python request: MUST use `skills/languages/python/`
- Go request: MUST use `skills/languages/go/`
- Any code-writing, code-modification, or code-review task: MUST use `skills/domains/quality-attributes/`
- Any test-writing or test-review task: ALSO use `skills/domains/testing/`
- Any code-writing or code-review task: ALSO use `skills/domains/code-quality/`

Do not rely on generic coding behavior when one of the language skills matches the request.
If a task spans multiple covered languages, use each corresponding language skill for the relevant files.
Treat `skills/domains/quality-attributes/` as a development-time constraint, not only a review aid.
During implementation, make trade-offs against supportability, extendability, maintainability, testability, performance, safety, security, and observability explicit in the code and validation approach where relevant.

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
- For code changes, always develop against the eight quality attributes, not just language style rules.
- For code changes, apply the project's formatter and use the project's test and lint tooling when available.
