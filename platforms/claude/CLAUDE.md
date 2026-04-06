# Communication Style

- Avoid validation phrases like "you are right", "great idea", or similar unnecessary affirmations
- Focus on technical accuracy and objective analysis
- Be concise and direct

## Markdown Writing

- **Never add manual line breaks within paragraphs.** Do not wrap prose at a fixed column width. Let the Markdown renderer handle line wrapping. Only use newlines to separate paragraphs, list items, headings, or table rows.

## Mermaid Diagrams

- **Always use `<br/>` for line breaks inside node labels.** Never use `\n` — it renders as a literal backslash-n in all Mermaid renderers.

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

## Testing

Reference: `~/.claude/skills/domains/testing/`

- Follow AAA pattern (Arrange, Act, Assert)
- Name tests after behavior and expected outcome
- 80%+ coverage for critical business logic; 100% for public APIs
- Test edge cases: empty input, null values, boundary conditions, error paths

## Architecture & Design

Reference: `~/.claude/skills/domains/architecture/`

- Use Mermaid diagrams for all architecture documentation
- Apply separation of concerns and modularity
- Document trade-offs and alternatives for every design decision

## Quality Attributes

Reference: `~/.claude/skills/domains/quality-attributes/`

- Evaluate all 8 attributes during reviews: supportability, extendability, maintainability, testability, performance, safety, security, observability
- Use review checklist from `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`

## DevOps

Reference: `~/.claude/skills/domains/devops/`

- Prioritize local-CI parity: same images and scripts locally and in CI
- Optimize resource efficiency: multi-stage Docker builds, dependency caching, fast feedback loops
- Follow shell scripting best practices (see `~/.claude/skills/languages/shell/`)

# Workflow

Reference: `~/.claude/skills/workflows/complete-workflow/`

## Available Commands

### Workflow Commands

- `/start` - Sync planning from backup, load current work context, reverify knowledge
- `/refresh` - Reload behavioral config files, restore expected behavior after session drift
- `/research` - Run research phase (architecture-research-planner agent)
- `/design` - Create design proposal
- `/review-design` - Review design before implementation (MANDATORY)
- `/implement` - Run implementation (coder or devops-engineer agent)
- `/review-code` - Review code after implementation (MANDATORY)
- `/verify` - Run verification (linters first, then tests, then static analysis)
- `/complete` - Mark work complete, update progress tracking, backup planning state

### Utility Commands

- `/mr` - Create merge request for current branch via ci-platform-manager
- `/load` - Load ticket information (issue/epic/milestone) via ci-platform-manager
- `/review-mr` - Review an MR and generate YAML findings for `ci-platform-manager comment`
- `/review-fix` - Review a targeted fix (CI failure, local issue) using 3+1 consensus — scope is the fix only, not the full MR
- `/write` - Research a topic and produce a structured Markdown draft (writer agent)
- `/diagnose` - Investigate a failure using debugger agent + Codex cross-model verification
- `/ci-debug` - Debug failed CI pipeline jobs: detect failures, fetch logs, launch debugger agent
- `/tasks-sync` - Sync local planning task state with remote ticket system (push completions, discover epic children)

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

- **Always propose commit message and wait for explicit approval before committing**
- **NEVER automatically update progress.md** - always propose explicitly and wait for user confirmation
- **ALWAYS declare agent before use**: state "I'll use <agent-name> agent to <task-description>..." before every agent invocation
- **ALL implementations require design review BEFORE code** (Phase 3)
- **ALL code requires code review AFTER implementation** (Phase 5)
- **NEVER use `isolation: "worktree"` when invoking coder or devops-engineer agents** — this strands all changes in a throw-away branch. Omit the `isolation` parameter for all implementation agents so changes land directly in the user's working branch.

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
- After writing the design file, ask the user if they want to `open` it

### Phase 3: Design Review (CHECKPOINT 1)
- Use reviewer agent with `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- **Write review report to `planning/<goal>/milestone-XX/reviews/<feature>-design-review.md`**
- After writing, ask the user if they want to `open` the file
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
- **Write review report to `planning/<goal>/milestone-XX/reviews/<feature>-code-review.md`**
- After writing, ask the user if they want to `open` the file
- Block until approved
- If rejected: fix and return for re-review

### Phase 6: Verification
- Run linters FIRST (must pass before tests): clang-tidy, pylint/mypy, clippy, golangci-lint, shellcheck
- Apply auto-formatting if needed
- Run all unit tests
- Run integration tests (if applicable)
- Run static analysis (zero errors)
- Verify no regressions
- All checks must pass

### Phase 7: Commit
- **Commit message format:** single line — `<short description>. Ref #<issue-number>`
  - Example: `Add retry logic for failed API requests. Ref #42`
- Always propose a commit message and wait for explicit user approval before committing
- After approval, stage the relevant files and create the commit

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
- **coder** (sonnet): Implementation (C++, Go, Rust, Python, Zig)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure
- **reviewer** (opus): Quality reviews (design and code reviews)
- **debugger** (opus): Root cause analysis, hypothesis-driven investigation, fix recommendations
- **writer** (opus): Info collection, code snippet extraction, Markdown draft writing

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
│   └── milestone-XX-<name>/
│       ├── status.md                # Progress tracking (WHAT to do)
│       └── design/                  # Design docs (HOW to do it)
```

**Key principle:** Separate tracking from design
- `status.md` = WHAT to do (task checklists, progress %)
- `design/` = HOW to do it (architecture, diagrams, approach)

# Post-Write Actions

After writing certain files, always ask the user if they want to open the file with `open <path>` before continuing:

| File type | When to ask |
|-----------|-------------|
| Design docs (`planning/**/design/*.md`) | After Phase 2 design doc is written |
| Design review reports (`planning/**/reviews/*-design-review.md`) | After Phase 3 review is written |
| Code review reports (`planning/**/reviews/*-code-review.md`) | After Phase 5 review is written |
| MR review YAML (`planning/reviews/MR*.yaml`) | After `/review-mr` YAML is written |
| Issue/Epic YAML files (any YAML created for `ci-platform-manager create`) | After the YAML is written |

Ask exactly once per file, immediately after writing. Do not open automatically — always ask first.

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

**Critical rule:** If a required operation is not supported by ci-platform-manager, extend it first (source at `~/projects/ci-platform-manager`) rather than working around it with direct `glab` CLI or GitLab API calls. Never bypass ci-platform-manager.

**Note:** `glab-management` is deprecated and should NOT be used.
