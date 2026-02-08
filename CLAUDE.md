# GenAI Automations Backup Repository

Personal collection of GenAI assistant configurations and automation tools.

## Repository Structure

### `platforms/`
Backup of AI platform configurations:
- **`claude/`** - Claude Code configs (mirrors `~/.claude/`)
  - `CLAUDE.md` - Workflow rules and process guidelines
  - `PLANNING-TEMPLATE.md` - Project planning template
  - `agents/*.md` - Agent definitions (coder, devops-engineer, architecture-research-planner, reviewer)
- **`codex/`** - Codex configurations and skills

### `ci_platform_manager/`
Multi-platform CI automation tool - Python package for GitLab/GitHub workflow management.

**Features:**
- Epic, issue, milestone, and merge request management
- Multi-platform support (GitLab, GitHub)
- Planning folder synchronization with Google Drive
- Modular architecture with specialized handlers

**See `ci_platform_manager/CLAUDE.md` for detailed usage instructions.**

### `glab-management/` (Legacy)
Original GitLab automation tool (deprecated in favor of `ci_platform_manager`)

**See `glab-management/CLAUDE.md` for legacy documentation.**
