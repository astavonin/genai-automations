---
name: verify
description: Run linters, tests, and static analysis
---

# Verification Command

Run comprehensive verification before considering work complete.

## Setup

Read testing skill before starting:
```
Read ~/.claude/skills/domains/testing/SKILL.md
```

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
   - C++: `clang-tidy`, `cppcheck` (via project build system, e.g. `./dev.sh lint --cpp`)
   - Go: `golangci-lint`, `go vet`
   - Rust: `clippy`
   - Shell: `shellcheck`

   **CRITICAL:**
   - Fix ALL linter errors and warnings before proceeding
   - If linters missing, this is a FAILURE - do not silently fall back to syntax checking

2. **C++ clangd analysis** (C++ projects only — skip for other languages):

   Clangd provides code intelligence from the editor's language server and catches
   issues that clang-tidy may miss (dead code, type mismatches, missing implementations).
   It complements the Docker-based linter — it does not replace it.

   **Step 2a — Identify changed C++ files:**
   ```bash
   git diff --name-only HEAD | grep -E '\.(cc|cpp|h|hpp)$'
   # Or against the base branch:
   git diff origin/master...HEAD --name-only | grep -E '\.(cc|cpp|h|hpp)$'
   ```

   **Step 2b — Enumerate symbols in each changed `.cc` / `.cpp` file:**
   For each changed implementation file, use the LSP tool:
   ```
   LSP(operation="documentSymbol", filePath="<abs-path>", line=1, character=1)
   ```
   Review the returned symbol list:
   - Every method declared in the corresponding `.h` should appear
   - Flag any declared method with no matching symbol (missing implementation)
   - Flag any unexpectedly short method (< 3 lines) — use `hover` to verify its return type

   **Step 2c — Spot-check suspicious method bodies with hover:**
   For any method whose implementation looks incorrect (wrong return type, suspicious
   boolean expression, missing side effect), use:
   ```
   LSP(operation="hover", filePath="<abs-path>", line=<method-line>, character=<col>)
   ```
   This surfaces the inferred type at that position and can catch operator-precedence
   bugs and implicit conversions (e.g. `return !ptr != nullptr || arg == nullptr`
   returning `bool` when the intent was to store and start a worker).

   **Step 2d — Check for dead public API (optional, for smaller files):**
   For key public methods on core classes, use:
   ```
   LSP(operation="findReferences", filePath="<abs-path>", line=<method-line>, character=<col>)
   ```
   A public method with zero references is a candidate for removal or may indicate
   a caller was accidentally deleted.

   **Clangd limitations to be aware of:**
   - If `compile_commands.json` uses Docker-internal paths (e.g. `/workspace`), system
     headers (`zmq.h`, capnp headers) won't resolve on the host → ignore
     `file not found` diagnostics for those headers, they are environment false positives
   - Clangd diagnostics for local project headers and standard library types ARE reliable
   - `<new-diagnostics>` system reminders surfaced by the Edit tool are clangd output —
     review them, but filter out false positives from missing system headers

3. **Run all unit tests:**
   - Execute full test suite
   - Verify all tests pass

4. **Run integration tests** (if applicable):
   - Execute integration test suite
   - Verify system integration

5. **Run static analysis:**
   - Additional static analysis tools beyond linters
   - Security scanners (if configured)
   - Code complexity analysis (if applicable)

6. **Verify no regressions:**
   - Check existing functionality still works
   - Verify no breaking changes

7. **On-device verification:**

   **Step 7-pre — Determine scope from analysis.md:**
   Read `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md` and check the `## On-Device Scope` recorded there (values: `YES`, `YES, procedures unknown`, or `NO`).
   - If scope is `NO`: skip Steps 7a–7c entirely with a one-line note.
   - If scope is `YES` or `YES, procedures unknown`: continue to Step 7a — do NOT skip even if the design doc's On-Device Verification section is absent. A missing section when scope is `YES` is a gap that must be surfaced, not silently skipped.
   - If `analysis.md` does not exist or contains no `## On-Device Scope` entry: treat scope as unknown and continue to Step 7a.

   **Step 7a — Locate entry point:**
   Check the active issue's design doc for an `**Entry point:**` line. If the design doc has an On-Device Verification section but no `**Entry point:**` line, or if the On-Device Verification section is absent entirely when scope is `YES`, surface an error: "On-device scope is YES but the design doc is missing the On-Device Verification section or Entry point — cannot determine entry point. Resolve before proceeding." Do not attempt to find an entry point from project files; this is a gate failure that should have been caught at `/review-design`.

   **Step 7b — Run verification:**
   If an entry point is found and a device is reachable, invoke it:
   ```bash
   <entry-point>   # e.g. make verify-device, scripts/verify-device.sh, ./dev.sh test-device
   ```

   **Step 7c — Device unavailable locally:**
   If no device is connected, flag explicitly: "On-device verification pending — run `<entry-point>` before merge. CI must cover it via the CI trigger defined in the design doc's On-Device Verification block (e.g., `DEVICE_IP` env var, runner label, or equivalent)." Treat verification as incomplete — do not update planning state and do not proceed to `/complete` until CI evidence of a passing device run is produced and recorded in the issue folder (e.g., a CI log link in a `device-verification.md` file). This is a blocker, not an advisory.

## Requirements

- ✅ Linters discovered and available (MANDATORY - ask user if missing)
- ✅ Zero linter errors/warnings
- ✅ Code formatting applied
- ✅ C++ clangd analysis complete — no missing implementations, no suspicious short methods
- ✅ Zero test failures
- ✅ Zero static analysis errors
- ✅ No breaking changes (or properly documented)
- ✅ Build passes
- ✅ On-device verification passed, or explicitly deferred with a CI-coverage statement if no device is available locally

## Failure Handling

If any check fails:
1. **Linter failures:** Fix code style, type errors, or warnings immediately
2. **Clangd findings:** Fix missing implementations or logic bugs before running tests
3. **Test failures:** Debug and fix the failing tests
4. **Static analysis issues:** Address security or code quality concerns
5. **On-device verification failures:** Check the failure indicators listed in the design doc's On-Device Verification section; fix the underlying issue (firmware, deploy step, or test logic) and re-run the entry-point script. If the device is unavailable, leave the explicit pending statement from Step 7c in place and do not mark as verified.
6. Re-run verification from step 1 (linters)
7. Do NOT proceed to completion until all checks pass

## Execution Order is Critical

**Always run in this order:**
1. Linters (fix code quality)
2. Clangd analysis — C++ only (catch missing impls and type bugs)
3. Tests (verify correctness)
4. Static analysis (security/quality)
5. Regression check

Do NOT run tests before linters and clangd pass. This ensures clean code before verification.

## Planning State Update (on full pass only)

When **all checks pass**, update planning state:

- In `planning/<goal>/milestone-XX/status.md`, append `| verified ✅` to the Notes column for the active issue.
- In `planning/progress.md` Active entry, append or replace: `- verification ✅ (linters + tests + itest)`.
- Update `**Last Updated:**` to today's date.

Then push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```
Follow the steps in that fragment. Surface the §8.2 warning block on failure; do not fail the skill.

**Do not update planning state if any check fails** — the failure is visible to the user; a stale "verified ✅" in planning would be worse than no entry.

## Next Step

After all checks pass, user handles commit (Phase 7), then use `/complete` to mark work done.
