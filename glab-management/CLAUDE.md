# glab-management

GitLab automation tool (`glab_tasks_management.py`) - Python wrapper around `glab` CLI for managing epics, issues, and milestones programmatically.

## Core Architecture

### Main Components

- **`glab_tasks_management.py`**: Single-file Python CLI tool (~2060 lines) that wraps `glab` CLI
- **Config Management**: YAML-based configuration (`glab_config.yaml`) for defaults and validation rules
- **YAML Templates**: Issue/epic definitions with dependency tracking (`epic_template.yaml`)

### Key Classes

1. **`Config`**: Loads configuration from `glab_config.yaml` (or path specified via `--config`)
   - Provides default group path, labels, and validation rules
   - Config resolution: `--config` flag > `./glab_config.yaml` in CWD (no fallback to example file)

2. **`EpicIssueCreator`**: Creates epics and issues via `glab` CLI
   - Supports dry-run mode for previewing commands
   - Handles dependency linking between issues using GitLab API
   - Validates labels against `allowed_labels` from config
   - Validates issue descriptions contain required sections

3. **`TicketLoader`**: Loads issue/epic/milestone information from GitLab
   - Parses references: URLs, issue numbers, `#123`, `&456` (epic), `%789` (milestone)
   - Outputs markdown format for issues, epics, and milestones
   - Includes dependency relationships (blocking/blocked_by)
   - Milestone view includes epic breakdown (groups issues by their epic)

4. **`SearchHandler`**: Searches issues, epics, and milestones by text query
   - Uses GitLab API via `glab api` command
   - Outputs plain text format
   - Milestone search supports state filters: active, closed, all

## Common Commands

### Development

```bash
# Navigate to the tool directory
cd glab-management

# Run the tool (requires glab CLI installed)
python3 glab_tasks_management.py --help

# Create issues from YAML definition
python3 glab_tasks_management.py create epic_definition.yaml

# Dry run to preview commands without executing
python3 glab_tasks_management.py create --dry-run epic_definition.yaml

# Use custom config file
python3 glab_tasks_management.py --config /path/to/config.yaml create epic_definition.yaml

# Load issue with dependencies (markdown output)
python3 glab_tasks_management.py load 113
python3 glab_tasks_management.py load https://gitlab.example.com/group/project/-/issues/113

# Load epic with all issues (markdown output)
python3 glab_tasks_management.py load &21
python3 glab_tasks_management.py load 21 --type epic

# Load milestone with epic breakdown (markdown output)
python3 glab_tasks_management.py load %123
python3 glab_tasks_management.py load 123 --type milestone

# Search for issues, epics, or milestones (text output)
python3 glab_tasks_management.py search issues "streaming"
python3 glab_tasks_management.py search issues "bug" --state opened --limit 10
python3 glab_tasks_management.py search epics "video"
python3 glab_tasks_management.py search milestones "v1.0"
python3 glab_tasks_management.py search milestones "release" --state active
```

### Testing

```bash
# Run verification tests for CLI argument validation
cd glab-management
./test_verification.sh
```

## Configuration

### Config File Resolution

The tool requires `glab_config.yaml` configuration:

1. If `--config` is specified: use that path (fail if not found)
2. Otherwise: use `./glab_config.yaml` in current working directory (fail if not found)
3. `glab_config.example.yaml` serves as documentation/template only, NOT a runtime fallback

### Config Structure

```yaml
gitlab:
  default_group: "your/group/path"  # Required for epic operations

labels:
  default:
    - "type::feature"
    - "development-status::backlog"

  allowed_labels:  # Optional validation list
    - "type::feature"
    - "type::bug"
    # ... (exhaustive list)

issue_template:
  sections:
    - name: "Description"
      required: true
    - name: "Acceptance Criteria"
      required: true
```

## YAML Issue/Epic Definitions

### Structure

- **Epic**: Either create new (title + description) or reference existing (id)
- **Issues**: List of issues with optional dependency tracking via local IDs

### Key Fields

- `id`: Local identifier for dependency tracking (not GitLab ID)
- `title`: Issue title (required)
- `description`: Issue body with required sections (validated against config)
- `labels`: Merged with default labels from config (validated against allowed_labels)
- `dependencies`: List of local IDs this issue depends on
- `assignee`, `milestone`, `due_date`: Optional metadata

### Dependency Linking

Issues can declare dependencies using local `id` fields:

```yaml
issues:
  - id: research-task
    title: "[Research] Investigate performance"
    # ...

  - id: impl-task
    title: "[Impl] Optimize encoder"
    dependencies:
      - research-task  # This issue blocked by research-task
```

The tool creates GitLab issue links with `link_type=blocks` after all issues are created.

## GitLab API Usage

The tool uses `glab api` command for operations not supported by native `glab` commands:

- **Epic creation**: `POST /groups/:id/epics`
- **Epic-issue linking**: `POST /groups/:id/epics/:epic_iid/issues/:issue_id`
- **Issue dependency links**: `POST /projects/:id/issues/:iid/links` with `link_type=blocks`
- **Milestone queries**: `GET /projects/:id/milestones/:milestone_id` and `/milestones/:milestone_id/issues`
- **Issue/epic/milestone queries**: Various `GET` endpoints

Key details:
- Epic operations require group path (from config or URL)
- Issue linking requires global issue ID (not project-scoped IID)
- URLs are properly encoded using `urllib.parse.quote()`

## Milestone Epic Breakdown

When loading a milestone, the tool provides a view of how issues are organized by epics:

```markdown
# Milestone %123: Title
**Progress:** X/Y issues closed

## Epic Breakdown

### Epic &21: Epic Title
- #45 Issue title `[opened]`
- #67 Another issue `[closed]`

### Epic &22: Another Epic
- #89 Issue title `[opened]`

### No Epic
- #12 Standalone issue `[opened]`
```

This view is useful for:
- Understanding milestone→epic mapping
- Tracking epic progress within a milestone
- Identifying standalone issues not associated with epics

## Validation Rules

### Label Validation

If `labels.allowed_labels` is configured:
- All labels (default + issue-specific) must be in allowed list
- Empty allowed list means no labels permitted
- Validation failure prevents issue creation

### Description Validation

If `issue_template.sections` defines required sections:
- Issue descriptions must contain headers matching required section names
- Looks for `# Section` or `## Section` patterns
- Validation failure prevents issue creation

## Dependencies

- **Python 3**: Standard library + PyYAML
- **glab CLI**: Must be installed and authenticated
- **GitLab instance**: With API access

## Error Handling

- `GlabError`: Raised for `glab` command failures (includes stderr output)
- `ValueError`: Raised for invalid YAML structure or missing required fields
- `FileNotFoundError`: Raised when config file not found (includes helpful error message)

## Task Organization Guidelines

From `epic_template.yaml`, the project follows these conventions:

- **[Research]**: Investigation tasks (must include "Architecture & Research" label)
- **[Design]**: Design documents (must include "Design document created" in acceptance criteria)
- **[Impl]**: Implementation tasks (must include "Unit tests added and passing" in acceptance criteria)
- **[Test]**: Integration/system tests only (unit tests are part of [Impl])

## Code Style

- Python code follows PEP 8
- Type hints used throughout (Python 3.7+)
- Comprehensive docstrings for classes and methods
- Logging via Python `logging` module
