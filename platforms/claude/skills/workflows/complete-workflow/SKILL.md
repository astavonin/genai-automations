---
name: complete-workflow
description: 8-phase complete workflow reference
---

# Complete Workflow Skill

Complete 8-phase workflow for software development with mandatory checkpoints.

## Workflow Phases

```
Phase 0: Start Work         → Load context from planning files
Phase 1: Research           → architecture-research-planner agent
Phase 2: Design             → Create design proposal
Phase 3: Design Review      → reviewer agent (MANDATORY CHECKPOINT)
Phase 4: Implementation     → coder or devops-engineer agent
Phase 5: Code Review        → reviewer agent (MANDATORY CHECKPOINT)
Phase 6: Verification       → Run tests and static analysis
Phase 7: Commit             → User handles git commits
Phase 8: Completion         → Update progress tracking
```

## Commands

Use these commands to execute workflow phases:

- `/start` - Phase 0: Load current work context
- `/research` - Phase 1: Run research phase
- `/design` - Phase 2: Create design proposal
- `/review-design` - Phase 3: Design review (MANDATORY)
- `/implement` - Phase 4: Implementation
- `/review-code` - Phase 5: Code review (MANDATORY)
- `/verify` - Phase 6: Verification
- `/complete` - Phase 8: Mark work complete

## Phase Details

### Phase 0: Start Work
**Command:** `/start`

Load context from planning files:
- `planning/progress.md` - Current active work
- `planning/<goal>/milestone-XX/status.md` - Milestone status
- `planning/<goal>/milestone-XX/design/` - Design docs

### Phase 1: Research
**Command:** `/research`
**Agent:** architecture-research-planner

Investigate existing codebase patterns, architecture, integration points.

**Output:** `planning/<goal>/milestone-XX/design/<feature>-analysis.md`

### Phase 2: Design
**Command:** `/design`
**Agent:** Main conversation

Create detailed design proposal with architecture, approach, trade-offs.

**Output:** `planning/<goal>/milestone-XX/design/<feature>-design.md`

### Phase 3: Design Review (CHECKPOINT)
**Command:** `/review-design`
**Agent:** reviewer
**MANDATORY:** User approval required before implementation

Review design against 8 quality attributes. Block until approved.

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

**Outcomes:**
- ✅ Approve → Proceed to verification
- ⚠️ Request Changes → Fix and re-review
- ❌ Reject → Redesign needed

### Phase 6: Verification
**Command:** `/verify`

Run all checks:
- Unit tests (must pass)
- Integration tests (if applicable)
- Static analysis (zero errors)
- No regressions

### Phase 7: Commit
**User handles all git commits**
- NEVER create commits automatically
- User commits after verification passes

### Phase 8: Completion
**Command:** `/complete`

Update progress tracking:
1. Explicitly propose update to `progress.md`
2. Wait for user confirmation
3. Update `progress.md` only after confirmation
4. Update `status.md` if needed

## Critical Rules

1. **NEVER create git commits** - user always handles commits
2. **NEVER automatically update progress.md** - always propose and confirm
3. **ALL implementations require design review BEFORE code** (Phase 3)
4. **ALL code requires code review AFTER implementation** (Phase 5)

## Agent Declaration

Always declare agent usage:
```
"I'll use <agent-name> agent to <task-description>..."
```

## References

See `references/` directory for workflow diagram and detailed phase descriptions.
