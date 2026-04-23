---
name: code-quality
description: Code quality principles covering comments, linter suppressions, and formatting. Use when writing or reviewing code to enforce self-documenting style, justified suppressions, and project-standard formatting.
---

# Code Quality Skill

## Core Principles

### Self-Documenting Code
- Prefer code that needs minimal comments
- Use comments to explain why, not what
- Keep functions focused
- Choose clear names over explanatory comments

### Comments

Use comments for:
- non-obvious design intent
- complex algorithms where the approach is not immediately clear
- TODOs with enough context to act on them later
- test scenario setup where the behavior being exercised is otherwise hard to follow

Avoid comments that restate the code.

## Linter Suppressions

Always explain why a suppression is necessary.

Examples:
- C++: `// NOLINTNEXTLINE(rule-name): reason`
- Python: `# noqa: rule-name - reason`
- Go: `//nolint:rule-name // reason`

Prefer fixing the code instead of suppressing the warning when the warning points to a real design issue.

## Formatting

Apply the project's formatter to every modified file.

- C++: `clang-format`
- Python: `black` or project equivalent
- Go: `gofmt` or `goimports`

## Checklist

- Code is readable without excessive comments
- Comments explain intent where needed
- Suppressions are justified
- Formatting has been applied
