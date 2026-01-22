# Communication Style

- Avoid validation phrases like "you are right", "great idea", or similar unnecessary affirmations
- Focus on technical accuracy and objective analysis
- Be concise and direct

# Coding Standards

## Language-Specific Guidelines
- **C++**: Strictly follow The C++ Core Guidelines
- **Python**: Follow PEP 8 and Google Python Style Guide
- **Go**: Follow Effective Go, Go Code Review Comments, and official Go style guide
- **Rust**: Follow Rust API Guidelines
- **Zig**: Follow Zig Style Guide

## Code Comments
- Write self-documenting code that needs minimal comments
- Before adding a comment, reevaluate the code: why is it unclear?
- When comments are necessary:
  - Be concise and focus on intent
  - Classes: 1-2 line summary
  - Methods: Inline purpose if non-obvious
  - TODOs: For future work
  - Tests: Describe the test case
- Avoid: usage examples, complexity notes, responsibility lists (tests document usage)

## Linter Suppressions
- **ALWAYS add a comment explaining WHY** when suppressing linter warnings
- Apply to all suppression directives in any language:
  - C++: `// NOLINTNEXTLINE(rule-name)`
  - Python: `# noqa`, `# type: ignore`
  - Go: `//nolint`
  - Rust: `#[allow(clippy::...)]`
  - JavaScript/TypeScript: `// eslint-disable-next-line`
- Format: `// NOLINTNEXTLINE(rule-name): Reason why suppression is needed`
- Example: `// NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast): Hardware register access requires reinterpret_cast`

## Formatting
- Apply formatting using the current project's formatting tool for all files you create or modify

# Workflow

## Prerequisites
1. **Load progress file**: Always start by loading `%current_project%/planning/progress.md`
2. **Follow planning template**: Adhere to the approach described in `~/.claude/PLANNING-TEMPLATE.md`

## Standard Process
1. **Research**: Investigate existing code, patterns, and requirements using `architecture-research-planner` agent
2. **Clarify**: Ask questions to resolve ambiguities before planning
3. **Design**: Analyze requirements and constraints
4. **Plan**: Create implementation plan (never skip this step)
5. **Confirm**: Wait for explicit user approval before coding
6. **Implement**: Execute the approved plan
7. **Verify**: Check results of each step before proceeding to the next
8. **Review**: Mandatory code review after implementation
9. **Complete**: After user confirms issue is complete, explicitly propose to update `%current_project%/planning/progress.md`

**CRITICAL:**
- NEVER create git commits - user will always handle commits
- NEVER automatically update progress.md - always propose explicitly and wait for user confirmation

## Agent Assignment
Always declare which agent you will use for each task:
- **architecture-research-planner**: Research and design tasks
- **coder**: Implementation tasks (non-CI code)
- **devops-engineer**: CI/CD, Docker, infrastructure tasks
- **reviewer**: Mandatory quality reviews (after implementation)

# Mandatory Review Process

**CRITICAL:** All implementations MUST be reviewed by the reviewer agent after completion.
**EXEMPTIONS:** None. All code changes require review.

## Two-Checkpoint System

### Checkpoint 1: Approach Confirmation (BEFORE Implementation)

**When:** After research and design, BEFORE any code changes
**Who:** User (mandatory)
**What to present:**
- Proposed implementation approach
- Files to be modified/created
- Technical rationale and trade-offs
- Expected changes summary

**Requirements:**
- User MUST explicitly approve approach before coding starts
- NO code changes without user confirmation
- If rejected: revise approach and re-present

### Checkpoint 2: Code Review (AFTER Implementation)

**When:** After implementation is complete (code + tests), BEFORE commit
**Who:** reviewer agent (mandatory)
**What to evaluate:**
- Quality attributes: Supportability, Extendability, Maintainability, Testability
- Non-functional: Performance, Safety, Security, Observability
- Design adherence: Approved design, code quality, best practices
- Test coverage and quality

**Requirements:**
- Must pass review BEFORE committing code
- If review requests changes: fix issues and return for re-review

## Complete Workflow

```
1. Research Phase
   Agent: architecture-research-planner
   └─> Understand existing code, patterns, requirements
   └─> Output: Research findings → %current_project%/planning/<goal>/milestone-XX/design/<feature>-analysis.md
   └─> Contains: Codebase analysis, architecture diagrams (Mermaid), findings

2. Design Phase
   Agent: None (main conversation)
   └─> Analyze requirements and constraints
   └─> Propose implementation approach
   └─> List files to be modified/created
   └─> Explain technical rationale and trade-offs
   └─> Output: Design proposal → %current_project%/planning/<goal>/milestone-XX/design/<feature>-design.md
   └─> Contains: Approach, architecture, diagrams, alternatives, rationale

3. ⚠️ CHECKPOINT 1: User Approval ⚠️
   └─> Present approach to user
   └─> Wait for explicit user confirmation
   └─> DO NOT proceed without approval
   └─> If rejected: revise design (return to step 2)

4. Implementation Phase
   Agent: coder (code) OR devops-engineer (CI/CD)
   └─> Write code following approved design
   └─> Include comprehensive unit tests
   └─> Verify build passes
   └─> Output: Implementation complete

5. ⚠️ CHECKPOINT 2: Code Review ⚠️
   Agent: reviewer (mandatory)
   └─> Evaluate implementation quality
   └─> Assessment: Approve / Request Changes / Reject
   └─> If not approved: fix issues (return to step 5)

6. Verification Phase
   └─> Run all tests (unit + integration)
   └─> Run static analysis (e.g., clang-tidy)
   └─> Verify no regressions
   └─> Output: All checks pass

7. Commit Phase
   └─> NEVER create commits - user will handle this
   └─> Only proceed to this phase after review approval and all checks pass

8. Completion Phase
   └─> After user confirms issue is complete
   └─> Explicitly propose to update %current_project%/planning/progress.md
   └─> Wait for user confirmation before updating
   └─> NEVER update progress.md automatically

Note: Keep status tracking (progress.md, status.md) separate from design artifacts (design/ folder).
Status files = WHAT to do (tasks, progress %). Design files = HOW to do it (architecture, diagrams).
```

## Agent Declaration Pattern

For EVERY task, explicitly state agent usage:

```
"I'll use <agent-name> agent to <task-description>..."

Examples:
- "I'll use architecture-research-planner agent to investigate existing error handling patterns..."
- "I'll use coder agent to implement the authentication module following the approved design..."
- "I'll use devops-engineer agent to create the CI pipeline configuration..."
- "I'll use reviewer agent for code review of the implemented feature..."
```
