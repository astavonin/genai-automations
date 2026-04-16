---
name: mr
description: Create merge request for current branch via projctl
---

# Merge Request Command

Create a merge request from the current branch using projctl (supports GitLab and GitHub).

## Prerequisites

- Current branch has commits
- Branch is pushed to remote (or will be pushed)
- `projctl` installed and configured
- `projctl` configured and platform authenticated (run: `projctl --help` to verify)

## Workflow

### 1. Analyze Current Branch

```bash
git status
# Detect default branch (main or master), then show commits and diff
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
git log origin/${DEFAULT}..HEAD --oneline
git diff origin/${DEFAULT}...HEAD --stat
```

### 2. Verify Issue Acceptance Criteria

If the branch is linked to an issue (look for `Ref #NNN` in commit messages or the branch name):

```bash
projctl load issue <issue_number>
```

Read the issue's **Scope** and **Acceptance Criteria** sections. For each item, check the changed files to determine whether it is implemented.

Produce a checklist:

```
Scope / Acceptance Criteria check:
  ✅ <item> — implemented in <file>
  ❌ <item> — NOT implemented (missing)
  ⚠️  <item> — partially implemented
```

**Then explicitly ask the user:**

> The following items from the issue are not yet implemented:
> - <item 1>
> - <item 2>
>
> How would you like to proceed?
> 1. Implement the missing items before creating the MR
> 2. Create the MR as-is and track missing items in follow-up issues
> 3. Remove the missing items from the issue scope

**Do NOT proceed to YAML generation until the user answers.**

If no linked issue is found, skip this step.

### 3. Generate MR YAML

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

### 4. Show YAML for User Verification

Display the generated YAML to the user:
```bash
cat planning/mr-draft.yaml
```

Ask the user if they want to `open planning/mr-draft.yaml`, then wait for confirmation before proceeding.

### 5. Create MR via projctl

After user confirms YAML, create the MR:

```bash
# Push branch if needed
git push -u origin $(git branch --show-current)
```

Read `planning/mr-draft.yaml` and build the `projctl create-mr` command by parsing the YAML fields directly. Pass each present field as the corresponding flag:

```bash
projctl create-mr \
  --title "<title from YAML>" \
  --description "<description from YAML>" \
  --draft \                          # only if draft: true
  --reviewer alice --reviewer bob \  # one --reviewer per entry
  --label "type::feature" \          # one --label per entry
  --milestone "v2.0" \               # only if present
  --target-branch main               # only if present
```

**Quick option (use git history to auto-generate title and description):**
```bash
projctl create-mr --fill --draft
```

Return the MR URL to the user and ask if they want to `open <url>` in the browser.

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

1. **Check acceptance criteria first** - Load the linked issue and verify scope/AC coverage before writing YAML
2. **Block on gaps** - If any scope/AC items are unimplemented, explicitly present them and ask the user how to proceed; do NOT silently skip them
3. **Generate YAML first** - Always create `planning/mr-draft.yaml` before creating MR
4. **User verification required** - Show YAML and wait for explicit confirmation
5. **Analyze all commits** - Review complete commit range, not just latest commit
6. **Follow template structure** - MR description must have Summary, Implementation Details, and How It Was Tested sections
7. **Keep it concise** - Architecture-level descriptions, not implementation details
8. **Push before creating** - Ensure branch is pushed to remote before MR creation

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
