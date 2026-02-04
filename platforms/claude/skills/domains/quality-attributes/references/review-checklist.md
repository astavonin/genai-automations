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
- [ ] Unit test strategy defined
- [ ] Components can be tested in isolation
- [ ] Integration test scenarios identified
- [ ] Edge cases considered

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
- [ ] Test coverage is adequate (critical paths covered)
- [ ] Tests are clear and maintainable
- [ ] Edge cases tested
- [ ] Integration tests identified/planned

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

### Code Standards
- [ ] Follows project coding style
- [ ] No magic numbers (use named constants)
- [ ] No code duplication
- [ ] Functions/methods are focused and small
- [ ] No commented-out code
- [ ] No TODO comments without issue references

### Testing
- [ ] Unit tests comprehensive
- [ ] All tests pass locally
- [ ] Integration tests pass (if applicable)
- [ ] Test names are descriptive
- [ ] Test assertions are clear

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

**When invoked via `/review` command (MR reviews):**
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
- `High` / `Critical` - Must fix (security, data loss, crashes, undefined behavior)
- `Medium` - Should fix (maintainability, performance, test issues)
- `Low` - Nice to fix (style, minor improvements)

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
- Order findings by severity: High → Medium → Low
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
