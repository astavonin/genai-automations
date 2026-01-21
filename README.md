# GenAI Automations

Personal collection of GenAI assistant configurations and automation tools.

## Repository Structure

### Assistant Configurations (`assistants/`)

Backup repository for AI assistant configurations that live in `~/.claude/` and `~/.codex/`:

- **`assistants/claude/`** - Claude Code agent configurations (backup of `~/.claude/`)
  - Workflow rules and process guidelines
  - Planning templates
  - Agent definitions: coder, devops-engineer, architecture-research-planner, reviewer

- **`assistants/codex/`** - Codex skills and configurations (backup of `~/.codex/`)

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

## Agent Overview

Custom agent configurations enforce explicit quality constraints and scope responsibilities.

### Workflow

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

- **`coder`** - Systems programming in C++, Go, Rust, Python, Zig
  - Enforces: C++ Core Guidelines, PEP 8, Go style guide, Rust API Guidelines, Zig Style Guide
  - Quality: Memory safety, algorithmic efficiency, 80% code coverage

- **`devops-engineer`** - Infrastructure, CI/CD, containerization
  - Enforces: Local-CI parity, resource efficiency, smooth developer experience
  - Quality: Build optimization, proper documentation

- **`architecture-research-planner`** - System design and documentation
  - Enforces: Visual artifacts over prose, Mermaid diagrams, C4 model preference
  - Quality: Concise documentation, architectural clarity

- **`reviewer`** - Mandatory code review after implementation
  - Evaluates: Supportability, Extendability, Maintainability, Testability
  - Quality: Performance, Safety, Security, Observability
