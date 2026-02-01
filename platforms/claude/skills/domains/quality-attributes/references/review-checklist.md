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
