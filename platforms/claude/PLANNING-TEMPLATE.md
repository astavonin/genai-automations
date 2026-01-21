# Planning Structure Template

## Overview

This template defines the planning structure and workflow for tracking long-term goals, milestones, and progress.

## Directory Structure

```
planning/
├── progress.md                           # Current work tracking (root level)
│
├── <goal-name>/                          # One folder per long-term goal
│   ├── overview.md                       # High-level milestone list
│   │
│   ├── milestone-XX-<name>/              # One folder per milestone
│   │   ├── status.md                     # Milestone progress tracking
│   │   ├── design/                       # Temporary design/architecture docs
│   │   │   ├── <feature>-design.md      # Design proposals
│   │   │   └── <component>-analysis.md  # Research findings
│   │   ├── epic-YY-<name>.md            # Epic details (when needed)
│   │   └── ...                           # Additional epic files
│   │
│   └── milestone-ZZ-<name>/
│       └── status.md
│
└── <another-goal>/
    └── overview.md
```

## File Purposes

### `progress.md` (Root Level)

**Purpose:** Track current active work across all goals
**Updated:** Daily/frequently
**Format:** Concise, task-focused

**Contains:**
- Current active milestone/epic
- What's in progress today
- Blockers and dependencies
- Next immediate steps (this week)
- Last updated timestamp

**Style:** Brief bullet points, no details

---

### `<goal-name>/overview.md`

**Purpose:** High-level roadmap for the long-term goal
**Updated:** When milestones added/completed
**Format:** Milestone list with context

**Contains:**
- Goal description (2-3 sentences)
- Foundation/prerequisites completed
- Milestone list (3-5 lines per milestone)
- Dependency chain diagram
- Execution phases
- Common exclusions (if applicable)

**Style:** Concise descriptions focusing on WHAT, not HOW

---

### `milestone-XX-<name>/status.md`

**Purpose:** Track milestone execution progress
**Updated:** Weekly or when status changes
**Format:** Task checklist

**Contains:**
- Milestone completion % (e.g., 70%)
- Epic breakdown with status (open/closed counts)
- Current blockers
- Timeline status (on track / at risk / blocked)
- Risk summary (high/medium/low)
- Next actions (task checklist)

**Style:** Concise, scannable, checklist format

**Example:**
```markdown
# Milestone 15: Performance Predictability

**Status:** 40% complete (2/5 epics done)
**Timeline:** On track
**Risk:** Low

## Epics

- ✅ Epic #30: Frame rate measurement (5/5 issues closed)
- 🔶 Epic #31: Latency optimization (2/4 issues closed)
- 🔴 Epic #32: Resource profiling (0/3 issues - blocked)
- ⬜ Epic #33: Performance baselines (not started)
- ⬜ Epic #34: Regression tests (not started)

## Blockers

- Epic #32 blocked: Profiling tools not available in CI

## Next Actions

- [ ] Complete Epic #31: Issues #145, #146
- [ ] Resolve Epic #32 blocker: Install profiling tools
- [ ] Start Epic #33: Define baseline metrics
```

---

### `milestone-XX-<name>/design/`

**Purpose:** Temporary design and research artifacts for the milestone
**Updated:** During research and design phases
**Format:** Architecture docs, diagrams, analysis

**Contains:**
- Research findings and codebase analysis
- Architecture diagrams (Mermaid)
- Design proposals and alternatives
- Technical decision rationale
- Implementation approach details

**Style:** Detailed technical content with diagrams

**Key Difference from status.md:**
- `status.md` = WHAT to do (task list, progress %)
- `design/` = HOW to do it (architecture, approach, diagrams)

**When to create:**
- Research phase produces analysis documents
- Design phase produces design proposals
- Complex features need architecture diagrams
- Technical decisions need documentation

**Lifecycle:** Temporary - archived or deleted after milestone completion

---

### `milestone-XX-<name>/epic-YY-<name>.md`

**Purpose:** Detailed tracking for complex epics
**Updated:** As work progresses
**Format:** Issue-focused

**When to create:**
- Epic has >5 issues
- Epic spans multiple weeks
- Epic has complex dependencies
- Epic needs detailed status documentation

**Contains:**
- Epic description and goals
- Issues breakdown (open/closed)
- Implementation notes
- Testing status
- Known issues
- Technical decisions

**Style:** More detailed than status.md, but still concise

---

## Workflow

### 1. Starting Work

**Always begin by checking:**
```bash
# Read current progress
cat planning/progress.md

# Check active milestone status
cat planning/<goal>/milestone-XX-<name>/status.md

# Check design docs if they exist
ls planning/<goal>/milestone-XX-<name>/design/
```

### 2. Research & Design Phase

**When starting a new feature/epic:**
```bash
# Create design directory
mkdir -p planning/<goal>/milestone-XX-<name>/design/

# Research phase (architecture-research-planner agent)
# Output: planning/<goal>/milestone-XX-<name>/design/<feature>-analysis.md
# Contains: codebase analysis, diagrams, findings

# Design phase
# Output: planning/<goal>/milestone-XX-<name>/design/<feature>-design.md
# Contains: approach, architecture, diagrams, alternatives
```

**Keep separate:**
- `status.md` = Brief reference to design doc + task checklist
- `design/<feature>.md` = Detailed architecture and approach

### 3. Daily Work

**Update `progress.md`:**
- Mark tasks in progress
- Note blockers
- Update next steps
- Timestamp changes

### 4. Milestone Progress

**Update `milestone-XX-<name>/status.md`:**
- When epic/issue completed
- When blockers identified
- Weekly status check
- Risk changes

### 5. Milestone Completion

**Actions:**
1. Update milestone status.md (100% complete)
2. Update goal overview.md (mark milestone ✅)
3. Archive or delete design/ folder (temporary artifacts)
4. Archive or move epic files (optional)
5. Update progress.md (next milestone)

### 6. New Milestone

**Actions:**
1. Create `milestone-XX-<name>/` folder
2. Create `status.md` from template
3. Add to goal overview.md
4. Update progress.md

---

## Planning Principles

### Concise Over Comprehensive

**DO:**
- Use task checklists
- Focus on WHAT needs to be done
- Brief descriptions (3-5 sentences)
- Status indicators (✅ 🔶 🔴 ⬜)

**DON'T:**
- Write implementation details
- Create architecture documents in planning files
- Include code examples
- Write verbose explanations

### Progress Tracking

**Update frequently:**
- `progress.md` - daily or every work session
- `status.md` - weekly or when status changes
- `overview.md` - when milestones added/completed

### Epic Details

**Only create epic files when:**
- Epic is complex (>5 issues, multi-week)
- Need to track technical details
- Multiple dependencies to document

**Otherwise:** Track in milestone status.md only

---

## Examples

### Good `progress.md`

```markdown
# Current Progress

**Last Updated:** 2026-01-14

## Active Work

**Milestone 5:** Initial Video Streaming (70% complete)
**Focus:** Epic &26 - encoderd streaming start/stop

### In Progress

- #140: VisionIpcClient for streaming-only scenarios
- #141: Graceful shutdown for streaming encoders

### Blockers

None

### Next Steps (This Week)

- [ ] Complete #140, #141 (Jan 14-15)
- [ ] Start #142: Multi-process support (Jan 16)
- [ ] Start #121: Config parsing (Jan 16)
```

### Good Milestone List (`overview.md`)

```markdown
## Milestones

**%5: Initial Video Streaming** ✅
- Single SRT stream working end-to-end
- Configuration system via parameters
- Basic testing infrastructure

**%15: Performance Predictability**
- Establish frame rate and latency baselines
- Optimize resource usage (<50% CPU)
- Performance regression tests

**%16: Graceful Degradation**
- Handle network failures without crashes
- Isolate streaming errors from recording
- Validate configuration gracefully
```

### Good Status Update

```markdown
## Status Update (Jan 14)

**Completion:** 70% → 75% (+5%)

**Completed This Week:**
- ✅ #140: VisionIpcClient handling
- ✅ #141: Graceful shutdown

**In Progress:**
- 🔶 #142: Multi-process support (50% done)

**Next:**
- [ ] Complete #142
- [ ] Start #143: Error handling
```

---

## Anti-Patterns to Avoid

❌ **Comprehensive planning documents**
- Too much detail upfront
- Becomes outdated quickly
- Focus on WHAT, not HOW

❌ **Stale status files**
- Not updating progress.md regularly
- Letting status.md get out of sync

❌ **Too many epic files**
- Creating epic files for simple work
- Use milestone status.md for simple tracking

❌ **Implementation details in status tracking**
- Don't put architecture diagrams in status.md
- Don't put code snippets in status.md or progress.md
- Don't put detailed design in status.md
- ✅ DO: Put architecture/design in milestone-XX/design/ folder
- ✅ DO: Keep status.md as task checklists only

---

## Summary

**Key Points:**

1. **Three-level structure:** progress.md → overview.md → status.md
2. **Separate tracking from design:**
   - status.md = WHAT (task checklists, progress %)
   - design/ = HOW (architecture, diagrams, approach)
3. **Concise over comprehensive:** Task checklists in status, details in design/
4. **Update frequently:** progress.md daily, status.md weekly
5. **Epic files:** Only when needed for complex tracking
6. **Design artifacts:** Temporary, milestone-scoped, archived after completion
