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
  - `CLAUDE.md` - Workflow rules, phase gates, commit format, agent dispatch, quality standards
  - `agents/*.md` - Agent definitions (architecture-research-planner, coder, devops-engineer, reviewer, debugger, writer)
  - `commands/*.md` - 27 slash command definitions (start, research, design, implement, review-*, verify, complete, and utilities)
  - `skills/` - Modular knowledge base: languages (C++, Go, Rust, Python, Zig, Shell), domains (architecture, testing, code-quality, devops, quality-attributes), workflows (complete-workflow, planning, review gates, push-planning)
  - `hooks/` - Git hooks: pre-commit scans platforms/ for path leaks
  - `scripts/` - Helper scripts: codex-pipe, projctl-post-create.sh
  - `memory/` - Persistent memory files synced across sessions
  - `settings.json` - Claude Code permissions, hooks, env vars
- **`codex/`** - Narrowed Codex config backup (subset of `~/.codex/`)
  - `CODEX.md` - Core Codex guidance and active-skill scope
  - `config.toml` - Default profile and trusted project settings
  - `rules/` - Command allow rules
  - `skills/` - Architecture/review skills plus C++, Python, Go, Rust, Shell, Zig guidance
  - `templates/` - Input templates for `codex-flow` (implementation-input.md, review-input.md)

### `sync-configs.sh`
Two-way sync utility for platform configurations between this repo and `~/.claude/` / `~/.codex/`.

```bash
./sync-configs.sh sync              # Backup all configs (home → repo)
./sync-configs.sh sync --dry-run    # Preview what would be backed up
./sync-configs.sh install           # Restore configs (repo → home, interactive)
./sync-configs.sh install --force   # Restore without confirmation prompts
```

### `planning/`
Project planning documents for ongoing and completed work.

---

## Extracted Tools (now in separate repos)

| Tool | Location |
|------|----------|
| `projctl` | `~/projects/projctl` |

`projctl` is installed from `~/projects/projctl`.
Use `projctl --help` to see usage and find its CLAUDE.md.
