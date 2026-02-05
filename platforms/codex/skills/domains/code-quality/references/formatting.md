# Code Formatting Guidelines

## Core Principle

**Apply formatting using the current project's formatting tool for all files you create or modify.**

## Language-Specific Tools

### C++
- **Tool:** clang-format
- **Config:** `.clang-format` in project root
- **Usage:** `clang-format -i <file>`
- **Common styles:** LLVM, Google, Chromium, Mozilla, WebKit

### Python
- **Tool:** black (opinionated) or autopep8 (configurable)
- **Config:** `pyproject.toml` or `setup.cfg`
- **Usage:** `black <file>` or `autopep8 --in-place <file>`
- **Line length:** 79 (PEP 8) or 88 (black default)

### Go
- **Tool:** gofmt or goimports (gofmt + import management)
- **Config:** None needed (enforced standard)
- **Usage:** `gofmt -w <file>` or `goimports -w <file>`
- **Note:** Non-negotiable in Go community

### Rust
- **Tool:** rustfmt
- **Config:** `rustfmt.toml` in project root
- **Usage:** `cargo fmt` or `rustfmt <file>`
- **Styles:** Configurable via rustfmt.toml

### Zig
- **Tool:** zig fmt
- **Config:** Built-in (no configuration)
- **Usage:** `zig fmt <file>`
- **Note:** Enforced by compiler toolchain

### JavaScript/TypeScript
- **Tool:** prettier
- **Config:** `.prettierrc` in project root
- **Usage:** `prettier --write <file>`
- **Alternative:** ESLint with formatting rules

### Shell
- **Tool:** shfmt
- **Config:** Command-line options or .editorconfig
- **Usage:** `shfmt -w <file>`
- **Common:** 2-space indentation, simplify syntax

## When to Apply Formatting

### During Development
1. Before committing changes
2. After making edits
3. When touching existing files

### In CI/CD
- Run formatter in check mode
- Fail builds if formatting differs
- Optional: Auto-format and commit

## Formatting in Editors

### VS Code
```json
{
  "editor.formatOnSave": true,
  "[cpp]": {
    "editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"
  },
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter"
  },
  "[go]": {
    "editor.defaultFormatter": "golang.go"
  },
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer"
  }
}
```

### Vim/Neovim
```vim
" Format on save
autocmd BufWritePre *.cpp,*.h :silent! execute '!clang-format -i %'
autocmd BufWritePre *.py :silent! execute '!black %'
autocmd BufWritePre *.go :silent! execute '!goimports -w %'
autocmd BufWritePre *.rs :silent! execute '!rustfmt %'
```

### Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/mirrors-clang-format
    rev: v14.0.0
    hooks:
      - id: clang-format
  - repo: https://github.com/psf/black
    rev: 23.1.0
    hooks:
      - id: black
  - repo: https://github.com/golangci/golangci-lint
    rev: v1.51.0
    hooks:
      - id: golangci-lint
```

## Project Configuration Examples

### C++ (.clang-format)
```yaml
BasedOnStyle: LLVM
IndentWidth: 4
ColumnLimit: 100
PointerAlignment: Left
AllowShortFunctionsOnASingleLine: Inline
```

### Python (pyproject.toml)
```toml
[tool.black]
line-length = 88
target-version = ['py310']
include = '\.pyi?$'
```

### Rust (rustfmt.toml)
```toml
max_width = 100
tab_spaces = 4
edition = "2021"
```

## Handling Existing Code

### Gradual Formatting
1. Format only files you modify
2. Avoid pure formatting commits (mixes history)
3. Consider separate "mass reformat" commit

### Mass Reformatting
If doing project-wide reformat:
1. Create dedicated commit
2. Run formatter on all files
3. Document in commit message
4. Tag commit for git-blame ignore

```bash
# .git-blame-ignore-revs
# Mass reformatting commit
abc123def456...
```

## Exceptions

Some code may need special handling:
- Generated code (mark with comment)
- Embedded data/tables
- ASCII art diagrams
- Specific alignment for readability

Use formatter-disable comments:
```cpp
// clang-format off
const int table[] = {
    1,  2,  3,  4,
    5,  6,  7,  8,
    9, 10, 11, 12,
};
// clang-format on
```

## Summary

1. Use project's configured formatter
2. Apply formatting before committing
3. Automate with editor integration
4. Enforce in CI/CD
5. Document exceptions
