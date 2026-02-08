# CI Platform Manager

Multi-platform CI automation tool for GitLab/GitHub workflow management.

## Quick Start

```bash
# Install with dev dependencies
pip install -e ".[dev]"

# Basic usage
python3 -m ci_platform_manager --help
ci-platform-manager --help  # If installed

# Planning sync (most common)
ci-platform-manager sync push
ci-platform-manager sync pull --dry-run
```

## Architecture

**Package Structure:**
```
ci_platform_manager/
├── __init__.py
├── __main__.py           # Entry point
├── cli.py                # CLI interface with command dispatch
├── config.py             # Multi-platform configuration
├── exceptions.py         # PlatformError and custom exceptions
├── handlers/             # Modular operation handlers
│   ├── sync.py          # Planning folder sync (NEW)
│   ├── loader.py        # Load issues/epics/milestones/MRs
│   ├── creator.py       # Create issues/epics
│   ├── search.py        # Search operations
│   ├── comment.py       # Post MR comments
│   └── mr_handler.py    # Create merge requests
├── utils/               # Shared utilities
│   ├── config_migration.py
│   ├── git_helpers.py
│   ├── logging_config.py
│   └── validation.py
└── formatters/          # Output formatters
```

**Design Principles:**
- Modular handler-based architecture
- Multi-platform support (GitLab, GitHub)
- Dry-run mode for all operations
- Type hints throughout
- Comprehensive error handling

## Configuration

### Config File Resolution

Search order (first found wins):
1. `--config` flag (explicit path)
2. `./glab_config.yaml` (project-local, legacy)
3. `./config.yaml` (project-local, new)
4. `~/.config/ci_platform_manager/config.yaml` (user-wide)
5. `~/.config/glab_config.yaml` (legacy)

### Config Structure

```yaml
# Platform selection
platform: gitlab  # or github

# GitLab-specific settings
gitlab:
  default_group: "group/project"
  labels:
    default: ["type::feature", "development-status::backlog"]
    default_epic: ["type::epic"]
    allowed: []  # Empty = no validation

# GitHub-specific settings (future)
github:
  default_org: "organization"

# Common settings
common:
  issue_template:
    required_sections:
      - "Description"
      - "Acceptance Criteria"

# Planning sync settings
planning_sync:
  gdrive_base: ~/GoogleDrive  # Machine-specific path
```

## Commands

### Issue/Epic Management

**Create issues from YAML:**
```bash
ci-platform-manager create epic_definition.yaml
ci-platform-manager create --dry-run epic_definition.yaml
ci-platform-manager create --config custom_config.yaml epic_definition.yaml
```

**Load information:**
```bash
# Issue
ci-platform-manager load 113
ci-platform-manager load #113
ci-platform-manager load https://gitlab.com/group/project/-/issues/113

# Epic
ci-platform-manager load &21
ci-platform-manager load 21 --type epic

# Milestone
ci-platform-manager load %123
ci-platform-manager load 123 --type milestone

# Merge Request
ci-platform-manager load !134
ci-platform-manager load 134 --type mr
```

**Search:**
```bash
ci-platform-manager search issues "streaming"
ci-platform-manager search issues "bug" --state opened --limit 10
ci-platform-manager search epics "video"
ci-platform-manager search milestones "v1.0" --state active
```

### Merge Request Operations

**Post review comments:**
```bash
ci-platform-manager comment planning/reviews/MR134-review.yaml
ci-platform-manager comment review.yaml --mr 134
ci-platform-manager comment review.yaml --dry-run
```

**Create merge request:**
```bash
ci-platform-manager create-mr --title "Add feature X" --draft
ci-platform-manager create-mr --fill --reviewer alice --label "type::feature"
ci-platform-manager create-mr --target-branch develop --milestone "v2.0"
ci-platform-manager create-mr --dry-run
```

### Planning Folder Synchronization

**Sync commands:**
```bash
# Push local planning → Google Drive
ci-platform-manager sync push
ci-platform-manager sync push --dry-run

# Pull Google Drive → local planning
ci-platform-manager sync pull
ci-platform-manager sync pull --dry-run
```

## Planning Sync Deep Dive

### Purpose

Synchronize proprietary planning folders across multiple machines using Google Drive as centralized backup.

**Use cases:**
- Work on planning docs from multiple machines (desktop, laptop)
- Backup planning folders automatically
- Keep planning folders in sync without git commits

### Architecture

**Auto-Detection:**
- Repository name: Extracted from git repository directory name
- Planning folder: Always `./planning/` from repository root
- No manual configuration of repo name or paths needed

**Google Drive Structure:**
```
${GDRIVE_BASE}/backup/planning/
├── genai-automations/    # Auto-created on first push
│   ├── progress.md
│   └── ci-platform-refactor/
└── other-repos/          # Other repositories sync here automatically
```

**Sync Strategy:**
- Uses `rsync` with `--delete` flag (last write wins)
- Excludes: `*.swp`, `*~`, `.DS_Store`
- Efficient incremental sync (only changed files)
- No version history (Google Drive provides 30-day file versioning)

### Setup (Per Machine)

**Initial setup on new machine:**

1. Install dependencies:
   ```bash
   # Ensure rsync is installed
   which rsync || sudo apt install rsync  # Ubuntu/Debian

   # Ensure Google Drive is mounted and synced
   ls ~/GoogleDrive  # Verify path
   ```

2. Configure Google Drive path in `config.yaml`:
   ```yaml
   planning_sync:
     gdrive_base: ~/GoogleDrive  # Adjust for your mount point
   ```

3. Pull existing planning folder:
   ```bash
   cd ~/projects/genai-automations
   ci-platform-manager sync pull --dry-run  # Preview
   ci-platform-manager sync pull            # Execute
   ```

**Repeat for each repository with planning folder**

### Regular Workflow

**Machine A (after making changes):**
```bash
cd ~/projects/genai-automations
# Work on planning docs...
ci-platform-manager sync push
# Google Drive auto-syncs to cloud (usually within seconds)
```

**Machine B (before starting work):**
```bash
cd ~/projects/genai-automations
ci-platform-manager sync pull   # Get latest changes
# Work on planning docs...
ci-platform-manager sync push   # Push changes back
```

**Best Practices:**
- Always `pull` before starting work
- Always `push` after finishing work
- Use `--dry-run` when unsure
- Check Google Drive sync status before switching machines

### Error Handling

**Common errors and solutions:**

1. **Planning folder not found:**
   ```
   Error: Planning folder not found: /path/to/repo/planning
   ```
   Solution: Create planning folder or check you're in correct repo

2. **Google Drive not mounted:**
   ```
   Error: Google Drive not found: ~/GoogleDrive
   ```
   Solution: Verify Google Drive path in config, ensure it's mounted

3. **Not in git repository:**
   ```
   Error: Not in a git repository. Planning sync requires git.
   ```
   Solution: Run command from within git repository

4. **rsync not installed:**
   ```
   Error: rsync is not installed or not available in PATH
   ```
   Solution: `sudo apt install rsync` (Ubuntu/Debian)

### Implementation Details

**Handler: `handlers/sync.py`**

**Key Class: `PlanningSyncHandler`**

Methods:
- `__init__(config, dry_run)` - Initialize with config and dry-run mode
- `push()` - Push local planning → Google Drive
- `pull()` - Pull Google Drive → local planning
- `_detect_repo_name()` - Auto-detect repository name from git
- `_get_planning_path()` - Get planning folder path (./planning/)
- `_verify_rsync_available()` - Verify rsync is installed
- `_run_rsync(source, target, description)` - Execute rsync command

**Auto-detection logic:**
```python
# Repo name from git repository directory name
repo_root = subprocess.run(['git', 'rev-parse', '--show-toplevel'])
repo_name = Path(repo_root).name  # e.g., "genai-automations"

# Planning path
planning_path = repo_root / 'planning'

# Google Drive path
gdrive_repo_path = gdrive_base / 'backup' / 'planning' / repo_name
```

**Rsync command:**
```bash
rsync -av --delete \
  --exclude='*.swp' \
  --exclude='*~' \
  --exclude='.DS_Store' \
  source/ target/
```

## Development

### Running Tests

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run all tests
pytest tests/

# Run specific test module
pytest tests/test_config.py -v

# Run with coverage
pytest --cov=ci_platform_manager --cov-report=term-missing

# Run specific test
pytest tests/test_config.py::TestConfig::test_planning_sync_config -v
```

### Linting

All linters installed in `.venv/bin/`:

```bash
# Pylint (code quality)
pylint ci_platform_manager/ --rcfile=pyproject.toml

# Flake8 (style)
flake8 ci_platform_manager/ --max-line-length=120

# Mypy (type checking)
mypy ci_platform_manager/ --config-file=pyproject.toml

# Black (formatting)
black ci_platform_manager/ --check
black ci_platform_manager/  # Apply formatting
```

**Project Standards:**
- pylint score: >= 9.5/10
- flake8: Zero violations
- mypy: Zero type errors
- black: All files formatted

### Adding New Handlers

**Pattern to follow:**

1. Create handler file: `ci_platform_manager/handlers/new_handler.py`

2. Implement handler class:
   ```python
   from ..config import Config
   from ..exceptions import PlatformError

   class NewHandler:
       """Handler for new operation."""

       def __init__(self, config: Config, dry_run: bool = False) -> None:
           self.config = config
           self.dry_run = dry_run

       def execute(self) -> None:
           """Execute the operation."""
           # Implementation
   ```

3. Add to CLI: `ci_platform_manager/cli.py`
   ```python
   from .handlers.new_handler import NewHandler

   def cmd_new(args) -> int:
       config = Config(args.config)
       handler = NewHandler(config, dry_run=args.dry_run)
       handler.execute()
       return 0

   # In main():
   commands = {
       # ...
       'new': cmd_new,
   }
   ```

4. Write tests: `tests/handlers/test_new_handler.py`

## Dependencies

### Runtime Dependencies

- **Python** >= 3.7
- **PyYAML** >= 5.4 - YAML parsing
- **glab** CLI - GitLab operations
- **rsync** - Planning folder sync (system package)
- **Google Drive** client - Planning folder sync

### Development Dependencies

- **pytest** >= 7.0 - Testing framework
- **pytest-cov** >= 4.0 - Coverage reporting
- **pylint** >= 3.0 - Code quality
- **flake8** >= 6.0 - Style checking
- **mypy** >= 1.0 - Type checking
- **black** >= 23.0 - Code formatting
- **types-PyYAML** >= 6.0 - Type stubs

### Installation

```bash
# Runtime only
pip install -e .

# Development
pip install -e ".[dev]"

# From pyproject.toml
pip install ci-platform-manager[dev]
```

## Troubleshooting

### Planning Sync Issues

**Issue: Sync fails with permission error**
```
Solution: Check Google Drive sync status, ensure folder is fully synced
```

**Issue: Wrong repository name detected**
```
Solution: Check git repository name with: git rev-parse --show-toplevel
```

**Issue: Conflict - files modified on both machines**
```
Solution: Last write wins. Pull latest, manually merge if needed, push
```

### General Issues

**Issue: Config file not found**
```
Solution: Create config.yaml in project root or use --config flag
```

**Issue: Command not found**
```
Solution: Install package: pip install -e . or use python3 -m ci_platform_manager
```

**Issue: Import errors**
```
Solution: Ensure in correct directory, reinstall: pip install -e ".[dev]"
```

## Additional Resources

- **Legacy docs**: `glab-management/CLAUDE.md`
- **Config example**: `ci_platform_manager_config.yaml.example`
- **Project root**: `/home/astavonin/projects/genai-automations`
- **Virtual env**: `.venv/` (pre-configured with all dependencies)
