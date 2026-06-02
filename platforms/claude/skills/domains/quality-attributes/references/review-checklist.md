# Review Checklist

Use this checklist when conducting design and code reviews with the reviewer agent.

## Design Review Checklist (Before Implementation)

### Context
- [ ] Understand the requirement/issue being addressed
- [ ] Review existing codebase patterns
- [ ] Identify integration points and dependencies

### Quality Attributes Assessment

#### Supportability
- [ ] Clear error messages and logging points identified
- [ ] Debugging strategy defined
- [ ] Operational troubleshooting considered

#### Extendability
- [ ] Future requirements anticipated
- [ ] Appropriate abstraction level
- [ ] Extension points identified
- [ ] Modular design

#### Maintainability
- [ ] Follows project conventions and patterns
- [ ] Clear naming and structure
- [ ] Minimal complexity
- [ ] Self-documenting approach

#### Testability
- [ ] Components can be tested in isolation
- [ ] Edge cases considered
- [ ] Key component boundaries and interfaces are mockable/injectable

**Testability analysis — answer all three:**
- [ ] **Local/Docker integration tests:** Can integration tests be run locally or in Docker without special hardware or credentials? What setup is required?
- [ ] **Real environment/device tests:** How difficult is it to run integration tests against a real environment or physical device? What are the blockers (access, hardware, env config)?
- [ ] **Manual testing:** How difficult is it to verify the feature manually? Is there a clear test procedure, or does it require deep system knowledge?

#### Performance
- [ ] No obvious bottlenecks in design
- [ ] Resource usage reasonable
- [ ] Algorithms appropriate for scale
- [ ] Caching strategy if needed

#### Safety
- [ ] Error handling strategy defined
- [ ] Edge cases identified
- [ ] Resource management approach clear
- [ ] Thread safety considered (if applicable)

#### Security
- [ ] Input validation planned
- [ ] No injection vulnerabilities
- [ ] Secrets handling secure
- [ ] Authentication/authorization appropriate

#### Observability
- [ ] Logging strategy defined
- [ ] Key metrics identified
- [ ] Tracing approach clear
- [ ] Monitoring capabilities planned

### Design Quality
- [ ] Simplest approach that meets requirements
- [ ] Not over-engineered
- [ ] Aligns with existing architecture
- [ ] Trade-offs clearly understood

### Documentation
- [ ] Design rationale clear
- [ ] Integration points documented
- [ ] Dependencies identified
- [ ] Migration strategy (if applicable)

## Code Review Checklist (After Implementation)

### Implementation Quality
- [ ] Follows approved design
- [ ] Code passes build
- [ ] Follows C++ Core Guidelines / PEP 8 / Rust API Guidelines
- [ ] Formatting applied (clang-format, etc.)
- [ ] No compiler warnings

### Quality Attributes Verification

#### Supportability
- [ ] Adequate logging at critical paths
- [ ] Clear, actionable error messages
- [ ] Debugging information available
- [ ] Operational concerns addressed

#### Extendability
- [ ] Code is modular
- [ ] Appropriate abstractions used
- [ ] Easy to add new features
- [ ] No premature optimization

#### Maintainability
- [ ] Code is easy to understand
- [ ] Naming is clear and consistent
- [ ] Complexity is minimal
- [ ] Comments explain WHY, not WHAT
- [ ] Self-documenting where possible

#### Testability
- [ ] Unit tests exist and pass
- [ ] Unit tests complete in ≤ 3 seconds each — no network, disk I/O, external processes, or real databases
- [ ] Test coverage is adequate (critical paths covered)
- [ ] When a numeric coverage target can be extracted from repo policy, CI, or surrounding context, the expected minimum is `>= 80%` unless the project defines a stricter rule
- [ ] Tests are clear and maintainable
- [ ] Edge cases tested
- [ ] Integration tests exist (not just planned) for component boundaries
- [ ] Integration tests are tagged/marked to run separately
- [ ] No flaky tests (non-deterministic assertions, bare sleeps)
- [ ] **Behavioral bug findings require a `Required test:` line** — any finding that identifies incorrect runtime behavior (wrong output, data corruption, silent invalid-input acceptance, infinite loop, security bypass) MUST include a `**Required test:**` line describing: what precondition/input triggers the bug and what outcome the test asserts. Quality findings (naming, observability, performance, maintainability) with no wrong-output consequence are exempt.

**Test correctness — answer all four:**
- [ ] **Assertion specificity:** Assertions check concrete values or behavior, not vacuous checks (`assert result is not None`, `assert called_once()` with no argument verification). Each assertion should fail if the implementation returns a wrong-but-non-null value.
- [ ] **Name/assertion alignment:** The test name describes the same scenario and outcome that the assertions actually verify. A mismatch (name says "returns error on missing token", body asserts status 200) is a correctness bug.
- [ ] **Falsifiability:** Would this test fail if the production code were broken in exactly the way the name implies? Mentally delete the production logic and ask whether the test catches it.
- [ ] **Failure scenario coverage:** Every public function or method that can fail MUST have at least one test for each distinct failure mode — invalid input, resource exhaustion, dependency error, boundary violation. A happy-path-only test suite is a correctness gap regardless of line coverage percentage.

#### Performance
- [ ] No unnecessary operations in hot paths
- [ ] Resource usage reasonable
- [ ] Algorithms efficient
- [ ] Caching implemented appropriately
- [ ] No obvious memory leaks

#### Safety
- [ ] Error handling comprehensive
- [ ] Edge cases handled
- [ ] Resource cleanup (RAII, defer, etc.)
- [ ] Thread safety correct (if applicable)
- [ ] No undefined behavior

**Rust — Borrow Checker Effectiveness (applies to all Rust reviews):**
- [ ] **No expensive resource recreated per call** — check hot paths (loops, per-frame, per-request) for patterns where a stream, connection, buffer, or file handle is created and immediately dropped. This is the primary symptom of a missing scoped guard. Flag as `High` if the recreation defeats a streaming/pooling architecture.
- [ ] **Self-referential struct need is addressed idiomatically** — when a struct must hold both an owner and something that borrows from it, verify the solution follows the preference order: scoped guard (`T<'a>`) → typestate → split ownership → `ouroboros`/`self_cell` → `unsafe + Pin`. Flag any jump to `unsafe` or external crate without evidence that scoped guard was evaluated.
- [ ] **Scoped guard pattern used for exclusive scoped resources** — resources with a clear "active / inactive" lifecycle (streams, locks, transactions) should use a guard type that borrows the session/owner (`fn activate(&mut self) -> Guard<'_>`). This makes lifecycle visible in the type system and prevents double-activation or use-after-stop at compile time.
- [ ] **No lifetime erasure via `transmute`** — `std::mem::transmute::<T<'a>, T<'static>>` is only safe when the owner is `Pin`-ned and demonstrably outlives the borrower. Requires an explicit `// SAFETY:` comment stating the invariant. Flag as `Critical` if no safety comment or if the owner is not pinned.
- [ ] **`unsafe` blocks have a documented invariant** — every `unsafe` block must have a `// SAFETY:` comment explaining why it is sound. Flag as `Critical` if missing.
- [ ] **Borrow checker friction treated as a design signal** — if the implementation works around the borrow checker (via `unsafe`, transmute, or an external self-referential crate) without evidence that idiomatic alternatives were evaluated, flag as `Medium` and ask for the tradeoff analysis. The goal is working *with* the borrow checker, not routing around it.

- [ ] **Variable initialization uses `{}` for user-defined types and smart pointers** — `TypeName var(...)` can be parsed as a function declaration (most vexing parse); use `TypeName var{...}` instead. Exception: standard library containers (`std::string`, `std::vector`, etc.) with fill/range constructors must use `()` because `{}` routes through `initializer_list` and changes semantics.
- [ ] **`[[nodiscard]]` on every non-void function whose return value the caller must act on** — applies to: error-indicating `bool` returns, status/result enums, factory/query functions where the only purpose is the return value. Ignoring these silently skips error handling. Trampolines and callbacks registered with external frameworks are exempt (the framework consumes the return).
- [ ] **`[[nodiscard]]` on virtual functions: annotate every site** — the attribute does not propagate from base to overrides. Check the base declaration, every `override` in derived classes, and every test fake or mock implementing the interface.
- [ ] **C++ typed error semantics** — recoverable I/O, network, and external API failures use project-native `std::expected`, `Result`, `StatusOr`, or status-enum patterns. Programmatic control flow does not parse diagnostic strings.
- [ ] **C++ exception boundaries** — exceptions are caught and converted at destructors, C callbacks, C ABI boundaries, thread entry points, and cleanup paths.

#### Security
- [ ] Inputs validated and sanitized
- [ ] No SQL/command/XSS injection vulnerabilities
- [ ] Secrets not hardcoded
- [ ] Authentication/authorization correct
- [ ] Dependencies from trusted sources

#### Observability
- [ ] Key operations logged
- [ ] Metrics available
- [ ] Traceable across boundaries
- [ ] Performance can be monitored

### Test Quality Pass (mandatory — runs after quality-attribute scan)

This is a dedicated enumeration pass, separate from the Testability attribute check above. It must be completed for every code review; a general "testability is adequate" summary does not satisfy it.

**Step 1 — Per-test scan:** List every test function touched by the diff. For each one, verify:
- [ ] **Assertion specificity:** Assertions check concrete values or behavior — not vacuous checks (`assert result is not None`, `assert called_once()` without argument verification). The test must fail if the implementation returns a wrong-but-non-null value.
- [ ] **Name/assertion alignment:** The test name describes the same scenario and outcome the assertions actually verify. A mismatch (name says "rollback sets rollbackDetected", body never asserts `error_code == "rollbackDetected"`) is a correctness bug.
- [ ] **Falsifiability:** Mentally delete the production logic being tested — would the test catch the breakage? If not, the test does not verify what it claims.
- [ ] **No bare sleeps for async behavior:** `time.sleep(N)` or `std::this_thread::sleep_for` used to wait for async side-effects is a race. Replace with polling or a signal/event.

**Step 2 — Per-function negative coverage:** For every public function or method that has at least one test, verify:
- [ ] At least one negative/failure test exists for each distinct failure mode (wrong input, null return, resource exhaustion, dependency error, boundary violation).
- [ ] Safety invariants have explicit negative tests — e.g. "action must NOT fire when ID mismatches" requires a test that asserts the action was not taken, not just that no exception was raised.
- [ ] Error path tests assert the specific error type, code, or message — not just that "some error occurred".
- [ ] Integration tests cover cancellation, timeout, and partial-completion paths, not just the happy path.

**Reporting:** Cite every gap by test name and criterion. Do not aggregate into a single "tests need improvement" finding.

### Code Standards
- [ ] Follows project coding style
- [ ] No magic numbers (use named constants)
- [ ] No code duplication
- [ ] Functions/methods are focused and small
- [ ] No commented-out code
- [ ] No TODO comments without issue references
- [ ] **Library reuse:** No reimplementation of functionality already available in the project's common/utility modules or in ecosystem libraries (STL, Boost, OpenSSL, stdlib equivalents per language) — prefer existing, battle-tested code over custom implementations
- [ ] **Common library promotion:** If any new class/function is domain-neutral, self-contained, and would benefit ≥2 other subprojects, note it as a promotion candidate — only when genuinely warranted, never as a template placeholder

### Testing
- [ ] Unit tests comprehensive
- [ ] All tests pass locally
- [ ] Integration tests pass (if applicable)
- [ ] Test names are descriptive and match what the assertions actually verify
- [ ] Assertions are specific — concrete expected values, not just non-null or call-count checks
- [ ] Every function/method that can fail has tests for each distinct failure mode (not just the happy path)
- [ ] Error paths assert the exact error type, message, or code — not just that "some error occurred"

### Documentation
- [ ] Public APIs documented
- [ ] Complex logic explained
- [ ] Configuration changes documented
- [ ] README updated (if needed)

### Static Analysis
- [ ] clang-tidy passes (C++)
- [ ] pylint/mypy passes (Python)
- [ ] clippy passes (Rust)
- [ ] No linter warnings

### Integration
- [ ] Builds in CI environment
- [ ] Compatible with existing systems
- [ ] No breaking changes (or properly handled)
- [ ] Configuration migration documented

## Review Decision Matrix

| Rating | Criteria |
|--------|----------|
| ✅ **Approve** | All critical items pass, minor issues are acceptable |
| ⚠️ **Request Changes** | Issues found that must be fixed before approval |
| ❌ **Reject** | Fundamental problems requiring redesign |

## Severity Levels

| Level | Description | Action Required |
|-------|-------------|-----------------|
| **Critical** | Security vulnerability, data loss risk, system instability | Must fix before approval |
| **Major** | Significant maintainability/performance/safety issue | Should fix before approval |
| **Minor** | Style issue, minor improvement opportunity | Consider fixing |
| **Suggestion** | Optional enhancement | Optional |

## Tips for Effective Reviews

1. **Be Thorough**: Check all quality attributes, not just obvious issues
2. **Be Specific**: Provide file paths, line numbers, and concrete examples
3. **Be Constructive**: Focus on improvement, not criticism
4. **Be Practical**: Balance ideal solutions with pragmatic progress
5. **Be Consistent**: Apply same standards across all reviews
6. **Be Educational**: Explain WHY something is a concern

## Review Report Format

**When invoked via `/review-mr` command (MR reviews):**
- MUST write review to a YAML file: `planning/reviews/MR<number>-review.yaml`

**For `/review-design` and `/review-code` commands:**
- Output inline in conversation (no file needed)

**ALL reviews must use YAML format:**

```yaml
mr_number: 134
title: "Draft: DMS refactoring"
review_date: "2026-02-04"

findings:
  - severity: High
    title: "Dangling reference capture in async lambda"
    description: |
      In `DMSPipeline::process_frame`, the lambda passed to `enqueue_detached`
      captures the loop variable `detector` by reference. That reference is
      invalid after the loop iteration ends, which is undefined behavior and
      can call the wrong detector or crash.
    location: "system/dms/dms_pipeline.cc:291"
    fix: |
      Capture a stable pointer/value (e.g., `auto* det = detector.get();`
      then `[det, ctx]`).
    guideline: "C++ Core Guidelines F.53 (avoid reference captures in non-local lambdas)"

  - severity: High
    title: "Potential shutdown hang in Latch wait"
    description: |
      The input thread waits on `FrameContext::wait_for_completion()` without
      timeout. If any detector task never calls `signal_detector_done()`, the
      input thread will block indefinitely and `stop()` will hang on `join()`.
    location: "system/dms/dms_pipeline.cc:127-152"
    fix: |
      Add timeout to Latch: `bool wait_for(std::chrono::milliseconds timeout)`
      and use it in `wait_for_completion()`.
    guideline: null

  - severity: Medium
    title: "Unit test defaults do not match config defaults"
    description: |
      `test_dms_pipeline` expects `thread_pool_size == 2` but `PipelineConfig`
      defaults to 6, so this test will fail as written.
    locations:
      - "system/dms/test/test_dms_pipeline.cc:181"
      - "system/dms/dms_pipeline.h:28"
    fix: "Use consistent default value of 4 across all files."
    guideline: null

  - severity: Low
    title: "Redundant destructor logic"
    description: |
      All detector wrappers have unnecessary explicit `reset()` calls in
      destructors. `unique_ptr` handles this automatically.
    location: "system/dms/detectors/detectors.cc"
    fix: "Remove custom destructors, rely on default behavior."
    guideline: null
```

### Severity Levels
- `Critical` - Must fix before merge (security vulnerabilities, data loss, crashes, undefined behavior)
- `High` - Should fix before merge (significant maintainability, correctness, or performance issues)
- `Medium` - Consider fixing (test gaps, style issues, minor improvements)
- `Low` - Optional suggestions (minor enhancements, nice-to-haves)

### Required YAML Fields

**Top-level:**
- `mr_number` - MR number (integer)
- `title` - MR title (string)
- `review_date` - Date in YYYY-MM-DD format (string)
- `findings` - List of finding objects

**Each finding:**
- `severity` - One of: `Critical`, `High`, `Medium`, `Low`
- `title` - Brief, specific problem statement
- `description` - Technical explanation (WHY it's an issue)
- `location` - Single file path with line number(s)
- `locations` - Use instead of `location` for multiple files (list)
- `fix` - Concrete recommendation (optional but recommended)
- `guideline` - Standards reference (optional, use `null` if none)

### YAML Formatting Rules
- Use `|` for multi-line strings (description, fix)
- Use `null` for optional fields with no value (not empty string)
- Use `location` (singular) for single file
- Use `locations` (plural list) for multiple files
- Order findings by severity: Critical → High → Medium → Low
- Keep descriptions concise and technical

## Common Review Failures

### Design Review
- Over-engineered solution
- Doesn't follow existing patterns
- Missing test strategy
- Security concerns not addressed
- No logging/observability plan

### Code Review
- Missing or inadequate tests
- Poor error handling
- Security vulnerabilities
- No logging at critical points
- Doesn't match approved design
- Code complexity too high
- clang-tidy/linter failures

## Reference

- **Complete workflow:** `~/.claude/CLAUDE.md` (Complete Workflow section)
- **Reviewer agent:** `~/.claude/agents/reviewer.md`
- **Project guidelines:** `%current_project%/CLAUDE.md`
