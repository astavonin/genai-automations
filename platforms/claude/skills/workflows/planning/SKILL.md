---
name: planning
description: Planning directory structure and progress tracking workflow. Use when organizing project work, creating planning files, or updating progress.md and status.md to follow the standard planning structure.
allowed-tools: Glob, Grep, Read, Write, Edit
compatibility: claude-code
metadata:
  version: 1.0.0
  category: workflows
  tags: [planning, workflow, project-management]
---

# Planning Skill

Planning directory structure and progress tracking workflow.

## Directory Structure

```
planning/
├── progress.md                           # Current work tracking
├── <goal-name>/
│   ├── overview.md                       # Milestone roadmap
│   └── milestone-XX-<name>/
│       ├── status.md                     # Progress tracking
│       ├── design/                       # Temporary design docs
│       │   ├── <feature>-analysis.md    # Research findings
│       │   └── <feature>-design.md      # Design proposals
│       └── epic-YY-<name>.md            # Epic details (optional)
```

## File Purposes

### progress.md (Root Level)
**Purpose:** Current active work tracking
**Updated:** Daily/frequently

**Contains:**
- Current active milestone/epic
- Tasks in progress
- Blockers
- Next immediate steps
- Timestamp

**Style:** Brief bullet points

### overview.md
**Purpose:** High-level roadmap for long-term goal
**Updated:** When milestones added/completed

**Contains:**
- Goal description (2-3 sentences)
- Milestone list (3-5 lines per milestone)
- Dependency chain
- Execution phases

**Style:** Concise, focus on WHAT not HOW

### status.md
**Purpose:** Milestone execution progress
**Updated:** Weekly or when status changes

**Contains:**
- Completion percentage
- Epic breakdown with status
- Blockers
- Timeline status
- Risk summary
- Next actions (task checklist)

**Style:** Scannable, checklist format

### design/
**Purpose:** Temporary design and research artifacts
**Updated:** During research and design phases

**Contains:**
- Research findings (`<feature>-analysis.md`)
- Design proposals (`<feature>-design.md`)
- Architecture diagrams (Mermaid)
- Technical decisions

**Style:** Detailed technical content

**Key Difference:**
- `status.md` = WHAT to do (task list, progress %)
- `design/` = HOW to do it (architecture, approach)

**Lifecycle:** Temporary - archived after milestone completion

## Workflow Integration

### Starting Work
1. Read `planning/progress.md`
2. Read `planning/<goal>/milestone-XX/status.md`
3. Check `planning/<goal>/milestone-XX/design/`

### Research & Design
1. Create `design/` directory
2. Research phase → `<feature>-analysis.md`
3. Design phase → `<feature>-design.md`

### Progress Updates
- Daily: Update `progress.md`
- Weekly: Update `status.md`
- Milestone complete: Archive `design/`, update `overview.md`

## Planning Principles

### Concise Over Comprehensive
- Use task checklists
- Focus on WHAT needs to be done
- Brief descriptions (3-5 sentences)
- Status indicators (✅ 🔶 🔴 ⬜)

### Separate Tracking from Design
- Don't put architecture diagrams in `status.md`
- Don't put code snippets in `status.md` or `progress.md`
- Don't put detailed design in `status.md`
- ✅ DO: Put architecture/design in `design/` folder
- ✅ DO: Keep `status.md` as task checklists only

### Update Frequently
- `progress.md` - daily or every work session
- `status.md` - weekly or when status changes
- `overview.md` - when milestones added/completed

## References

See `references/` directory for:
- Detailed planning templates
- Example progress files
- Status file formats
