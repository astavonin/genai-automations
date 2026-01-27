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

# Complete Workflow

**Planning Structure:** See `~/.claude/PLANNING-TEMPLATE.md` for planning directory structure and file organization.

**CRITICAL:**
- NEVER create git commits - user will always handle commits
- NEVER automatically update progress.md - always propose explicitly and wait for user confirmation

## Agent Assignment

Always declare which agent you will use for each task:
- **architecture-research-planner**: Research and design tasks
- **coder**: Implementation tasks (non-CI code)
- **devops-engineer**: CI/CD, Docker, infrastructure tasks
- **reviewer**: Mandatory quality reviews (design and code reviews)

## Workflow Phases

```
┌─────────────────────────────────────────────────────────────────────┐
│ 0. Start Work                                                       │
│    → Check current progress and planning files                      │
│    → Load context from progress.md and status.md                    │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 1. Research Phase                                                   │
│    Agent: architecture-research-planner                             │
│    → Investigate existing code, patterns, requirements              │
│    → Ask clarifying questions if requirements unclear               │
│    Output: %current_project%/planning/<goal>/milestone-XX/design/   │
│           <feature>-analysis.md                                     │
│    Contains: Codebase analysis, architecture diagrams, findings     │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 2. Design Phase                                                     │
│    Agent: None (main conversation)                                  │
│    → Analyze requirements and constraints                           │
│    → Propose implementation approach                                │
│    → List files to be modified/created                              │
│    → Explain technical rationale and trade-offs                     │
│    Output: %current_project%/planning/<goal>/milestone-XX/design/   │
│           <feature>-design.md                                       │
│    Contains: Approach, architecture, diagrams, alternatives         │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 3. ⚠️ CHECKPOINT 1: User Approval (MANDATORY) ⚠️                    │
│    Who: User                                                        │
│    → Present complete design approach to user                       │
│    → Wait for explicit user confirmation                            │
│    → DO NOT proceed without approval                                │
│    → If rejected: revise design (return to step 2)                  │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 4. Implementation Phase                                             │
│    Agent: coder (code) OR devops-engineer (CI/CD)                   │
│    → Write code following approved design                           │
│    → Include comprehensive unit tests                               │
│    → Verify build passes after each change                          │
│    → Follow language-specific style guides                          │
│    Output: Implementation complete (code + tests)                   │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 5. ⚠️ CHECKPOINT 2: Code Review (MANDATORY) ⚠️                      │
│    Agent: reviewer                                                  │
│    → Use review checklist: ~/.claude/review-checklist.md           │
│    → Evaluate: Supportability, Extendability, Maintainability,     │
│                Testability, Performance, Safety, Security,          │
│                Observability                                         │
│    → Check: Design adherence, code quality, test coverage          │
│    Assessment: ✅ Approve / ⚠️ Request Changes / ❌ Reject          │
│    → If not approved: fix issues (return to step 5)                │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 6. Verification Phase                                               │
│    → Run all unit tests                                             │
│    → Run integration tests (if applicable)                          │
│    → Run static analysis (clang-tidy, pylint, etc.)                │
│    → Verify no regressions                                          │
│    → All checks must pass                                           │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 7. Commit Phase                                                     │
│    ⚠️ NEVER create commits automatically ⚠️                         │
│    → User will handle all git commits                               │
│    → Only proceed here after review approval and all checks pass    │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 8. Completion Phase                                                 │
│    → After user confirms issue is complete                          │
│    → Explicitly propose to update progress.md                       │
│    → Wait for user confirmation before updating                     │
│    → Update milestone status.md if needed                           │
│    ⚠️ NEVER update planning files automatically ⚠️                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Phase Details

### Phase 0: Start Work

**Always begin by checking:**
```bash
# Read current progress
cat planning/progress.md

# Check active milestone status
cat planning/<goal>/milestone-XX-<name>/status.md

# Check design docs if they exist
ls planning/<goal>/milestone-XX-<name>/design/
```

### Phase 1: Research

**Agent:** `architecture-research-planner`

**Actions:**
- Investigate existing codebase patterns
- Understand current architecture
- Identify integration points and dependencies
- Ask clarifying questions if requirements are unclear

**Output:** `planning/<goal>/milestone-XX/design/<feature>-analysis.md`
- Codebase analysis
- Architecture diagrams (Mermaid)
- Research findings
- Integration points

### Phase 2: Design

**Agent:** Main conversation (no specialized agent)

**Actions:**
- Analyze requirements and constraints
- Propose implementation approach
- List files to be modified/created
- Explain technical rationale
- Document trade-offs and alternatives

**Output:** `planning/<goal>/milestone-XX/design/<feature>-design.md`
- Proposed approach
- Architecture diagrams
- Alternative approaches considered
- Design rationale
- File modification list

**Key:** Design files = HOW to implement (architecture, approach)

### Phase 3: Checkpoint 1 - User Approval

**Who:** User (mandatory)

**Present:**
- Complete design approach
- Files to be modified/created
- Technical rationale and trade-offs
- Expected changes summary

**Requirements:**
- User MUST explicitly approve before any code changes
- NO code implementation without approval
- If rejected: revise design and return to Phase 2

### Phase 4: Implementation

**Agent:** `coder` (application code) OR `devops-engineer` (CI/CD/infrastructure)

**Actions:**
- Write code following approved design
- Include comprehensive unit tests (mandatory)
- Verify build passes after each change
- Follow language-specific style guides (C++ Core Guidelines, PEP 8, etc.)
- Apply code formatting (clang-format, black, etc.)

**Output:** Implementation complete (code + tests)

### Phase 5: Checkpoint 2 - Code Review

**Agent:** `reviewer` (mandatory)

**Review Checklist:** `~/.claude/review-checklist.md`

**Evaluate:**
- **Supportability:** Logging, error messages, debugging
- **Extendability:** Modularity, abstractions, future-proofing
- **Maintainability:** Code clarity, naming, complexity
- **Testability:** Unit tests, test coverage, edge cases
- **Performance:** No bottlenecks, efficient algorithms
- **Safety:** Error handling, resource management, thread safety
- **Security:** Input validation, no vulnerabilities
- **Observability:** Logging, metrics, tracing

**Also Check:**
- Design adherence (matches approved design)
- Code quality and standards
- Test coverage and quality
- Static analysis compliance

**Assessment:**
- ✅ **Approve:** Proceed to verification
- ⚠️ **Request Changes:** Fix issues and return for re-review
- ❌ **Reject:** Fundamental problems, redesign needed

**How to invoke:**
```
"I'll use the reviewer agent to perform code review. Please use the Code Review
Checklist from ~/.claude/review-checklist.md to evaluate the implementation."
```

### Phase 6: Verification

**Actions:**
- Run all unit tests
- Run integration tests (if applicable)
- Run static analysis (clang-tidy, pylint, clippy, etc.)
- Verify no regressions in existing functionality
- All checks must pass

**Requirements:**
- Zero test failures
- Zero static analysis errors
- No breaking changes (or properly documented)

### Phase 7: Commit

**CRITICAL:**
- NEVER create git commits automatically
- User will handle all commit operations
- Only proceed here after:
  - Review approval received
  - All verification checks pass

### Phase 8: Completion

**After user confirms issue is complete:**

**Actions:**
1. Explicitly propose to update `planning/progress.md`
2. Wait for user confirmation
3. Update progress.md only after confirmation
4. Update `planning/<goal>/milestone-XX/status.md` if needed
5. Archive design documents if milestone complete

**Key:** Status files = WHAT to do (task checklists, progress %)

**NEVER:**
- Update planning files automatically
- Assume work is complete without user confirmation

## Review Checklist Usage

**Location:** `~/.claude/review-checklist.md`

**Design Review (Before Implementation):**
```
"I'll use the reviewer agent to review this design. Please use the Design Review
Checklist from ~/.claude/review-checklist.md to evaluate the approach."
```

**Code Review (After Implementation):**
```
"I'll use the reviewer agent to perform code review. Please use the Code Review
Checklist from ~/.claude/review-checklist.md to evaluate the implementation."
```

## Agent Declaration Pattern

For EVERY task, explicitly state agent usage:

```
"I'll use <agent-name> agent to <task-description>..."
```

**Examples:**
- "I'll use architecture-research-planner agent to investigate existing error handling patterns..."
- "I'll use coder agent to implement the authentication module following the approved design..."
- "I'll use devops-engineer agent to create the CI pipeline configuration..."
- "I'll use reviewer agent for code review. Please use the Code Review Checklist from ~/.claude/review-checklist.md..."
