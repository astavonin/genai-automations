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
├── progress.md                           # Active work only: current, last 3 merged, next steps
├── reviews-orphan/                       # Fix reviews for unlinked work (uncommon; hand-managed)
├── <epic-slug>/
│   ├── overview.md                       # Epic summary + milestone roadmap
│   ├── reviews/                          # External MR reviews touching this epic
│   │   └── MR<N>-review.yaml             # Final published output only
│   └── milestone-XX-<name>/
│       ├── status.md                     # Issue list with phase + dependency diagram
│       ├── tickets/                      # YAML files for projctl create
│       └── issues/
│           └── <NNN-name>/              # One folder per issue
│               ├── analysis.md          # Research findings (Phase 1)
│               ├── design.md            # Design proposal (Phase 2)
│               ├── design-review.md     # Design review (Phase 3)
│               ├── code-review.md       # Code review (Phase 5)
│               └── codex-review.md      # Codex review of our issue
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
**Purpose:** High-level roadmap for the epic
**Updated:** When milestones added/completed

**Contains:**
- Goal description (2-3 sentences)
- Milestone list (3-5 lines per milestone)
- Dependency chain
- Execution phases

**Style:** Concise, focus on WHAT not HOW

### status.md
**Purpose:** Full milestone picture — all issues, phases, dependency order
**Updated:** When issue phase changes

**Contains:**
- Issue table with phase column (see canonical vocabulary below)
- Dependency order diagram
- Artifact index (links to issue folders)

**Style:** Scannable table; no backlog lists in progress.md

### Canonical Phase Vocabulary

Every command that updates the Phase column in `status.md` MUST use exactly these labels:

| Phase | Meaning | Set by |
|-------|---------|--------|
| `backlog ⏳` | Not started | Initial state |
| `research ✅` | `analysis.md` written | `/research` |
| `design 📝` | `design.md` written, awaiting review | `/design` |
| `changes requested 🔄` | Review returned CHANGES REQUESTED (design or code) | `/review-design` or `/review-code` |
| `implementing 🔨` | Design approved, implementation in progress | `/review-design` APPROVED |
| `code review ⏳` | Implementation done, awaiting code review | `/implement` |
| `code review ✅` | Code review APPROVED, ready for MR | `/review-code` APPROVED |
| `in review 👀` | MR open, awaiting human review | `/mr` |
| `merged ✅` | MR merged and closed | `/complete` |
| `rejected ❌` | Review returned REJECTED — redesign required | `/review-design` or `/review-code` |

Do not invent new phase labels. If a transition is not listed here, leave the Phase column unchanged and record the event in the Notes column only.

### issues/<NNN-name>/
**Purpose:** All artifacts for one issue in one place
**Updated:** During research, design, review phases

**Contains:**
- `analysis.md` — research findings (Phase 1)
- `design.md` — design proposal (Phase 2)
- `design-review.md` — design review (Phase 3)
- `code-review.md` — code review (Phase 5)
- `codex-*.md` — codex review outputs (optional)

**Style:** Detailed technical content; filenames inside the folder are generic (no issue-number prefix)

**Key Difference:**
- `status.md` = WHAT phase each issue is in
- `issues/<NNN-name>/` = HOW — the full design and review record for that issue

## Workflow Integration

### Starting Work
1. Read `planning/progress.md`
2. Read `planning/<epic-slug>/milestone-XX/status.md`
3. Check `planning/<epic-slug>/milestone-XX/issues/`
4. Load live state for every active issue and open MR: `projctl load issue N` / `projctl load mr N`

### Research & Design
1. Create `issues/<NNN-name>/` directory
2. Research phase → `issues/<NNN-name>/analysis.md`
3. Design phase → `issues/<NNN-name>/design.md`

### Progress Updates
- Active issue changes: Update `progress.md`
- Issue phase changes: Update phase column in `status.md`

## File Location Rules

**ALL project-related files go under `planning/`, never `/tmp` or other system directories.**

This includes:
- YAML input files for `projctl` (tickets, epics) → `planning/<epic-slug>/milestone-XX/tickets/`
- MR review YAMLs → `planning/<epic-slug>/reviews/MR<N>-review.yaml` (grouped by the epic the MR touches; never at top level)
- Design, analysis, review artifacts → `planning/<epic-slug>/milestone-XX/issues/<NNN-name>/`

`/tmp` is for throwaway system scratch only. If a file is related to the project — even if it is a draft pending user confirmation — it belongs in `planning/`.

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
- ✅ DO: Put architecture/design in `issues/<NNN-name>/` folder
- ✅ DO: Keep `status.md` as the phase table + dependency diagram only
- ✅ DO: Keep `progress.md` to ≤ 30 lines — active item, last 3 merged, next steps

### Update Frequently
- `progress.md` - daily or every work session
- `status.md` - weekly or when status changes
- `overview.md` - when milestones added/completed

## References

See `references/` directory for:
- Detailed planning templates
- Example progress files
- Status file formats
