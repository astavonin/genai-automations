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

---

## Extracted Tools

The Python tools that were previously in this repo have been extracted into standalone repos:

### ci-platform-manager
**Location:** `~/projects/ci-platform-manager`

Multi-platform CI automation tool for GitLab/GitHub workflow management.
- Managing issues, epics, milestones, merge requests
- Planning folder synchronization with Google Drive

```bash
cd ~/projects/ci-platform-manager
pip install -e ".[dev]"
ci-platform-manager --help
```

### anki-sync
**Location:** `~/projects/anki-sync`

Bidirectional vocabulary synchronization between local YAML files and Anki Desktop.

```bash
cd ~/projects/anki-sync
pip install -e ".[dev]"
anki-sync --help
```
