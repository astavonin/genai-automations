---
name: complete-workflow
description: 8-phase software development workflow with mandatory design and code review checkpoints. Use when starting any implementation task to follow the research → design → review → implement → review → verify phases.
allowed-tools: Bash, Glob, Grep, Read, Write, Edit, WebFetch, WebSearch
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [workflow, development, phases, review]
---

# Complete Workflow Skill

Complete 8-phase workflow for software development with mandatory checkpoints.

## Workflow Phases

```
Phase 0: Start Work         → Sync planning → Load context → Reverify knowledge
Phase 1: Research           → architecture-research-planner agent
Phase 2: Design             → Create design proposal
Phase 3: Design Review      → reviewer agent (MANDATORY CHECKPOINT)
Phase 4: Implementation     → coder or devops-engineer agent
Phase 5: Code Review        → reviewer agent (MANDATORY CHECKPOINT)
Phase 6: Verification       → Run linters, tests, and static analysis
Phase 7: Commit             → User handles git commits
Phase 8: Completion         → Update progress tracking → Backup planning
```

## Commands

Use these commands to execute workflow phases:

- `/start` - Phase 0: Sync planning, load context, reverify knowledge
- `/research` - Phase 1: Run research phase
- `/design` - Phase 2: Create design proposal
- `/review-design` - Phase 3: Design review (MANDATORY)
- `/implement` - Phase 4: Implementation
- `/review-code` - Phase 5: Code review (MANDATORY)
- `/verify` - Phase 6: Verification
- `/complete` - Phase 8: Mark work complete, backup planning

## Phase Details

### Phase 0: Start Work
**Command:** `/start`

**Step 1: Sync Planning State (Multi-Machine Support)**
```bash
ci-platform-manager sync pull
```
Pulls latest planning state from Google Drive backup to ensure you have the most recent work from all machines.

**Step 2: Load Context**
Load context from planning files:
- `planning/progress.md` - Current active work
- `planning/<goal>/milestone-XX/status.md` - Milestone status
- `planning/<goal>/milestone-XX/design/` - Design docs

**Step 3: Reverify Knowledge**
- Check if any planning files were updated from backup
- Review any changes made on other machines
- Confirm understanding of current work state

### Phase 1: Research
**Command:** `/research`
**Agent:** architecture-research-planner

Investigate existing codebase patterns, architecture, integration points.

**Output:** `planning/<goal>/milestone-XX/design/<feature>-analysis.md`

### Phase 2: Design
**Command:** `/design`
**Agent:** Main conversation

Create detailed design proposal with architecture, approach, trade-offs, and test plan.

**Output:** `planning/<goal>/milestone-XX/design/<feature>-design.md`

**Required sections** (design doc is incomplete without all of these):
- Architecture / approach with at least one Mermaid diagram
- Files to be created/modified
- Trade-offs and alternatives
- **Test Plan** — unit test table (component → scenarios) + integration test table (boundary → what it verifies) + explicit exclusions

After writing, ask the user if they want to `open <path>` the design file.

### Phase 3: Design Review (CHECKPOINT)
**Command:** `/review-design`
**Agent:** reviewer
**MANDATORY:** User approval required before implementation

Review design against 8 quality attributes. Block until approved.

**Output:** Write report to `planning/<goal>/milestone-XX/reviews/<feature>-design-review.md`.
After writing, ask the user if they want to `open <path>` the review file.

**Outcomes:**
- ✅ Approve → Proceed to implementation
- ⚠️ Request Changes → Revise and re-review
- ❌ Reject → Return to Phase 2

### Phase 4: Implementation
**Command:** `/implement`
**Agent:** coder OR devops-engineer

Implement approved design with:
- Production code
- Comprehensive unit tests
- Passing build
- Applied formatting

### Phase 5: Code Review (CHECKPOINT)
**Command:** `/review-code`
**Agent:** reviewer
**MANDATORY:** Review required after implementation

Review code against 8 quality attributes and design adherence.

**Output:** Write report to `planning/<goal>/milestone-XX/reviews/<feature>-code-review.md`.
After writing, ask the user if they want to `open <path>` the review file.

**Outcomes:**
- ✅ Approve → Proceed to verification
- ⚠️ Request Changes → Fix and re-review
- ❌ Reject → Redesign needed

### Phase 6: Verification
**Command:** `/verify`

Run all checks in this order:
1. **Linters** (FIRST - must pass before tests):
   - Python: pylint, flake8, mypy (type checking)
   - C++: clang-tidy, cppcheck
   - Go: golangci-lint, go vet
   - Rust: clippy
   - Shell: shellcheck
   - Apply auto-formatting if needed
2. **Unit tests** (must pass)
3. **Integration tests** (if applicable)
4. **Static analysis** (zero errors)
5. **Regression check** (no existing functionality broken)

**Critical:** Linting MUST be run before tests. Fix all linter errors and warnings before proceeding.

### Phase 7: Commit
**User handles all git commits**
- NEVER create commits automatically
- User commits after verification passes

### Phase 8: Completion
**Command:** `/complete`

**Step 1: Update Progress Tracking**
1. Explicitly propose update to `progress.md`
2. Wait for user confirmation
3. Update `progress.md` only after confirmation
4. Update `status.md` if needed

**Step 2: Backup Planning State (Multi-Machine Support)**
```bash
ci-platform-manager sync push
```
Pushes updated planning to Google Drive backup, making it available on all machines.

**Purpose:** Ensures planning state is backed up and synchronized after completing work

## Critical Rules

1. **NEVER create git commits** - user always handles commits
2. **NEVER automatically update progress.md** - always propose and confirm
3. **ALWAYS declare agent before use** - state "I'll use <agent-name> agent to <task>..." before every agent invocation
4. **ALL implementations require design review BEFORE code** (Phase 3)
5. **ALL code requires code review AFTER implementation** (Phase 5)
6. **NEVER use `isolation: "worktree"` for coder or devops-engineer agents** — changes would land in a throw-away branch instead of the user's working branch, requiring manual recovery. Omit the `isolation` parameter entirely for all implementation agents.

## Agent Declaration

Always declare agent usage:
```
"I'll use <agent-name> agent to <task-description>..."
```

## References

See `references/` directory for workflow diagram and detailed phase descriptions.
