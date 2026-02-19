# GenAI Automations

Config backup repo for Claude/Codex AI platform configurations.

## Repository Structure

### Platform Configurations (`platforms/`)

Backup of AI platform configurations that live in `~/.claude/` and `~/.codex/`:

- **`platforms/claude/`** — Claude Code configurations (backup of `~/.claude/`)
  - **CLAUDE.md** — Workflow rules and process guidelines
  - **commands/** — Executable workflow commands
  - **skills/** — Modular knowledge base (languages, domains, workflows)
  - **agents/** — Agent definitions (coder, devops-engineer, architecture-research-planner, reviewer)

- **`platforms/codex/`** — Codex skills and configurations (backup of `~/.codex/`)

### Sync Script (`sync-configs.sh`)

Two-way sync utility for platform configurations.

```bash
./sync-configs.sh sync              # Backup all configs (home → repo)
./sync-configs.sh sync --dry-run    # Preview changes
./sync-configs.sh install --claude  # Restore Claude configs (interactive)
./sync-configs.sh install --force   # Restore without prompts
```

---

## How Claude Works Here

All implementation tasks follow a structured workflow enforced via `CLAUDE.md`:

```
Research → Design → [User approval] → Implement → [Code review] → Verify
```

### Agents

Each phase uses a specialized agent:

| Agent | Model | Role |
|-------|-------|------|
| `architecture-research-planner` | Opus | Investigate codebase, produce analysis docs |
| `coder` | Sonnet | Write code (C++, Go, Rust, Python) |
| `devops-engineer` | Sonnet | CI/CD, Docker, infrastructure |
| `reviewer` | Opus | Design review (before coding) and code review (after) |
| `debugger` | Opus | Root cause analysis, fix recommendations |
| `writer` | Opus | Research and produce structured Markdown drafts |

### Skills

Reusable knowledge modules loaded on demand:

- **`languages/`** — Coding standards for C++, Go, Rust, Python, Zig, Shell
- **`domains/`** — Code quality, architecture, testing, DevOps, quality attributes
- **`workflows/`** — Complete workflow reference, planning templates

### Commands

Slash commands that drive the workflow:

| Command | Action |
|---------|--------|
| `/start` | Load current work context from planning files |
| `/research` | Run architecture-research-planner agent |
| `/design` | Create design proposal |
| `/review-design` | Reviewer agent — mandatory before coding |
| `/implement` | Run coder or devops-engineer agent |
| `/review-code` | Reviewer agent — mandatory after coding |
| `/verify` | Run tests, linters, static analysis |
| `/complete` | Update progress tracking, sync planning backup |
| `/mr` | Create merge/pull request via ci-platform-manager |
| `/diagnose` | Debug failures with debugger agent + cross-model verification |
