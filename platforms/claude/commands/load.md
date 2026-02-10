---
name: load
description: Load ticket information via ci-platform-manager
---

# Load Ticket Command

Load issue, epic, or milestone information from ticket management systems.

## Supported Systems

### Multi-Platform Support (via ci-platform-manager)

Load issues, epics, milestones, and merge requests with full details and dependencies.

**Tool:** `ci-platform-manager` (supports GitLab and GitHub)

## Usage Patterns

### Load Issue
```bash
# By issue number
ci-platform-manager load 113

# By URL
ci-platform-manager load https://gitlab.com/group/project/-/issues/113

# With # prefix
ci-platform-manager load #113
```

### Load Epic
```bash
# By epic number with & prefix
ci-platform-manager load &21

# By number with --type flag
ci-platform-manager load 21 --type epic

# By URL
ci-platform-manager load https://gitlab.com/groups/group/-/epics/21
```

### Load Milestone
```bash
# By milestone number with % prefix
ci-platform-manager load %123

# By number with --type flag
ci-platform-manager load 123 --type milestone

# By URL
ci-platform-manager load https://gitlab.com/group/project/-/milestones/123
```

### Load Merge Request
```bash
# By MR number with ! prefix
ci-platform-manager load !134

# By number with --type flag
ci-platform-manager load 134 --type mr

# By URL
ci-platform-manager load https://gitlab.com/group/project/-/merge_requests/134
```

## Actions

1. **Parse ticket reference:**
   - Detect ticket type from prefix (#, &, %) or URL
   - Extract ticket number

2. **Load ticket data:**
   - Use ci-platform-manager (supports GitLab and GitHub)
   - Fetch full ticket information including:
     - Title and description
     - Status and labels
     - Dependencies (blocking/blocked by)
     - For epics: all associated issues
     - For milestones: epic breakdown with issues

3. **Display information:**
   - Show markdown-formatted output
   - Include all relevant details
   - Highlight dependencies and relationships

## Output Format

### Issue Output
```markdown
# Issue #123: Title

**Status:** opened
**Labels:** type::feature, priority::high
**Assignee:** @username
**Milestone:** %456

## Description
[Issue description]

## Dependencies
**Blocks:** #124, #125
**Blocked by:** #100
```

### Epic Output
```markdown
# Epic &21: Epic Title

**Status:** opened
**Labels:** epic::active

## Description
[Epic description]

## Issues (3)
- #45 Issue title `[opened]`
- #67 Another issue `[closed]`
- #89 Third issue `[opened]`
```

### Milestone Output
```markdown
# Milestone %123: Release v1.0

**Progress:** 5/10 issues closed (50%)
**Due date:** 2026-03-01

## Epic Breakdown

### Epic &21: Authentication
- #45 Login feature `[opened]`
- #67 Password reset `[closed]`

### Epic &22: Settings
- #89 User preferences `[opened]`

### No Epic
- #12 Standalone fix `[closed]`
```

## Configuration

The ci-platform-manager tool uses `config.yaml` or `glab_config.yaml` (legacy):

```yaml
# Platform selection
platform: gitlab  # or github

# GitLab-specific settings
gitlab:
  default_group: "your/group/path"  # Required for epic operations
  labels:
    default: ["type::feature", "development-status::backlog"]

# GitHub-specific settings (future)
github:
  default_org: "organization"
```

**Config file resolution (first found wins):**
1. `--config` flag (explicit path)
2. `./glab_config.yaml` (project-local, legacy)
3. `./config.yaml` (project-local, new)
4. `~/.config/ci_platform_manager/config.yaml` (user-wide)
5. `~/.config/glab_config.yaml` (legacy)

## Error Handling

- If ticket not found: show clear error message
- If tool not available: suggest installation
- If config missing: show configuration requirements

## Platform Support

**Supported Platforms:**
- **GitLab:** Full support via ci-platform-manager
- **GitHub:** Full support via ci-platform-manager (future)

**Alternative Tools:**
- **GitHub:** Use `gh issue view <number>` or `gh pr view <number>` (native CLI)
- **Jira:** (Add Jira support as needed)

## Examples

```bash
# Load GitLab issue with dependencies
/load #145

# Load epic with all issues
/load &25

# Load milestone with progress
/load %10

# Load from URL
/load https://gitlab.com/mygroup/project/-/issues/200
```
