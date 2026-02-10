# Communication Style

- Avoid validation phrases like "you are right", "great idea", or similar unnecessary affirmations
- Focus on technical accuracy and objective analysis
- Be concise and direct

## Response Format for User Requests

For each user request, automatically provide:

1. **Corrected version**: Make it grammatically correct while avoiding rephrasing if possible. Prefix with "Corrected:"
2. **Spanish translation**: Provide a grammatically correct Spanish translation that stays close to the original request. Prefix with "Traducción:"

**Example:**
```
User: "Explain potential reuse sstate-cache and downloads. Will either these two be reused?"

Response:
Corrected: "Explain the potential for reusing sstate-cache and downloads. Will either of these two be reused?"
Traducción: "Explica el potencial de reutilizar sstate-cache y downloads. ¿Se reutilizará alguno de estos dos?"
```

# Coding Standards

## Language-Specific Guidelines

Reference: `~/.claude/skills/languages/`

- **C++**: Strictly follow The C++ Core Guidelines
- **Python**: Follow PEP 8 and Google Python Style Guide
- **Go**: Follow Effective Go, Go Code Review Comments, and official Go style guide
- **Rust**: Follow Rust API Guidelines
- **Zig**: Follow Zig Style Guide
- **Shell**: Follow shell scripting best practices

See language skills for detailed guidelines, patterns, and examples.

## Code Quality

Reference: `~/.claude/skills/domains/code-quality/`

- Write self-documenting code that needs minimal comments
- **ALWAYS add a comment explaining WHY** when suppressing linter warnings
- Apply formatting using the current project's formatting tool for all files you create or modify

# Workflow

Reference: `~/.claude/skills/workflows/complete-workflow/`

## Available Commands

### Workflow Commands

- `/start` - Sync planning from backup, load current work context, reverify knowledge
- `/research` - Run research phase (architecture-research-planner agent)
- `/design` - Create design proposal
- `/review-design` - Review design before implementation (MANDATORY)
- `/implement` - Run implementation (coder or devops-engineer agent)
- `/review-code` - Review code after implementation (MANDATORY)
- `/verify` - Run verification (tests, linters, static analysis)
- `/complete` - Mark work complete, update progress tracking, backup planning state

### Utility Commands

- `/mr` - Create merge request for current branch via ci-platform-manager
- `/load` - Load ticket information (issue/epic/milestone) via ci-platform-manager

## Quick Reference

```
1. Start:      /start → sync pull → load progress.md, status.md → reverify
2. Research:   /research → architecture-research-planner → analysis.md
3. Design:     /design → create design.md → /review-design
4. Implement:  /implement → coder/devops-engineer → code + tests
5. Review:     /review-code → reviewer → approve/changes/reject
6. Verify:     /verify → tests + linters + static analysis
7. Commit:     User handles git commits (NEVER automatic)
8. Complete:   /complete → update progress.md (propose & confirm) → sync push
```

## Critical Rules

- **NEVER create git commits** - user always handles commits
- **NEVER automatically update progress.md** - always propose explicitly and wait for user confirmation
- **ALL implementations require design review BEFORE code** (Phase 3)
- **ALL code requires code review AFTER implementation** (Phase 5)

## Workflow Execution

For ANY implementation task, automatically follow these phases:

### Phase 0: Start Work
**Step 1: Sync Planning State (Multi-Machine Support)**
```bash
# Pull latest planning state from Google Drive backup
ci-platform-manager sync pull

# Verify sync successful
echo "✓ Planning state synchronized from backup"
```

**Step 2: Load Context**
```bash
cat planning/progress.md
cat planning/<goal>/milestone-XX/status.md
ls planning/<goal>/milestone-XX/design/
```

**Step 3: Reverify Knowledge**
- Check if any planning files were updated from backup
- Review any changes made on other machines
- Confirm understanding of current work state

### Phase 1: Research
- Use architecture-research-planner agent
- Investigate existing codebase patterns and architecture
- Output: `planning/<goal>/milestone-XX/design/<feature>-analysis.md`

### Phase 2: Design
- Main conversation (no agent)
- Propose implementation approach with architecture diagrams
- List files to be modified/created
- Explain rationale and trade-offs
- Output: `planning/<goal>/milestone-XX/design/<feature>-design.md`

### Phase 3: Design Review (CHECKPOINT 1)
- Use reviewer agent with `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- Present design to user
- Wait for explicit user approval
- DO NOT proceed without approval
- If rejected: return to Phase 2

### Phase 4: Implementation
- Use coder agent (code) OR devops-engineer agent (CI/CD)
- Follow approved design
- Include comprehensive unit tests
- Verify build passes
- Apply formatting

### Phase 5: Code Review (CHECKPOINT 2)
- Use reviewer agent with review checklist
- Evaluate all 8 quality attributes
- Block until approved
- If rejected: fix and return for re-review

### Phase 6: Verification
- Run all unit tests
- Run integration tests (if applicable)
- Run static analysis (clang-tidy, pylint, clippy, etc.)
- Verify no regressions
- All checks must pass

### Phase 7: Commit
- User handles all git commits
- NEVER create commits automatically

### Phase 8: Completion
**Step 1: Update Planning Files**
- After user confirms work complete
- Explicitly propose updating `planning/progress.md`
- Wait for user confirmation
- Update `status.md` if needed

**Step 2: Backup Planning State (Multi-Machine Support)**
```bash
# Push updated planning to Google Drive backup
ci-platform-manager sync push

# Verify sync successful
echo "✓ Planning backup complete - available on all machines"
```

**Purpose:** Ensures planning state is backed up and available across machines after completing work

# Agents

Reference: `~/.claude/agents/`

- **architecture-research-planner** (opus): Research, architecture, documentation
- **coder** (sonnet): Implementation (C++, Go, Rust, Python)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure
- **reviewer** (opus): Quality reviews (design and code reviews)

## Agent Declaration Pattern

For EVERY task, explicitly state agent usage:

```
"I'll use <agent-name> agent to <task-description>..."
```

**Examples:**
- "I'll use architecture-research-planner agent to investigate existing error handling patterns..."
- "I'll use coder agent to implement the authentication module following the approved design..."
- "I'll use devops-engineer agent to create the CI pipeline configuration..."
- "I'll use reviewer agent for code review. Please use the Code Review Checklist from ~/.claude/skills/domains/quality-attributes/references/review-checklist.md..."

# Planning Structure

Reference: `~/.claude/skills/workflows/planning/`

**Directory structure:**
```
planning/
├── progress.md                      # Current work (updated daily)
├── <goal>/
│   ├── overview.md                  # Milestone roadmap
│   └── milestone-XX/
│       ├── status.md                # Progress tracking (WHAT to do)
│       └── design/                  # Design docs (HOW to do it)
```

**Key principle:** Separate tracking from design
- `status.md` = WHAT to do (task checklists, progress %)
- `design/` = HOW to do it (architecture, diagrams, approach)

# CI Platform Management

**Tool:** `ci_platform_manager` (Python package)

For ALL managerial tasks related to GitLab/GitHub, use `ci_platform_manager`:
- Creating/updating issues, epics, milestones
- Creating merge requests (MRs) or pull requests (PRs)
- Loading ticket information
- Synchronizing planning folders with Google Drive
- Multi-platform workflow automation

**Usage Instructions:**
- Run `ci-platform-manager --help` to see usage examples and find the full path to CLAUDE.md documentation
- The `--help` output includes a "Documentation:" section with the absolute path to comprehensive usage instructions
- Invoke via `/mr` and `/load` commands, which internally use ci-platform-manager

**Note:** `glab-management` is deprecated and should NOT be used.
