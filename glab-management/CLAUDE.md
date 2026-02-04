# glab-management

GitLab automation tool (`glab_tasks_management.py`) - Python wrapper around `glab` CLI for managing epics, issues, milestones, and merge requests programmatically.

## Recent Updates

**New capabilities added:**
- **MR Loading**: View merge request details in markdown format
- **Review Comments**: Post code review comments from YAML files to MRs
- **MR Creation**: Create merge requests from current branch with reviewers, labels, etc.

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

3. **`TicketLoader`**: Loads issue/epic/milestone/MR information from GitLab
   - Parses references: URLs, issue numbers, `#123`, `&456` (epic), `%789` (milestone), `!134` (MR)
   - Outputs markdown format for issues, epics, milestones, and merge requests
   - Includes dependency relationships (blocking/blocked_by) for issues
   - Milestone view includes epic breakdown (groups issues by their epic)
   - MR view includes branches, reviewers, assignees, pipeline status

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

# Load merge request (markdown output)
python3 glab_tasks_management.py load !134
python3 glab_tasks_management.py load 134 --type mr
python3 glab_tasks_management.py load https://gitlab.example.com/group/project/-/merge_requests/134

# Post review comment from YAML to merge request
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml --mr 134
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml --dry-run

# Create merge request from current branch
python3 glab_tasks_management.py create-mr --title "Add streaming support" --draft
python3 glab_tasks_management.py create-mr --fill --reviewer alice --label "type::feature"
python3 glab_tasks_management.py create-mr --target-branch develop --milestone "v2.0"
python3 glab_tasks_management.py create-mr --dry-run
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

The tool uses both native `glab` commands and `glab api` for operations:

**Native glab commands:**
- **MR operations**: `glab mr view`, `glab mr comment`, `glab mr create`
- **Issue operations**: `glab issue view`, `glab issue list`
- **Epic operations**: Limited support (most use API)

**glab api for advanced operations:**
- **Epic creation**: `POST /groups/:id/epics`
- **Epic-issue linking**: `POST /groups/:id/epics/:epic_iid/issues/:issue_id`
- **Issue dependency links**: `POST /projects/:id/issues/:iid/links` with `link_type=blocks`
- **Milestone queries**: `GET /projects/:id/milestones/:milestone_id` and `/milestones/:milestone_id/issues`
- **Issue/epic/milestone queries**: Various `GET` endpoints

Key details:
- Epic operations require group path (from config or URL)
- Issue linking requires global issue ID (not project-scoped IID)
- URLs are properly encoded using `urllib.parse.quote()`
- MR operations use JSON output from `glab mr view --output json`

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

## Merge Request Operations

### Loading MRs

Load merge request information in markdown format:

```python
# Reference formats supported:
# - !134 (exclamation prefix)
# - 134 --type mr (explicit type)
# - URL: https://gitlab.../merge_requests/134
loader.load_mr('!134')
```

Output includes:
- Title, state, author
- Source and target branches
- Draft status
- Labels, assignees, reviewers
- Milestone
- Created/updated/merged timestamps
- Pipeline status
- Description

### Posting Review Comments

Post code review comments from YAML files to merge requests:

**YAML Format:**
```yaml
mr_number: 134
title: "Draft: DMS refactoring"
review_date: "2026-02-04"

findings:
  - severity: Critical  # or High, Medium, Low
    title: "Brief issue description"
    description: |
      Detailed explanation with technical context.
      Explains WHY it's an issue, not just WHAT.
    location: "path/to/file.cc:123"
    # OR for multiple locations:
    # locations:
    #   - "file1.cc:123"
    #   - "file2.h:456"
    fix: |
      Concrete fix recommendation with code example.
    guideline: "C++ Core Guidelines F.53"  # Optional, use null if none
```

**Required YAML Fields:**
- `mr_number` (integer) - MR number
- `title` (string) - MR title
- `review_date` (string) - YYYY-MM-DD format
- `findings` (list) - List of finding objects

**Each Finding:**
- `severity` - One of: Critical, High, Medium, Low
- `title` - Brief problem statement
- `description` - Technical explanation (multiline with `|`)
- `location` OR `locations` - File path(s) with line numbers
- `fix` - Concrete recommendation (optional)
- `guideline` - Standards reference (optional, use `null` if none)

**Comment Formatting:**
The tool automatically formats findings into markdown:
- Groups by severity (Critical → High → Medium → Low)
- Numbers all findings sequentially
- Includes code blocks for fix suggestions
- Adds location references

**Usage:**
```bash
# Post review (MR number from YAML)
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml

# Override MR number
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml --mr 135

# Preview without posting
python3 glab_tasks_management.py comment planning/reviews/MR134-review.yaml --dry-run
```

### Creating Merge Requests

Create MRs from current branch with full metadata:

**Options:**
- `--title` - MR title
- `--description` - MR description
- `--draft` - Mark as draft
- `--fill` - Auto-fill title/description from commits
- `--assignee` - Assignee username (repeatable)
- `--reviewer` - Reviewer username (repeatable)
- `--label` - Label to add (repeatable)
- `--milestone` - Milestone title
- `--target-branch` - Target branch (default: repo default branch)
- `--web` - Open MR in browser after creation
- `--dry-run` - Preview command without creating

**Examples:**
```bash
# Interactive mode
python3 glab_tasks_management.py create-mr

# With metadata
python3 glab_tasks_management.py create-mr \
  --title "Fix memory leak in encoder" \
  --description "Addresses issue #123" \
  --reviewer alice --reviewer bob \
  --label "type::bug" --label "priority::high" \
  --milestone "v2.0"

# Draft MR with auto-fill
python3 glab_tasks_management.py create-mr --draft --fill
```

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

## File Organization

### Review Files

Review YAML files should be stored in `planning/reviews/` directory:

```
project-root/
├── planning/
│   ├── reviews/
│   │   ├── MR134-review.yaml
│   │   ├── MR135-review.yaml
│   │   └── ...
│   ├── epic1.yaml
│   └── epic2.yaml
└── glab_config.yaml
```

**Naming convention:** `MR<number>-review.yaml`

### Project Integration

When using this tool from a project (e.g., openpilot):

1. **Config location**: `./glab_config.yaml` in project root
2. **Epic definitions**: `planning/*.yaml`
3. **Review files**: `planning/reviews/MR*-review.yaml`
4. **Documentation**: `planning/glab-management.md` (project-specific guide)

## Code Structure

### Main Functions (~2400 lines total)

- **`cmd_create()`**: Handle issue/epic creation from YAML
- **`cmd_load()`**: Handle loading of issues/epics/milestones/MRs
- **`cmd_search()`**: Handle search operations
- **`cmd_comment()`**: Handle posting review comments to MRs (NEW)
- **`cmd_create_mr()`**: Handle MR creation from current branch (NEW)

### Helper Functions

- **`format_review_comment()`**: Convert YAML review to markdown comment (NEW)
- Groups findings by severity
- Formats code blocks and locations
- Numbers findings sequentially

### Class Methods

**TicketLoader additions:**
- `load_mr()`: Load MR via `glab mr view --output json`
- `print_mr_info()`: Format MR info as markdown

## Code Style

- Python code follows PEP 8
- Type hints used throughout (Python 3.7+)
- Comprehensive docstrings for classes and methods
- Logging via Python `logging` module
- Single-file design for easy deployment (~2400 lines)
