---
name: mr
description: Create merge request for current branch via ci-platform-manager
---

# Merge Request Command

Create a merge request from the current branch using ci-platform-manager (supports GitLab and GitHub).

## Prerequisites

- Current branch has commits
- Branch is pushed to remote (or will be pushed)
- `ci-platform-manager` installed and configured
- Platform CLI authenticated (`glab` for GitLab, `gh` for GitHub)

## Workflow

### 1. Analyze Current Branch

```bash
git status
git log origin/main..HEAD  # View commits that will be in MR
git diff origin/main...HEAD --stat  # Review changed files
```

### 2. Generate MR YAML

Create `planning/mr-draft.yaml` with the following structure:

```yaml
title: "Add adaptive camera exposure"
description: |
  # Summary

  Adds adaptive exposure control to improve image stability in variable lighting.

  ---

  # Implementation Details

  - Introduced exposure adjustment module
  - Replaced fixed gain with adaptive averaging
  - Updated related unit tests

  ---

  # How It Was Tested

  - Unit tests for low/high light scenarios
  - CI pipeline passed

draft: true  # Optional: mark as draft
reviewers:  # Optional
  - alice
  - bob
labels:  # Optional
  - "type::feature"
  - "priority::medium"
milestone: "v2.0"  # Optional
target_branch: "main"  # Optional (default: repo default)
```

**YAML Fields:**
- `title` (required) - MR title, under 70 characters
- `description` (required) - MR description following template structure
- `draft` (optional) - Boolean, mark as draft MR
- `reviewers` (optional) - List of reviewer usernames
- `labels` (optional) - List of labels
- `milestone` (optional) - Milestone title
- `target_branch` (optional) - Target branch name

### 3. Show YAML for User Verification

Display the generated YAML to the user:
```bash
cat planning/mr-draft.yaml
```

Wait for user confirmation before proceeding.

### 4. Create MR via ci-platform-manager

After user confirms YAML, create the MR:

```bash
# Push branch if needed
git push -u origin $(git branch --show-current)

# Create MR using ci-platform-manager
ci-platform-manager create-mr \
  --title "$(yq '.title' planning/mr-draft.yaml)" \
  --description "$(yq '.description' planning/mr-draft.yaml)" \
  $(yq -r '.draft // false | if . then "--draft" else "" end' planning/mr-draft.yaml) \
  $(yq -r '.reviewers[]? | "--reviewer " + .' planning/mr-draft.yaml) \
  $(yq -r '.labels[]? | "--label " + .' planning/mr-draft.yaml) \
  $(yq -r '.milestone // "" | if . != "" then "--milestone " + . else "" end' planning/mr-draft.yaml) \
  $(yq -r '.target_branch // "" | if . != "" then "--target-branch " + . else "" end' planning/mr-draft.yaml)
```

**Alternative (if yq not available):**
Parse YAML manually and build command:
```bash
ci-platform-manager create-mr \
  --title "MR title from YAML" \
  --description "MR description from YAML" \
  --draft \
  --reviewer alice --reviewer bob \
  --label "type::feature" --label "priority::medium" \
  --milestone "v2.0" \
  --target-branch main
```

**Quick option (use git history to auto-generate):**
```bash
ci-platform-manager create-mr --fill --draft
```

Return the MR URL to the user.

## MR Description Template

**Structure (mandatory):**

```markdown
# Summary

[1-2 sentences: What this implements and why - architecture level]

---

# Implementation Details

- [High-level change 1]
- [High-level change 2]
- [Key architectural decision]

---

# How It Was Tested

- [Test approach]
- [CI status]
```

**Guidelines:**
- **Summary:** 1-2 sentences maximum, architecture level (WHAT and WHY)
- **Implementation Details:** 2-4 bullet points, high-level changes only
- **How It Was Tested:** 2-3 bullet points, concise test approach
- Use `|` for multi-line YAML strings
- Keep descriptions SHORT and HIGH-LEVEL
- Avoid file-level details - reviewers can see the code

## Critical Rules

1. **Generate YAML first** - Always create `planning/mr-draft.yaml` before creating MR
2. **User verification required** - Show YAML and wait for explicit confirmation
3. **Analyze all commits** - Review complete commit range, not just latest commit
4. **Follow template structure** - MR description must have Summary, Implementation Details, and How It Was Tested sections
5. **Keep it concise** - Architecture-level descriptions, not implementation details
6. **Push before creating** - Ensure branch is pushed to remote before MR creation

## Example

```yaml
title: "Add DMS refactoring with pipeline architecture"
description: |
  # Summary

  Refactors DMS module into a pipeline with thread pool and bounded queues.

  ---

  # Implementation Details

  - Introduced DMSPipeline with configurable thread pool
  - Added FrameContext with latch-based synchronization
  - Replaced direct detector calls with async task queue

  ---

  # How It Was Tested

  - Unit tests for ThreadPool, ResultQueue, FrameContext
  - Integration test with mock detectors
  - CI pipeline passed

draft: true
reviewers:
  - john
  - sarah
labels:
  - "type::refactor"
  - "component::dms"
milestone: "v2.0"
```
