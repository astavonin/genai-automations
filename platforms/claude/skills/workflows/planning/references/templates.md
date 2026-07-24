# Planning Structure Template

## Overview

This template defines the planning structure and workflow for tracking epics, milestones, and progress.

## Directory Structure

```
planning/
├── progress.md                           # Active work only: current, last 3 merged, next steps
├── reviews-orphan/                       # Fix reviews for unlinked work (uncommon; hand-managed)
│
├── <epic-slug>/                          # One folder per epic
│   ├── overview.md                       # Epic summary + milestone roadmap
│   ├── reviews/                          # External MR reviews touching this epic
│   │   └── MR<N>-review.yaml             # Final published output only
│   │
│   ├── milestone-XX-<name>/              # One folder per milestone
│   │   ├── status.md                     # Issue table with phase column + dependency diagram
│   │   ├── tickets/                      # YAML files for projctl create
│   │   └── issues/
│   │       └── <NNN-name>/              # One folder per issue
│   │           ├── analysis.md          # Research findings (Phase 1)
│   │           ├── design.md            # Design proposal (Phase 2)
│   │           ├── design-review.md     # Design review (Phase 3)
│   │           ├── code-review.md       # Code review (Phase 5)
│   │           └── codex-review.md      # Codex review of our issue
│   │
│   └── milestone-ZZ-<name>/
│       └── status.md
│
└── <another-epic-slug>/
    └── overview.md
```

## File Purposes

### `progress.md` (Root Level)

**Purpose:** Track current active work across all epics
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

### `<epic-slug>/overview.md`

**Purpose:** High-level roadmap for the epic
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

**Example** (every `#N` / `&N` / `%N` / `!N` reference is rendered as a clickable Markdown link — never bare):
```markdown
# Milestone 15: Performance Predictability

**Status:** 40% complete (2/5 epics done)
**Timeline:** On track
**Risk:** Low

## Epics

- ✅ Epic [&30](URL): Frame rate measurement (5/5 issues closed)
- 🔶 Epic [&31](URL): Latency optimization (2/4 issues closed)
- 🔴 Epic [&32](URL): Resource profiling (0/3 issues - blocked)
- ⬜ Epic [&33](URL): Performance baselines (not started)
- ⬜ Epic [&34](URL): Regression tests (not started)

## Blockers

- Epic [&32](URL) blocked: Profiling tools not available in CI

## Next Actions

- [ ] Complete Epic [&31](URL): Issues [#145](URL), [#146](URL)
- [ ] Resolve Epic [&32](URL) blocker: Install profiling tools
- [ ] Start Epic [&33](URL): Define baseline metrics
```

---

### `milestone-XX-<name>/issues/<NNN-name>/`

**Purpose:** All artifacts for a single issue in one place
**Updated:** During research, design, and review phases
**Format:** Architecture docs, diagrams, reviews

**Contains:**
- `analysis.md` — research findings and codebase analysis (Phase 1)
- `design.md` — design proposal, architecture diagrams, alternatives (Phase 2)
- `design-review.md` — design review output (Phase 3)
- `code-review.md` — code review output (Phase 5)
- `codex-*.md` — codex review outputs (optional)

**Style:** Detailed technical content; filenames inside are generic (no issue-number prefix — the folder name carries the issue number)

**Key Difference from status.md:**
- `status.md` = WHAT phase each issue is in (the table)
- `issues/<NNN-name>/` = HOW — the full design and review record for that issue

**When to create:** One folder per issue that has any planning artifact (analysis, design, or review). Issues with no planning artifacts (simple backlog items) don't need a folder.

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
cat planning/<epic-slug>/milestone-XX-<name>/status.md

# Check issue folders if they exist
ls planning/<epic-slug>/milestone-XX-<name>/issues/
```

### 2. Research & Design Phase

**When starting a new feature/epic:**
```bash
# Create issue directory (NNN = issue number, name = short slug)
mkdir -p planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/

# Research phase (architecture-research-planner agent)
# Output: planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/analysis.md
# Contains: codebase analysis, diagrams, findings

# Design phase
# Output: planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/design.md
# Contains: approach, architecture, diagrams, alternatives
```

**Keep separate:**
- `status.md` = phase column for each issue (the table)
- `issues/<NNN-name>/design.md` = Detailed architecture and approach

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
1. Update milestone status.md (all issues marked merged ✅)
2. Update goal overview.md (mark milestone ✅)
3. Update progress.md (point to next milestone)

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
**Focus:** Epic [&26](URL) - encoderd streaming start/stop

### In Progress

- [#140](URL): VisionIpcClient for streaming-only scenarios
- [#141](URL): Graceful shutdown for streaming encoders

### Blockers

None

### Next Steps (This Week)

- [ ] Complete [#140](URL), [#141](URL) (Jan 14-15)
- [ ] Start [#142](URL): Multi-process support (Jan 16)
- [ ] Start [#121](URL): Config parsing (Jan 16)
```

### Good Milestone List (`overview.md`)

```markdown
## Milestones

**[%5](URL): Initial Video Streaming** ✅
- Single SRT stream working end-to-end
- Configuration system via parameters
- Basic testing infrastructure

**[%15](URL): Performance Predictability**
- Establish frame rate and latency baselines
- Optimize resource usage (<50% CPU)
- Performance regression tests

**[%16](URL): Graceful Degradation**
- Handle network failures without crashes
- Isolate streaming errors from recording
- Validate configuration gracefully
```

### Good Status Update

```markdown
## Status Update (Jan 14)

**Completion:** 70% → 75% (+5%)

**Completed This Week:**
- ✅ [#140](URL): VisionIpcClient handling
- ✅ [#141](URL): Graceful shutdown

**In Progress:**
- 🔶 [#142](URL): Multi-process support (50% done)

**Next:**
- [ ] Complete [#142](URL)
- [ ] Start [#143](URL): Error handling
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
- ✅ DO: Put architecture/design in `issues/<NNN-name>/` folder
- ✅ DO: Keep status.md as the phase table + dependency diagram only
- ✅ DO: Keep progress.md to ≤ 30 lines

---

## Summary

**Key Points:**

1. **Four-level structure:** progress.md → overview.md → status.md → issues/<NNN-name>/
2. **Separate tracking from design:**
   - progress.md = what's active right now (≤ 30 lines)
   - status.md = all issues with phase column + dependency diagram
   - issues/<NNN-name>/ = HOW — design, analysis, reviews for one issue
3. **Navigate by issue:** find everything about #302 in `issues/302-verifier/`
4. **Filenames inside issue folders are generic:** `design.md` not `verifier-design.md`
5. **Tickets in tickets/:** YAML files for projctl create live in `tickets/`, not mixed with design artifacts
6. **MR YAML files live at `planning/<epic-slug>/reviews/`:** operational, ephemeral, grouped by the epic the MR touches (never a top-level `planning/reviews/`)
