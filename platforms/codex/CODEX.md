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

When implementing code:
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

## Review Routing

Use the right review path for the artifact under review:

- **Code review:** use the relevant language skill plus `skills/domains/testing/`, `skills/domains/code-quality/`, and `skills/domains/code-quality/references/code-review-checklist.md`. Do not use `skills/reviewer/` for code-level style, language idioms, tests, or implementation defects.
- **Architecture/design review:** use `skills/reviewer/`, `skills/workflows/architecture-review/`, `skills/domains/architecture/`, and `skills/domains/quality-attributes/`.
- **Workflow or command design review:** use the architecture/design review path and run the required field/path/invariant consistency pass from the design-doc workflow.

For code review findings, lead with defects and risks. If a finding identifies incorrect runtime behavior, include a `Required test:` line describing the triggering input or precondition and the asserted outcome.

## Implementation Discipline

Before coding, clarify requirements, constraints, performance expectations, and the relevant project patterns. Start from a small design or implementation outline, then make focused edits and verify each meaningful step.

For algorithms and data structures, explain the chosen approach and its time/space complexity when that affects correctness, scalability, or maintainability. Note real trade-offs and assumptions instead of hiding them in code comments.

Before finalizing implementation work, actively verify:
1. the changed code is syntactically valid for the target language
2. tests exercise concrete behavior and would fail for the intended bug, not merely check existence or call counts
3. the implementation matches the approved design or stated scope
4. no obvious security issue is introduced, including unsafe input handling or secret exposure
5. formatting, linting, and available tests have been run or the reason they could not be run is reported

## Comment And Review Hygiene

Comments explain why, not what. Inline comments are for hidden constraints, subtle invariants, external API quirks, and surprising behavior. Public-facing interfaces, types, enums, and central data structures should have short comments that clarify role, contract, ownership, lifetime, valid states, or constraints.

Never mention review process artifacts in code, comments, docstrings, or test names. Labels such as `Fix for finding H3`, `Assertion gap fix`, `Added per review`, or issue-specific review rounds belong in review notes or PR descriptions, not source files.

Every linter or static-analysis suppression must include a concrete reason. Prefer fixing the code when the warning identifies a real design issue.

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
- Do not leave comments, docstrings, or test names that refer to review findings, gap numbers, fix rounds, or review history.
