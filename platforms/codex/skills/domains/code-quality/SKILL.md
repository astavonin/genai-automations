---
name: code-quality
description: Code quality principles covering comments, linter suppressions, and formatting. Use when writing or reviewing code to enforce self-documenting style, justified suppressions, and project-standard formatting.
---

# Code Quality Skill

Use this skill when writing or reviewing code in the narrowed Codex scope.

## Core Principles

### Self-Documenting Code
- Prefer code that needs minimal comments
- Re-evaluate code structure before adding explanatory comments
- Use comments to explain why, not what
- Keep functions focused
- Keep functions and methods at or below 80 lines where practical
- Do not create or leave a modified function or method over 100 lines
- Choose clear names over explanatory comments

### Function Size

Treat 80 physical lines as the target maximum for functions and methods. When a function grows past that, first look for coherent helpers, smaller data transformations, or clearer control-flow boundaries.

Treat 100 physical lines as a hard ceiling for new or modified functions and methods. If an existing function already exceeds 100 lines and must be touched, split it or reduce it as part of the change; do not make it longer.

### Comments

Use comments for:
- all main interfaces, types, and data structures, using short notes that clarify purpose, invariants, ownership, lifetime, valid states, or usage constraints
- non-obvious design intent
- complex algorithms where the approach is not immediately clear
- TODOs with enough context to act on them later
- test scenario setup where the behavior being exercised is otherwise hard to follow
- public API documentation when required by the language or project

Avoid comments that restate the code or exist only to satisfy a comment quota.

## Linter Suppressions

Always explain why a suppression is necessary. Prefer fixing the code instead when the warning points to a real design issue.

Examples:
- C++: `// NOLINTNEXTLINE(rule-name): reason`
- Python: `# noqa: rule-name - reason` or `# type: ignore[error-code]  # reason`
- Go: `//nolint:rule-name // reason`

## Formatting

Apply the project's formatter to every modified file.

- C++: `clang-format`
- Python: `black` or project equivalent
- Go: `gofmt` or `goimports`

## Review Heuristics

- Prefer concrete findings over style-only commentary.
- Raise style feedback only when it affects readability, maintainability, or project consistency.
- Treat unexplained suppressions, stale comments, and missing formatting as quality defects.

## Reference Checklist

Use `references/code-review-checklist.md` for the narrowed code-quality review checklist.

## References

Use the reference docs for the detailed operating rules:
- `references/comments.md`
- `references/linter-suppressions.md`
- `references/formatting.md`
