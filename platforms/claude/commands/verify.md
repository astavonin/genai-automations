---
name: verify
description: Run tests and static analysis
---

# Verification Command

Run comprehensive verification before considering work complete.

## Actions

1. **Run all unit tests:**
   - Execute full test suite
   - Verify all tests pass

2. **Run integration tests** (if applicable):
   - Execute integration test suite
   - Verify system integration

3. **Run static analysis:**
   - C++: clang-tidy
   - Python: pylint, mypy
   - Rust: clippy
   - Go: golint, go vet
   - Language-specific linters

4. **Verify no regressions:**
   - Check existing functionality still works
   - Verify no breaking changes

## Requirements

- ✅ Zero test failures
- ✅ Zero static analysis errors
- ✅ No breaking changes (or properly documented)
- ✅ Build passes

## Failure Handling

If any check fails:
1. Fix the issue
2. Re-run verification
3. Do NOT proceed to completion until all checks pass

## Next Step

After all checks pass, user handles commit (Phase 7), then use `/complete` to mark work done.
