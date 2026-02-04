# GenAI Automations

Personal collection of GenAI assistant configurations and automation tools.

## Repository Structure

### Platform Configurations (`platforms/`)

Backup repository for AI platform configurations that live in `~/.claude/` and `~/.codex/`:

- **`platforms/claude/`** - Claude Code configurations (backup of `~/.claude/`)
  - **CLAUDE.md** - Simplified reference guide for workflows and standards
  - **commands/** - Executable workflow commands (10 total)
    - **Workflow:** `/start`, `/research`, `/design`, `/review-design`, `/implement`, `/review-code`, `/verify`, `/complete`
    - **Utility:** `/mr` (create merge request), `/load` (load ticket info)
  - **skills/** - Modular knowledge base (13 skills)
    - **languages/** (6) - C++, Python, Go, Rust, Zig, Shell
    - **domains/** (5) - Code quality, quality attributes, architecture, testing, devops
    - **workflows/** (2) - Complete workflow reference, planning templates
  - **agents/** (4) - coder, devops-engineer, architecture-research-planner, reviewer
  - **README.md** - Detailed documentation of structure and usage

- **`platforms/codex/`** - Codex skills and configurations (backup of `~/.codex/`)

#### Sync Script

**`sync-configs.sh`** - Two-way sync utility for platform configurations

**Backup configurations (home → repo):**
```bash
./sync-configs.sh sync              # Backup all configs
./sync-configs.sh sync --dry-run    # Preview changes
./sync-configs.sh sync --claude     # Backup Claude only
```

**Restore configurations (repo → home):**
```bash
./sync-configs.sh install --dry-run   # Preview restore (safe)
./sync-configs.sh install --claude    # Restore Claude only (interactive)
./sync-configs.sh install --force     # Restore without prompts (dangerous!)
```

**Features:**
- Two-way sync (backup and restore)
- Selective platform sync (Claude and/or Codex)
- Dry-run mode for safe preview
- Interactive confirmation for installs
- Automatic exclusion of sensitive files (credentials, history, cache)

### Tools

#### glab-management

GitLab automation tool for managing epics, issues, and milestones programmatically.

**Features:**
- Create issues from YAML definitions with dependency tracking
- Load and display issue/epic/milestone information in markdown format
- Search issues, epics, and milestones by text query
- Milestone epic breakdown for progress tracking

**See [glab-management/CLAUDE.md](glab-management/CLAUDE.md) for detailed documentation.**

**Requirements:**
- Python 3 (PyYAML)
- [glab CLI](https://gitlab.com/gitlab-org/cli) installed and authenticated

## Claude Setup Overview

The Claude setup uses a modular, command-based architecture with executable workflow commands and reusable knowledge skills.

### Commands

**Workflow Commands:**
- `/start` - Load current work context
- `/research` - Run research phase (architecture-research-planner)
- `/design` - Create design proposal
- `/review-design` - Design review checkpoint (MANDATORY)
- `/implement` - Run implementation (coder/devops-engineer)
- `/review-code` - Code review checkpoint (MANDATORY)
- `/verify` - Run tests and static analysis
- `/complete` - Mark work complete

**Utility Commands:**
- `/mr` - Create merge request for current branch (GitLab)
- `/load` - Load ticket information (issue/epic/milestone) using glab-management

### Workflow Phases

All implementation tasks follow a structured workflow with two mandatory checkpoints:

```
┌─────────────────────┐
│ 1. Research         │ ← architecture-research-planner
│ 2. Design           │
└──────────┬──────────┘
           ↓
    ┌──────────────┐
    │ ⚠️  USER     │
    │   APPROVAL   │ ← Checkpoint 1
    └──────┬───────┘
           ↓
┌──────────────────────┐
│ 3. Implementation    │ ← coder / devops-engineer
└──────────┬───────────┘
           ↓
    ┌──────────────┐
    │ ⚠️  CODE     │
    │   REVIEW     │ ← reviewer (Checkpoint 2)
    └──────┬───────┘
           ↓
┌──────────────────────┐
│ 4. Verify & Tests    │
│ 5. User Commits      │
└──────────────────────┘
```

**Key Principles:**
- **Two mandatory checkpoints:** User approval before coding, code review after implementation
- **Specialized agents:** Different agents handle specific phases based on expertise
- **User control:** User handles all git commits and final task completion
- **Quality gates:** No bypassing checkpoints - rejected work loops back for revision

### Agent Responsibilities

- **`coder`** (sonnet) - Systems programming in C++, Go, Rust, Python, Zig
  - Algorithmic efficiency, correctness, and architectural quality
  - Does NOT handle infrastructure or deployment

- **`devops-engineer`** (sonnet) - Infrastructure, CI/CD, containerization
  - Docker, CI/CD pipelines, deployment scripts, environment setup
  - Optimizes build processes and resource usage

- **`architecture-research-planner`** (opus) - Research, architecture, documentation
  - Reverse engineers codebases, creates Mermaid diagrams
  - Produces production-level architecture documentation
  - Does NOT write production code

- **`reviewer`** (opus) - Quality reviews (design and code)
  - MANDATORY before implementation (design review) and after implementation (code review)
  - Evaluates: Supportability, Extendability, Maintainability, Testability, Performance, Safety, Security, Observability
  - NEVER writes code - only provides feedback
