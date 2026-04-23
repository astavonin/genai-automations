# Code Formatting Guidelines

## Core Principle

Apply the project's formatter to every file you modify.

## Preferred Tools

### C++
- Tool: `clang-format`
- Typical config: `.clang-format`
- Typical usage: `clang-format -i <file>`

### Python
- Tool: `black` or the project's configured formatter
- Typical config: `pyproject.toml`
- Typical usage: `black <file>`

### Go
- Tool: `gofmt` or `goimports`
- Typical usage: `gofmt -w <file>` or `goimports -w <file>`

## When To Apply Formatting

- after making edits
- before finishing the change
- on the files you touched, not as unrelated mass churn

## Existing Code

Prefer formatting only the files you changed unless the task is explicitly a repo-wide formatting pass.

If a repo-wide format is required:
1. keep it in a dedicated change
2. avoid mixing behavioral edits with mass formatting
3. document the reformat clearly

## Exceptions

Occasional exceptions can be reasonable for:
- generated code
- embedded tables or structured data
- carefully aligned blocks kept for readability

If formatting is disabled, the exception should be narrow and justified.

## Summary

Formatting should be automatic, consistent, and low-drama. Use the repository's established toolchain and avoid introducing unrelated churn.
