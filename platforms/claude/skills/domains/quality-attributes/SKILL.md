---
name: quality-attributes
description: Eight quality attributes for software evaluation: supportability, extendability, maintainability, testability, performance, safety, security, observability. Use when conducting design reviews or code reviews to evaluate all quality dimensions.
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: domains
  tags: [quality, review, architecture, design]
---

# Quality Attributes Skill

Eight quality attributes for evaluating software design and implementation.

## The 8 Quality Attributes

### 1. Supportability
**Definition:** How easy is it to diagnose and fix issues?

**Key aspects:**
- Adequate logging at critical paths
- Clear, actionable error messages
- Debugging information available
- Operational troubleshooting considered

### 2. Extendability
**Definition:** How easy is it to add new features?

**Key aspects:**
- Modular design
- Appropriate abstractions
- Extension points identified
- Future requirements anticipated

### 3. Maintainability
**Definition:** How easy is it to understand and modify the code?

**Key aspects:**
- Code clarity and naming
- Minimal complexity
- Follows project conventions
- Self-documenting approach

### 4. Testability
**Definition:** How easy is it to test the system?

**Key aspects:**
- Unit test strategy defined; components testable in isolation
- Integration tests written (not just planned) for component boundaries
- Integration tests tagged to run separately from unit tests
- Edge cases covered; no flaky tests
- When a coverage target can be extracted from repo policy, CI, or review context, expect `>= 80%` coverage unless the project defines a stricter rule

### 5. Performance
**Definition:** Does the system meet performance requirements?

**Key aspects:**
- No obvious bottlenecks
- Resource usage reasonable
- Algorithms appropriate for scale
- Profiling and optimization strategy

### 6. Safety
**Definition:** Does the system handle errors and edge cases gracefully?

**Key aspects:**
- Comprehensive error handling
- Edge cases handled
- Resource management (RAII, defer, etc.)
- Thread safety (if applicable)
- No undefined behavior

### 7. Security
**Definition:** Is the system protected against vulnerabilities?

**Key aspects:**
- Input validation and sanitization
- No injection vulnerabilities (SQL, command, XSS)
- Secrets not hardcoded
- Authentication/authorization appropriate
- Dependencies from trusted sources

### 8. Observability
**Definition:** Can we understand system behavior in production?

**Key aspects:**
- Key operations logged
- Metrics available
- Traceable across boundaries
- Performance can be monitored

## Usage

### Design Review
Evaluate proposed design against all 8 attributes before implementation.

### Code Review
Verify implementation meets quality standards for all 8 attributes after implementation.

## References (checklist lookup — explicitly read when doing reviews)

- `references/review-checklist.md` — full design and code review checklists (pass this path to reviewer agent)
