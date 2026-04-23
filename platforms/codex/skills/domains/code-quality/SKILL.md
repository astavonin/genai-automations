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
- Choose clear names over explanatory comments

### Comments

Use comments for:
- non-obvious design intent
- complex algorithms where the approach is not immediately clear
- TODOs with enough context to act on them later
- test scenario setup where the behavior being exercised is otherwise hard to follow
- public API documentation when required by the language or project

Avoid comments that restate the code.

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
