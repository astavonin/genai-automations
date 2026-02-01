---
name: quality-attributes
description: 8 quality attributes for software evaluation
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
- Unit test strategy defined
- Components testable in isolation
- Edge cases considered
- Integration test scenarios identified

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

## References

See `references/` directory for:
- Detailed attribute descriptions
- Review checklists (design and code)
- Evaluation criteria
