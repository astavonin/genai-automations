---
name: comment
description: Add comments to code following the project comment policy — WHY-only inline comments plus public API documentation (interfaces, classes, types, enums).
allowed-tools: Bash, Read, Edit, LSP
---

# Comment Command

Apply the full comment policy to the specified files (or all changed files if no arguments given).

## Setup

Read the comment policy before starting:
```
Read ~/.claude/skills/domains/code-quality/SKILL.md
```

## Identify Target Files

**If arguments provided:** operate only on the listed files.

**If no arguments:** identify changed files relative to master:
```bash
git diff origin/master...HEAD --name-only
# Also include unstaged and untracked files:
git diff --name-only
git ls-files --others --exclude-standard
```

Restrict to source files only (`.cc`, `.cpp`, `.h`, `.hpp`, `.py`, `.go`, `.rs`, `.zig`). Skip generated files, build artifacts, and test fixtures.

## Actions (Execute in Order per File)

### 1. Read the file

Read the full file before making any edits.

### 2. Apply WHY-only inline comments

Add a comment **only** when the WHY is non-obvious to a careful reader:
- A hidden constraint (e.g. raw pointer lifetime, multi-thread signal, overflow guard)
- A subtle invariant (e.g. ordering dependency, cumulative vs. session count)
- A workaround for a specific bug or library quirk
- Behavior that would surprise a reader (e.g. early-rejection via callback return value)

**Do NOT add** comments that explain WHAT the code does. If removing the comment would not confuse a future reader, do not write it. One short line per comment, no multi-line blocks.

### 3. Add public API documentation

For **every** public-facing symbol, add a concise comment if one is missing:

| Symbol kind | Scope | Comment style | Content |
|---|---|---|---|
| Class / struct (non-trivial) | Public or file-scope | Line above declaration | Purpose and key invariant or ownership rule |
| Interface / abstract class | Public | Line above declaration | Contract: what implementors must guarantee |
| Public method | Non-obvious purpose | Line above declaration | What it does and any preconditions/postconditions |
| Enum | Public | Line above declaration | What the enum represents |
| Enum value | Non-obvious meaning | Trailing `//` | Semantics, especially error codes and sentinel values |
| Public constant | Non-obvious | Trailing `//` | What it controls and why this value |
| `using` / `typedef` (public) | Non-obvious alias | Line above | What the alias represents and why it exists |

**Skip** symbols whose names are already completely self-documenting and have no non-obvious contract. One line max per symbol — no paragraphs, no `@param`/`@return` blocks unless the project already uses Doxygen.

**Accessor methods** (trivial getters/setters with no logic) do not need comments.

### 4. Re-run lint on edited files

After all edits, re-run the project linter on every modified file to verify no regressions:

```bash
# C++ (project-specific):
./dev.sh lint --cpp <file1> <file2> ...

# Python:
./dev.sh lint --python <file>

# Shell:
./dev.sh lint --shell <file>
```

Fix any lint errors introduced by the edits before finishing.

## Rules

- **Never explain WHAT** — self-documenting names already do that
- **One line per comment** — no multi-line prose blocks
- **No docstring boilerplate** — no `@param`, `@return`, `@throws` unless the project uses Doxygen/Sphinx consistently
- **No TODO comments** unless the user explicitly asks
- **No commented-out code**
- Comments must survive a future rename without becoming false — describe contracts and invariants, not callers or current-state details

## Output

Report a brief summary: files edited, number of comments added per file, and lint result.
