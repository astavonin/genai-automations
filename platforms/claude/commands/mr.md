---
name: mr
description: Create merge request for current branch via projctl
---

# Merge Request Command

Create a merge request from the current branch using projctl (supports GitLab and GitHub).

## Prerequisites

- Work exists — committed on a feature or the default branch, or still in the working tree for Step 0 to land
- A remote named `origin` with a resolvable default branch (`origin/<default>`) — Step 0 hard-exits otherwise
- `projctl` installed and configured
- `projctl` configured and platform authenticated (run: `projctl --help` to verify)

## Workflow

### 0. Establish a branch with commits

**Step 1 needs two things: a branch that is not the default one, and at least one commit on it that the default branch does not have.** Where either is missing, this step establishes it rather than stopping — the common case is work finished in the editor and never committed, and "there is nothing to push" is a state the command can fix, not a reason to send the user away.

```bash
# Do not pipe the first command — a pipeline's exit status is sed's, which is 0 even where
# symbolic-ref printed nothing, so the fallback would never fire and DEFAULT would be empty.
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
  || DEFAULT=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
DEFAULT=${DEFAULT#origin/}
# `git remote show origin` prints the literal "(unknown)" where the remote HEAD is unset, which is
# non-empty and would reach git as origin/(unknown) — verify the ref rather than only the string.
git rev-parse --verify --quiet "origin/${DEFAULT:?could not resolve the default branch}" >/dev/null \
  || {
    if git remote show origin 2>/dev/null | grep -q 'HEAD branch: (unknown)'; then
      echo "origin's HEAD is unset — run: git remote set-head origin <default-branch-name>" >&2
    else
      echo "origin/$DEFAULT does not resolve — run: git fetch origin" >&2
    fi
    exit 1
  }
BRANCH=$(git branch --show-current)
echo "branch: ${BRANCH:-<detached HEAD>}   default: $DEFAULT"
git status --porcelain
git rev-parse --verify --quiet HEAD >/dev/null \
  && git log --oneline "origin/$DEFAULT..HEAD" \
  || echo "(no commits yet)"
```

Read all three outputs before acting. Both conditions below can hold at once, and 0a runs first so 0b's commit lands on the new branch.

**Detached HEAD.** Where `$BRANCH` is empty, neither 0a nor 0b's branch-equality check can fire — there is no branch to compare against `$DEFAULT`. Offer `git switch -c <name>` under 0a's propose-and-wait rule to give the work a branch, or stop.

**Resolve the linked issue before proposing anything.** Both 0a's branch name and the commit message rule below choose their form based on whether an issue is linked, and on this path neither a commit nor a branch name exists yet to parse one from. Run `~/.claude/skills/workflows/issue-folder-resolve/SKILL.md` Procedure step 1 to resolve it: if it does not settle the question, ask the user rather than guessing. Where the user confirms the work is genuinely unlinked, say so explicitly in the run output before proceeding — do not let Step 2 discover the absence on its own.

**0a. On the default branch.** Where `$BRANCH` equals `$DEFAULT`, no MR can be opened — a merge request needs a source branch distinct from its target. Propose a name and **wait**: `<type>/<issue>-<slug>` where an issue is linked (`bug/498-version-string-comparison`), otherwise `<type>/<slug>` from the work itself. On approval:

```bash
git switch -c '<proposed-branch-name>'
```

`git switch -c` carries the working tree across unchanged, so nothing is committed, stashed, or lost by this step.

**0b. No commit the default branch does not already have.** Where `git log origin/$DEFAULT..HEAD` printed nothing, there is nothing to push and nothing to diff an MR against.

- **Working tree also clean** — this is the one case Step 0 cannot fix. Stop and say so plainly: the branch holds no work, committed or otherwise.
- **Working tree dirty** — the work exists and is uncommitted. Land it under the rules below.

**0c. Commits exist but the tree is still dirty.** Surface every uncommitted path and ask whether it belongs in this MR before continuing. An MR opened over a dirty tree is an MR missing part of its own change, and the omission is invisible in the diff the reviewer reads.

**Landing uncommitted work — two rules, neither negotiable:**

1. **Never `git add -A`.** List what `git status --porcelain` reported, tracked modifications and untracked files separately, and ask which belong to this MR. An untracked file is as often a scratch script, a local config, or a downloaded artifact as it is a deliverable, and a stray one committed here is published by Step 5's push. Stage the named paths explicitly.
2. **Propose the commit message and wait for explicit approval**, per `CLAUDE.md` → Commit Message Format: one line, `<short description>` or `<short description>. Ref #<number>` with the reference last. The standing rule that the user approves every commit message is not suspended because the commit was this command's idea rather than theirs.

Then commit the staged paths, and re-run this step's three commands before Step 1 — the analysis below reads the state Step 0 just changed.

### 1. Analyze Current Branch

```bash
git status
# Detect default branch (main or master), then show commits and diff
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
  || DEFAULT=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
DEFAULT=${DEFAULT#origin/}
git log "origin/${DEFAULT}..HEAD" --oneline
git diff "origin/${DEFAULT}...HEAD" --stat
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
10. **Step 0 may create a branch and a commit; it may never do either silently** - a branch name is proposed and approved before `git switch -c`, and a commit message is proposed and approved before `git commit`, exactly as if the user had asked for the commit themselves. Stage only paths the user named — `git add -A` here publishes whatever else is lying in the tree, since Step 5 pushes what Step 0 committed
11. **Label allowlist** - Run the `label-allowlist` shared fragment at the start of Step 3 before writing any `labels:` field, and re-invoke it at Step 4 before displaying the YAML. Every entry must match byte-for-byte (case, spaces, punctuation) a label name in `planning/.label-allowlist.txt` (see `~/.claude/skills/workflows/label-allowlist/SKILL.md`). If no listed label fits, omit the `labels:` key entirely — do not write `labels: []`. Never fabricate, extrapolate from prior MRs, or copy from a stale draft. Whether `projctl create-mr` rejects unknown labels at submit or not, this pre-flight is the primary gate — do not rely on the tool as a backstop. Note: this pre-flight verifies only what the workflow writes into `labels:`; if `projctl create-mr` applies `labels.default` from projctl config, those entries are NOT verified here (see the fragment's Residual failure paths).

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
