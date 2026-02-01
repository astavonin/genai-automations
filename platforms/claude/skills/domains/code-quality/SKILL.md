---
name: code-quality
description: Code quality principles and standards
---

# Code Quality Skill

## Core Principles

### Self-Documenting Code
- Write code that needs minimal comments
- Before adding a comment, reevaluate: why is the code unclear?
- Use clear, descriptive names for variables, functions, and classes
- Keep functions focused and small

### When Comments Are Necessary

Use comments for:
- **Classes:** 1-2 line summary of purpose
- **Methods:** Inline purpose if non-obvious
- **TODOs:** For future work (with issue reference if possible)
- **Tests:** Describe the test case scenario
- **Complex algorithms:** Explain the approach, not the syntax

### What to Avoid in Comments

Don't use comments for:
- Usage examples (tests document usage)
- Complexity notes (simplify the code instead)
- Responsibility lists (code structure shows this)
- Obvious information (what the code already says)

## Linter Suppressions

**CRITICAL RULE:** ALWAYS add a comment explaining WHY when suppressing linter warnings.

### Format

```
// NOLINTNEXTLINE(rule-name): Reason why suppression is needed
```

### Language-Specific Suppressions

- **C++:** `// NOLINTNEXTLINE(rule-name): reason`
- **Python:** `# noqa: rule-name - reason` or `# type: ignore - reason`
- **Go:** `//nolint:rule-name // reason`
- **Rust:** `#[allow(clippy::rule_name)] // reason`
- **JavaScript/TypeScript:** `// eslint-disable-next-line rule-name -- reason`

### Example

```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast): Hardware register access requires reinterpret_cast
auto* reg = reinterpret_cast<volatile uint32_t*>(0x40000000);
```

## Code Formatting

**Apply formatting using the current project's formatting tool for all files you create or modify.**

### Language-Specific Tools

- **C++:** clang-format
- **Python:** black, autopep8
- **Go:** gofmt, goimports
- **Rust:** rustfmt
- **Zig:** zig fmt
- **JavaScript/TypeScript:** prettier

### Workflow

1. Write code
2. Apply formatter before commit
3. Ensure CI enforces formatting

## Code Quality Checklist

- [ ] Code is self-documenting
- [ ] Clear, descriptive names
- [ ] Functions are focused and small
- [ ] Comments explain WHY, not WHAT
- [ ] All linter suppressions have explanations
- [ ] Formatting applied
- [ ] No commented-out code
- [ ] No TODO without context

## References

See `references/` directory for:
- Detailed comment philosophy
- Linter suppression guidelines
- Formatting configuration examples
