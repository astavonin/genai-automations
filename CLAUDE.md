# GenAI Automations — Config Backup Repo

Config backup repo for Claude/Codex platforms. No Python packages live here.

## Workflow Roles

This repo backs a combined Claude + Codex workflow.

- **Claude** is the primary workflow orchestrator for research, investigation, planning, design, and checkpoint coordination. The Claude config also retains implementation, review, verification, and utility commands, including wrappers that delegate implementation and review to Codex through `codex-flow`.
- **Codex** is the narrower implementation and review partner. The tracked Codex config focuses on architecture/design documentation, implementation support for C++, Python, Go, Rust, and Shell, testing/code-quality guidance, and architecture/design review. Code review is integrated from the Claude side through Codex review-request workflows.

The practical operating split is: use Claude for research/investigation and workflow planning; use Codex for repository edits, implementation follow-through, and independent review when delegated through `codex-flow`.

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
  - `skills/` - Architecture/review workflow skills plus C++, Python, Go, Rust, and Shell guidance
  - `templates/` - Input templates for `codex-flow`

### `sync-configs.sh`
Two-way sync utility for platform configurations between this repo and `~/.claude/` / `~/.codex/`.

```bash
./sync-configs.sh sync          # Backup all configs (home → repo)
./sync-configs.sh install       # Restore configs (repo → home)
./sync-configs.sh install --force  # Restore without confirmation prompts (overwrites home configs)
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
