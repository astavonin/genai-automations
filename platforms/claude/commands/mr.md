---
name: mr
description: Create merge request for current branch
---

# Merge Request Command

Create a GitLab merge request for the current branch.

## Prerequisites

- Current branch has commits
- Branch is pushed to remote (or will be pushed)
- `glab` CLI installed and authenticated

## Actions

1. **Check git status:**
   ```bash
   git status
   git log origin/main..HEAD  # View commits that will be in MR
   ```

2. **Analyze changes:**
   - Review all commits that will be included
   - Check if branch needs to be pushed to remote

3. **Draft MR title and description:**
   - **Title:** Short summary (under 70 characters)
   - **Description:** Use project MR template structure (keep it SHORT and HIGH-LEVEL):
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

   **Keep descriptions concise and architectural:**
   - Summary: 1-2 sentences maximum
   - Implementation Details: 2-4 bullet points, high-level only
   - How It Was Tested: 2-3 bullet points maximum

4. **Create MR:**
   ```bash
   # Push branch if needed
   git push -u origin <branch-name>

   # Create MR using project template
   glab mr create --title "MR title" --description "$(cat <<'EOF'
   # Summary

   [What this MR implements and why]

   ---

   # Implementation Details

   - [Key file changes]
   - [Design decisions]
   - [Trade-offs]

   ---

   # How It Was Tested

   - [Unit tests added]
   - [Manual validation]
   - [CI status]
   EOF
   )"
   ```

## Options

- `--draft` - Create as draft MR
- `--assignee <username>` - Assign to user
- `--target-branch <branch>` - Target branch (default: main)
- `--remove-source-branch` - Delete source branch after merge
- `--squash` - Squash commits on merge

## Example Usage

```bash
# Example: Short, high-level MR description
glab mr create --title "Add adaptive camera exposure" --description "$(cat <<'EOF'
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
EOF
)"

# Draft MR
glab mr create --draft --title "WIP: Add caching layer" --description "..."

# With options
glab mr create \
  --title "Add user settings" \
  --description "..." \
  --assignee @me \
  --remove-source-branch \
  --squash
```

## Output

Return the MR URL so the user can view it.

## MR Template

The MR description must follow the project template structure:
- **Summary:** What and why (1-2 sentences, architecture level)
- **Implementation Details:** How (2-4 bullet points, high-level changes only)
- **How It Was Tested:** Validation approach (2-3 bullet points)


## Critical Rules

- **Keep descriptions SHORT and HIGH-LEVEL (architecture level)**
- Analyze ALL commits that will be included (not just the latest)
- Follow project MR template structure exactly
- Summary: 1-2 sentences maximum, focus on WHAT and WHY at architecture level
- Implementation Details: 2-4 bullet points, high-level changes only (no file-level details)
- How It Was Tested: 2-3 bullet points, concise test approach
- Use HEREDOC for multi-line descriptions to ensure proper formatting
- Avoid verbose descriptions - reviewers can see the code
