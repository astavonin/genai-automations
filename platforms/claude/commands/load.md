---
name: load
description: Load ticket information via projctl
---

# Load Ticket Command

Load issue, epic, or milestone information from ticket management systems.

## Supported Systems

### Multi-Platform Support (via projctl)

Load issues, epics, milestones, and merge requests with full details and dependencies.

**Tool:** `projctl` (supports GitLab and GitHub)

## Usage Patterns

### Load Issue
```bash
projctl load issue 113
projctl load issue "#113"   # prefixed form also accepted
projctl load issue https://gitlab.com/group/project/-/issues/113
```

### Load Epic
```bash
projctl load epic 21
projctl load epic "&21"     # prefixed form also accepted
projctl load epic https://gitlab.com/groups/group/-/epics/21
```

### Load Milestone
```bash
projctl load milestone 123
projctl load milestone "%123"  # prefixed form also accepted
projctl load milestone https://gitlab.com/group/project/-/milestones/123
```

### Load Merge Request
```bash
projctl load mr 134
projctl load mr "!134"      # prefixed form also accepted
projctl load mr https://gitlab.com/group/project/-/merge_requests/134
```

## Actions

1. **Parse ticket reference:**
   - Detect ticket type from subcommand (`issue`, `epic`, `mr`, `milestone`) or URL
   - Extract ticket number

2. **Load ticket data:**
   - Use projctl (supports GitLab and GitHub)
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

The projctl tool uses `config.yaml` or `glab_config.yaml` (legacy):

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
4. `~/.config/projctl/config.yaml` (user-wide)
5. `~/.config/glab_config.yaml` (legacy)

## Error Handling

- If ticket not found: show clear error message
- If tool not available: suggest installation
- If config missing: show configuration requirements

## Platform Support

**Supported Platforms:**
- **GitLab:** Full support via projctl
- **GitHub:** Full support via projctl

## Examples

```bash
# Load issue with dependencies
/load issue 145

# Load epic with all issues
/load epic 25

# Load milestone with progress
/load milestone 10

# Load from URL
/load issue https://gitlab.com/mygroup/project/-/issues/200
```
