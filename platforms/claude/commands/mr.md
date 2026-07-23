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

**Pre-flight: fetch label allowlist**

Before writing `planning/mr-draft.yaml`, run the shared fragment:

```
Read ~/.claude/skills/workflows/label-allowlist/SKILL.md
```

Follow every step in that fragment. The snapshot lands at `planning/.label-allowlist.txt` and is the sole source of truth for the `labels:` field below. On empty allowlist, tool failure, or pre-feature projctl, follow the branches defined in the fragment — do not proceed silently.

Create `planning/mr-draft.yaml` with the following structure:

```yaml
title: "Add adaptive camera exposure. Ref #42"
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
labels:  # Optional — every entry MUST come from planning/.label-allowlist.txt (see pre-flight)
  - "<label-from-projctl-labels>"
  - "<label-from-projctl-labels>"
milestone: "v2.0"  # Optional
target_branch: "main"  # Optional (default: repo default)
```

**YAML Fields:**
- `title` (required) - MR title in format `<short description>. Ref #<issue-number>`, under 70 characters. Always include the issue reference.
- `description` (required) - MR description following template structure
- `draft` (optional) - Boolean, mark as draft MR
- `reviewers` (optional) - List of reviewer usernames
- `labels` (optional) - List of labels. Every entry MUST match byte-for-byte (case, spaces, punctuation) a label name in `planning/.label-allowlist.txt` written by the pre-flight step. Fabricated, extrapolated, or copy-from-stale-draft labels are prohibited. If no listed label fits, omit the `labels:` key entirely — do not write `labels: []`.
- `milestone` (optional) - Milestone title
- `target_branch` (optional) - Target branch name

### 4. Show YAML for User Verification

Execute these sub-steps in strict order. The fragment re-invocation MUST run before any `cat` of the YAML — otherwise the confirmation-time snapshot check cannot gate the display, and the compaction-safety property of the invoke-twice pattern is lost.

**Sub-step 4a — Re-invoke the shared fragment (only Step 5 fires on this invocation):**

```
Read ~/.claude/skills/workflows/label-allowlist/SKILL.md
```

The fragment's Step 5 verifies `planning/.label-allowlist.txt` is present and re-runs Steps 1–2 if it is missing or stale. Do not proceed to sub-step 4b until Step 5 completes.

**Sub-step 4b — Show the allowlist snapshot:**

```bash
cat planning/.label-allowlist.txt
```

**Sub-step 4c — Show the generated YAML:**

```bash
cat planning/mr-draft.yaml
```

**Sub-step 4d — State any label omissions explicitly.** If `labels:` was omitted because no listed label fits, or because the fragment's empty-allowlist / pre-feature-projctl branches fired, name the omission in the summary rather than hiding the empty field.

**Sub-step 4e — Ask about opening:** ask the user if they want to `open planning/mr-draft.yaml`, then wait for confirmation before proceeding.

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

### 6. Update Planning State (mandatory)

Extract the MR number from the URL (e.g. `!188` from `.../merge_requests/188`).

**Update `planning/progress.md`:**
- In the **Active** section, find the entry for the linked issue(s).
- Add or replace the MR reference line: `- MR !<N> open — pipeline pending, <N> reviewers assigned, awaiting review`
- Update `**Last Updated:**` to today's date.

**Update `planning/<goal>/milestone-XX/status.md`:**
- In the issue table, set the MR column to `!<N>` for each linked issue row.
- Update the Phase column to `in review 👀`.

Then push planning to backup:
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment. Surface the §8.2 warning block on failure; do not fail the skill.

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
- **How It Was Tested:** 1-2 bullets max — which test commands were run and whether they passed. Never include assertion counts, test case counts, or file-level test details.
- Use `|` for multi-line YAML strings
- Keep descriptions SHORT and HIGH-LEVEL
- Avoid file-level details - reviewers can see the code

## Critical Rules

1. **Title format** - Must be `<short description>. Ref #<issue-number>` — never omit the issue reference
2. **Check acceptance criteria first** - Load the linked issue and verify scope/AC coverage before writing YAML
3. **Block on gaps** - If any scope/AC items are unimplemented, explicitly present them and ask the user how to proceed; do NOT silently skip them
4. **Generate YAML first** - Always create `planning/mr-draft.yaml` before creating MR
5. **User verification required** - Show YAML and wait for explicit confirmation
6. **Analyze all commits** - Review complete commit range, not just latest commit
7. **Follow template structure** - MR description must have Summary, Implementation Details, and How It Was Tested sections
8. **Keep it concise** - Architecture-level descriptions, not implementation details
9. **Push before creating** - Ensure branch is pushed to remote before MR creation
10. **Label allowlist** - Run the `label-allowlist` shared fragment at the start of Step 3 before writing any `labels:` field, and re-invoke it at Step 4 before displaying the YAML. Every entry must match byte-for-byte (case, spaces, punctuation) a label name in `planning/.label-allowlist.txt` (see `~/.claude/skills/workflows/label-allowlist/SKILL.md`). If no listed label fits, omit the `labels:` key entirely — do not write `labels: []`. Never fabricate, extrapolate from prior MRs, or copy from a stale draft. Whether `projctl create-mr` rejects unknown labels at submit or not, this pre-flight is the primary gate — do not rely on the tool as a backstop. Note: this pre-flight verifies only what the workflow writes into `labels:`; if `projctl create-mr` applies `labels.default` from projctl config, those entries are NOT verified here (see the fragment's Residual failure paths).

## Example

The `labels:` values below are illustrative placeholders. Replace them with entries from `planning/.label-allowlist.txt` (written by the Step 3 pre-flight) for your project — do not copy them verbatim.

```yaml
title: "Add Pipeline refactoring with worker pool architecture. Ref #117"
description: |
  # Summary

  Refactors the Pipeline module into a worker pool with bounded queues and thread pool.

  ---

  # Implementation Details

  - Introduced PipelineCoordinator with configurable thread pool
  - Added FrameContext with latch-based synchronization
  - Replaced direct worker calls with async task queue

  ---

  # How It Was Tested

  - Unit tests for ThreadPool, ResultQueue, FrameContext
  - Integration test with mock workers
  - CI pipeline passed

draft: true
reviewers:
  - john
  - sarah
labels:  # illustrative placeholders — see disclaimer above this example
  - "<label-from-projctl-labels>"
  - "<label-from-projctl-labels>"
milestone: "v2.0"
```
