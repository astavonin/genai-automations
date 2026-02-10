---
name: verify
description: Run linters, tests, and static analysis
---

# Verification Command

Run comprehensive verification before considering work complete.

## Actions (Execute in Order)

1. **Run linters FIRST** (must pass before tests):

   **Linter Discovery Process:**
   a. Search for project linters in order:
      - Virtual environment (`.venv/bin/`, `venv/bin/`)
      - Project-local installations (`node_modules/.bin/`)
      - System PATH
   b. If linters not found, search for formatters:
      - Python: `black`, `autopep8`, `yapf`
      - C++: `clang-format`
      - Go: `gofmt`
      - Rust: `rustfmt`
   c. If neither linters nor formatters found:
      - **STOP** and explicitly ask user how to proceed
      - Provide options: install linters, skip linting, use basic syntax check
      - **DO NOT** proceed to tests without user decision

   **Language-Specific Linters:**
   - Python: `pylint`, `flake8`, `mypy` (type checking)
   - C++: `clang-tidy`, `cppcheck`
   - Go: `golangci-lint`, `go vet`
   - Rust: `clippy`
   - Shell: `shellcheck`

   **CRITICAL:**
   - Fix ALL linter errors and warnings before proceeding
   - If linters missing, this is a FAILURE - do not silently fall back to syntax checking

2. **Run all unit tests:**
   - Execute full test suite
   - Verify all tests pass

3. **Run integration tests** (if applicable):
   - Execute integration test suite
   - Verify system integration

4. **Run static analysis:**
   - Additional static analysis tools beyond linters
   - Security scanners (if configured)
   - Code complexity analysis (if applicable)

5. **Verify no regressions:**
   - Check existing functionality still works
   - Verify no breaking changes

## Requirements

- ✅ Linters discovered and available (MANDATORY - ask user if missing)
- ✅ Zero linter errors/warnings
- ✅ Code formatting applied
- ✅ Zero test failures
- ✅ Zero static analysis errors
- ✅ No breaking changes (or properly documented)
- ✅ Build passes

## Failure Handling

If any check fails:
1. **Linter failures:** Fix code style, type errors, or warnings immediately
2. **Test failures:** Debug and fix the failing tests
3. **Static analysis issues:** Address security or code quality concerns
4. Re-run verification from step 1 (linters)
5. Do NOT proceed to completion until all checks pass

## Execution Order is Critical

**Always run in this order:**
1. Linters (fix code quality)
2. Tests (verify correctness)
3. Static analysis (security/quality)
4. Regression check

Do NOT run tests before linters pass. This ensures clean code before verification.

## Next Step

After all checks pass, user handles commit (Phase 7), then use `/complete` to mark work done.
