# GenAI Automations — Config Backup Repo

Config backup repo for Claude/Codex platforms. No Python packages live here.

## Repository Structure

### `platforms/`
Backup of AI platform configurations:
- **`claude/`** - Claude Code configs (mirrors `~/.claude/`)
  - `CLAUDE.md` - Workflow rules and process guidelines
  - `PLANNING-TEMPLATE.md` - Project planning template
  - `agents/*.md` - Agent definitions (coder, devops-engineer, architecture-research-planner, reviewer)
- **`codex/`** - Codex configurations and skills

### `sync-configs.sh`
Two-way sync utility for platform configurations between this repo and `~/.claude/` / `~/.codex/`.

```bash
./sync-configs.sh sync          # Backup all configs (home → repo)
./sync-configs.sh install       # Restore configs (repo → home)
./sync-configs.sh sync --dry-run
```

### `planning/`
Project planning documents for ongoing and completed work.

---

## Extracted Tools (now in separate repos)

| Tool | Location |
|------|----------|
| `ci-platform-manager` | `~/projects/ci-platform-manager` |
| `anki-sync` | `~/projects/anki-sync` |

The `ci_platform_manager` package is installed from `~/projects/ci-platform-manager`.
Use `ci-platform-manager --help` to see usage and find its CLAUDE.md.
