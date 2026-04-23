# GenAI Automations — Config Backup Repo

Config backup repo for Claude/Codex platforms. No Python packages live here.

## Repository Structure

### `platforms/`
Backup of AI platform configurations:
- **`claude/`** - Claude Code configs (mirrors `~/.claude/`)
  - `CLAUDE.md` - Workflow rules and process guidelines
  - `PLANNING-TEMPLATE.md` - Project planning template
  - `agents/*.md` - Agent definitions (coder, devops-engineer, architecture-research-planner, reviewer)
  - `commands/*.md` - Slash command definitions (mr, load, ticket, review-mr, etc.)
- **`codex/`** - Narrowed Codex config backup (subset of `~/.codex/`)
  - `CODEX.md` - Core Codex guidance and active-skill scope
  - `config.toml` - Default profile and trusted project settings
  - `rules/` - Command allow rules
  - `skills/` - Architecture/review workflow skills plus C++, Python, and Go guidance
  - `templates/` - Input templates for `codex-flow`

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
| `projctl` | `~/projects/projctl` |
| `anki-sync` | `~/projects/anki-sync` |

`projctl` is installed from `~/projects/projctl`.
Use `projctl --help` to see usage and find its CLAUDE.md.
