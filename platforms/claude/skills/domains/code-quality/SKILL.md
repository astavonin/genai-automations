---
name: code-quality
description: Code quality principles covering comments, linter suppressions, and formatting. Use when writing or reviewing any code to enforce self-documenting style, suppression comment requirements, and formatting rules.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: domains
  tags: [code-quality, linting, formatting, comments]
---

# Code Quality Skill

## Core Principles

### Self-Documenting Code
- Write code that needs minimal comments
- Before adding a comment, reevaluate: why is the code unclear?
- Use clear, descriptive names for variables, functions, and classes
- Keep functions focused and small

### Comment Policy

This section is the comment policy. It applies whenever code is written or changed — there is no separate commenting pass to defer to.

**Tier 1 — WHY-only inline comments.** Add a comment only when the WHY is non-obvious: a hidden constraint, a subtle invariant, a workaround for a specific bug, or behavior that would surprise a careful reader. Never explain WHAT — self-documenting names do that. One short line max; if removing it would not confuse a future reader, omit it.

**Tier 2 — Public API documentation.** Every public class, interface, enum, non-trivial public type alias, and non-obvious public constant must have a concise comment. One line max per symbol — no paragraphs, no `@param`/`@return` blocks unless the project already uses Doxygen. Skip symbols whose names are already self-documenting and carry no non-obvious contract; trivial accessors are exempt.

| Symbol kind | Scope | Comment style | Content |
|---|---|---|---|
| Class / struct (non-trivial) | Public or file-scope | Line above declaration | Purpose and key invariant or ownership rule |
| Interface / abstract class | Public | Line above declaration | Contract: what implementors must guarantee |
| Public method | Non-obvious purpose | Line above declaration | What it does and any preconditions/postconditions |
| Enum | Public | Line above declaration | What the enum represents |
| Enum value | Non-obvious meaning | Trailing `//` | Semantics, especially error codes and sentinel values |
| Public constant | Non-obvious | Trailing `//` | What it controls and why this value |
| `using` / `typedef` (public) | Non-obvious alias | Line above | What the alias represents and why it exists |

### What to Avoid in Comments

Don't use comments for:
- Usage examples (tests document usage)
- Complexity notes (simplify the code instead)
- Responsibility lists (code structure shows this)
- Obvious information (what the code already says)
- Multi-line prose blocks or `@param`/`@return` boilerplate (unless the project uses Doxygen/Sphinx consistently)

## Linter Suppressions

**CRITICAL RULE:** ALWAYS add a comment explaining WHY when suppressing linter warnings.

**Fix instead of suppress when:** the warning points to a genuine design issue; the fix is as easy as the suppression; multiple suppressions of the same rule exist; or the code can be simply rewritten. Suppress only for: hardware/low-level unavoidable casts, external protocol constants, API boundary matching, third-party library limitations, or justified legacy debt (with issue reference).

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
