---
name: code-quality
description: Code quality principles covering comments, linter suppressions, formatting, and review hygiene. Use when writing or reviewing code to enforce self-documenting style, justified suppressions, and project-standard formatting.
---

# Code Quality Skill

Use this skill when writing or reviewing code in the narrowed Codex scope.

## Core Principles

### Self-Documenting Code
- Prefer code that needs minimal comments
- Re-evaluate code structure before adding explanatory comments
- Use comments to explain why, not what
- Use clear, descriptive names instead of explanatory comments
- Keep functions focused
- Keep functions and methods at or below 80 lines where practical
- Do not create or leave a modified function or method over 100 lines

### Function Size

Treat 80 physical lines as the target maximum for functions and methods. When a function grows past that, first look for coherent helpers, smaller data transformations, or clearer control-flow boundaries.

Treat 100 physical lines as a hard ceiling for new or modified functions and methods. If an existing function already exceeds 100 lines and must be touched, split it or reduce it as part of the change; do not make it longer.

### Comment Policy

Use a two-tier comment policy:

1. Inline comments explain WHY only. Add one only for hidden constraints, subtle invariants, specific external API quirks, workarounds, or behavior that would surprise a careful reader. Keep inline comments to one short line when possible.
2. Public API documentation explains contracts. Main interfaces, public or exported types, enums, non-trivial type aliases, central data structures, and non-obvious constants should have short comments that clarify purpose, invariants, ownership, lifetime, valid states, or usage constraints.

Use comments for:
- non-obvious design intent
- complex algorithms where the approach is not immediately clear
- test scenario setup where the behavior being exercised is otherwise hard to follow
- TODOs only when they are actionable and include enough context, such as an issue reference or concrete follow-up

Do not use comments for:
- restating what the code already says
- usage examples that should live in tests or docs
- complexity notes that should be solved by refactoring
- responsibility lists that code structure should already show
- placeholder text added only to satisfy a comment quota
- multi-line prose blocks or `@param`/`@return` boilerplate unless the project consistently uses that documentation format
- commented-out code

Never reference review findings, gap numbers, fix rounds, or review history in comments, docstrings, or test names. Labels like `Fix for finding H3`, `Assertion gap fix`, or `Added per review` are review-process metadata; source code and tests must describe behavior and contracts.

## Linter Suppressions

Always explain why a suppression is necessary. Prefer fixing the code instead when the warning points to a real design issue, the fix is as easy as the suppression, or the same rule is being suppressed repeatedly.

Examples:
- C++: `// NOLINTNEXTLINE(rule-name): reason`
- Python: `# noqa: rule-name - reason` or `# type: ignore[error-code]  # reason`
- Go: `//nolint:rule-name // reason`

Accept suppressions only for narrow, justified cases such as hardware or low-level constraints, external protocol constants, required API-boundary compatibility, third-party library limitations, or legacy debt with a follow-up reference.

## Formatting

Apply the project's formatter to every modified file.

- C++: `clang-format`
- Python: `black` or project equivalent
- Go: `gofmt` or `goimports`

## Review Heuristics

- Prefer concrete findings over style-only commentary.
- Raise style feedback only when it affects readability, maintainability, or project consistency.
- Treat unexplained suppressions, stale comments, review-process labels in source, commented-out code, and missing formatting as quality defects.

## Reference Checklist

Use `references/code-review-checklist.md` for the narrowed code-quality review checklist.

## References

Use the reference docs for the detailed operating rules:
- `references/comments.md`
- `references/linter-suppressions.md`
- `references/formatting.md`
