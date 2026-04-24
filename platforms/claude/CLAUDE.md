# Memory Precedence

**`~/.claude/CLAUDE.md` takes precedence over all project memories.** Project memories are for project-specific context only (decisions, bugs, local conventions) — not behavioral rules. When a rule is generalized into this file, delete the project memory entry so it cannot conflict.

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

- `/mr` - Create merge request for current branch via projctl
- `/load` - Load ticket information (issue/epic/milestone) via projctl
- `/ticket` - Create milestones, epics, and/or issues as YAML for `projctl create`
- `/review-mr` - Review an MR and generate YAML findings for `projctl comment`
- `/review-fix` - Review a targeted fix (CI failure, local issue) using 3+1 consensus — scope is the fix only, not the full MR
- `/write` - Research a topic and produce a structured Markdown draft (writer agent)
- `/diagnose` - Investigate a failure using debugger agent + Codex cross-model verification
- `/ci-debug` - Debug failed CI pipeline jobs: detect failures, fetch logs, launch debugger agent
- `/tasks-sync` - Sync local planning task state with remote ticket system (push completions, discover epic children)
- `/codex-review` - Run a standalone Codex review via codex-flow from a review request document (REVIEW-REQUEST-TEMPLATE.md)
- `/codex-implement` - Run a standalone Codex implementation via codex-flow from a design document (DESIGN-TEMPLATE.md)

## Quick Reference

```
1. Start:      /start → auto-compact → drift-check → sync pull (if needed) → load progress.md, status.md → reverify
2. Research:   /research → architecture-research-planner → analysis.md
3. Design:     /design → create design.md → push planning → /review-design
4. Implement:  /implement → gated auto-compact → coder/devops-engineer → code + tests
5. Review:     /review-code → reviewer → APPROVED/CHANGES REQUESTED/REJECTED marker → push planning
6. Verify:     /verify → tests + linters + static analysis
7. Commit:     User handles git commits (NEVER automatic)
8. Complete:   /complete → update progress.md (propose & confirm) → sync push → gated auto-compact
```

## Critical Rules

- **After every compaction (auto or manual), run `/refresh` as the first action before responding to the user**
- **Always propose commit message and wait for explicit approval before committing**
- **NEVER automatically update progress.md** - always propose explicitly and wait for user confirmation
- **ALWAYS declare agent before use**: state "I'll use <agent-name> agent to <task-description>..." before every agent invocation
- **ALL implementations require design review BEFORE code** (Phase 3)
- **ALL code requires code review AFTER implementation** (Phase 5)
- **NEVER use `isolation: "worktree"` when invoking coder or devops-engineer agents** — this strands all changes in a throw-away branch. Omit the `isolation` parameter for all implementation agents so changes land directly in the user's working branch.
- **Review files MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED` as first non-empty line after H1, within first 20 lines** — machine-readable, no emoji. Pre-existing reviews without this marker cause gates to skip (fail-safe). See §4 below.
- **Auto-compaction fires at three phase boundaries** without a prompt: `/start` (unconditional), `/implement` (gated), `/complete` (gated). Always followed by a `✓ Compacted at <phase>` confirmation line.

## Workflow Safety — New Behaviors (workflow-safety milestone)

### Review File Status-Marker Convention (§4)

Every review file written by `/review-design` or `/review-code` MUST contain:

```
**Status:** APPROVED
```

as the **first non-empty line after the H1 title**, within the first 20 lines. Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED`. No emoji, no verb/noun mixing. Machine-readable via `head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`.

**Migration note:** This marker is NOT retrofitted to pre-existing review files. Reviews written before this convention was adopted do not have the canonical marker; gates fail-safe (skip compaction) for those files. Users on in-flight milestones may manually add the marker to opt in.

### Gate-Decision Log (§8.1)

Every gate evaluation at a compaction point appends one line to:

**Path:** `planning/.workflow-safety.log`

**Format:**
```
<ISO-8601 timestamp> <skill> <boundary> <decision> [reason]
```

Examples:
```
2026-04-22T14:30:12Z /start start FIRED
2026-04-22T15:02:44Z /implement implement-begin SKIPPED precondition-2-failed:CHANGES_REQUESTED
2026-04-22T16:18:03Z /complete complete-end SKIPPED precondition-3-failed:STATUS=local-ahead
2026-04-22T16:20:11Z /complete complete-end FIRED
```

Boundary values: `start`, `implement-begin`, `complete-end`. Decision values: `FIRED`, `SKIPPED`.

### Warning Surface Convention (§8.2)

All gate-skip and push-failure warnings use this three-line visual block:

```
⚠️  workflow-safety: <event>
    reason: <one-line reason>
    recovery: <one-line recommendation>
```

Consistent formatting makes warnings scannable across any skill output.

## Workflow Execution

For ANY implementation task, automatically follow these phases:

### Phase 0: Start Work
**Step 0-pre: Auto-compact (unconditional, first)**
Compact the session before any other action. Log the gate decision to `planning/.workflow-safety.log`. Emit `✓ Compacted at start` on success. On compact failure, log, warn, and continue.

**Step 1: Sync Planning State (Multi-Machine Support) — drift-check flow**
Do NOT blindly pull. First detect pre-feature projctl, then run drift check:
```bash
# Check if projctl sync status is available
timeout 30 projctl sync status
# Parse first line: in-sync → no-op; remote-ahead → pull; local-ahead → HALT; diverged → HALT
# On timeout → blind pull with caveat warning
# On pre-feature projctl (exit 2 / "invalid choice") → blind pull, no warning
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
- Use architecture-research-planner agent
- Output: `planning/<goal>/milestone-XX/design/<feature>-design.md`
- **Structure:** follow `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md` exactly — all 9 sections required
- After writing the design file, ask the user if they want to `open` it
- **Last step:** push planning to backup via the push-planning fragment (best-effort, non-blocking)

### Phase 3: Design Review (CHECKPOINT 1)
- Use reviewer agent with `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- **Write review report to `planning/<goal>/milestone-XX/reviews/<feature>-design-review.md`**
- **Review file MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED` as first non-empty line after H1, within first 20 lines** (machine-readable, no emoji). Verify with `head -20 <file> | grep -m 1 '^\*\*Status:\*\*'` before declaring done.
- After writing, ask the user if they want to `open` the file
- Present design to user
- Wait for explicit user approval
- DO NOT proceed without approval
- If rejected: return to Phase 2
- **Last step:** push planning to backup via the push-planning fragment (best-effort, non-blocking)

### Phase 4: Implementation
- **First step:** gated auto-compact (§7.3, §7.4) — both preconditions must pass: (1) design.md + design-review.md exist on disk, mtime-ordered, status=APPROVED; (2) no code-review exists OR code-review status=APPROVED. Log gate decision. Skip silently with §8.2 warning if gate fails.
- Use coder agent (code) OR devops-engineer agent (CI/CD)
- Follow approved design
- Include comprehensive unit tests
- Verify build passes
- Apply formatting

### Phase 5: Code Review (CHECKPOINT 2)
- Use reviewer agent with review checklist
- Evaluate all 8 quality attributes
- **Write review report to `planning/<goal>/milestone-XX/reviews/<feature>-code-review.md`** (single file, always overwritten — no versioning suffixes)
- **Review file MUST contain `**Status:** APPROVED|CHANGES REQUESTED|REJECTED`** (verify before declaring done)
- After writing, ask the user if they want to `open` the file
- Block until approved
- If rejected: fix and return for re-review
- **Last step:** push planning to backup (elevated warning on failure: also recommend `projctl sync status` before `/complete`)

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
projctl sync push
# Record push success/failure for the compaction gate (Step 3)
```

**Step 3: Gated auto-compact (last step, §7.5)**
Three disk-checkable conditions must all pass:
1. `git status --porcelain` — no uncommitted tracked changes outside `planning/`
2. `projctl sync push` (Step 2) returned exit code 0
3. `projctl sync status` reports `STATUS: in-sync`

If all pass → log `FIRED` → compact → emit `✓ Compacted at complete-end`. If any fail → log `SKIPPED <condition>` → surface §8.2 warning → leave session uncompacted (acceptable). If compact itself fails → log + warn + accept.

**Purpose:** Ensures planning state is backed up and available across machines after completing work

# Agents

Reference: `~/.claude/agents/`

- **architecture-research-planner** (opus): Research, architecture, documentation — **including writing architecture docs and service READMEs**
- **coder** (sonnet): Implementation (C++, Go, Rust, Python, Zig)
- **devops-engineer** (sonnet): CI/CD, Docker, infrastructure
- **reviewer** (opus): Quality reviews (design and code reviews)
- **debugger** (opus): Root cause analysis, hypothesis-driven investigation, fix recommendations
- **writer** (opus): Info collection, code snippet extraction, Markdown draft writing

> **Rule:** Any task that produces architecture documentation or a service README MUST be delegated to architecture-research-planner. Never write these files inline with Write/Edit tools.

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
| Issue/Epic YAML files (any YAML created for `projctl create`) | After the YAML is written |

Ask exactly once per file, immediately after writing. Do not open automatically — always ask first.

# CI Platform Management

**Tool:** `projctl` (Python package)

For ALL managerial tasks related to GitLab/GitHub, use `projctl`:
- Creating/updating issues, epics, milestones
- Creating merge requests (MRs) or pull requests (PRs)
- Loading ticket information (issues `#N`, epics `&N`, milestones `%N`, MRs `!N`)
- Searching issues, epics, and milestones by text/state
- Managing milestones: activate/close state, set due-date, assign issues to milestones
- Synchronizing planning folders with Google Drive
- Multi-platform workflow automation

**Usage Instructions:**
- Run `projctl --help` to see usage examples and find the full path to CLAUDE.md documentation
- The `--help` output includes a "Documentation:" section with the absolute path to comprehensive usage instructions
- Invoke via `/mr` and `/load` commands, which internally use projctl

**Critical rule:** If a required operation is not supported by projctl, extend it first (source at `~/projects/projctl`) rather than working around it with direct `glab` CLI or GitLab API calls. Never bypass projctl.

**Note:** `glab-management` is deprecated and should NOT be used.
