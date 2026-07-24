---
name: codex-review
description: Run a Codex review via codex-flow from a review request document
---

# Codex Review Command

Run `codex-flow review` against a review request document and display the findings.

## Usage

```
/codex-review planning/<epic-slug>/reviews/<feature>-review-request.md
```

If no path is provided, generate a new review request document from the template first.

## Path conventions

- **MR-scoped review:** input and output live under `planning/<epic-slug>/reviews/`. The `<epic-slug>` follows the folder used by `/review-mr` for the same epic. Typically invoked via `/review-mr` rather than directly.
- **Issue-scoped review:** input at `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/codex-review-request.md`; output at `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/codex-review.md`. Single canonical file, always overwritten — no `-r<N>`, `-final`, or `-v2` filename suffixes.
- **Never** write to a top-level `planning/reviews/` directory. That layout is retired — see CLAUDE.md "Planning Structure".

Every iteration overwrites in place. If the reviewer or the user needs to compare against a prior round, they use `git log` on the file, not filename versioning.

## Actions

### Step 1: Resolve the review request document

**If a path was provided:** verify it exists and starts with `# Review Request`. If the path is inside `planning/reviews/` (top-level) rather than under an epic folder, warn the user — the layout is retired.

**If no path was provided:**
1. Read `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md`
2. Ask the user for the review scope so the default path resolves correctly:
   - **Issue-scoped** → default paths under `planning/<epic-slug>/milestone-XX-<name>/issues/<NNN-name>/`
   - **MR-scoped** → default paths under `planning/<epic-slug>/reviews/`. **Note:** standalone MR-scoped use is unusual — consider `/review-mr` instead. If the user confirms MR-scoped, ask for the MR number and run the same epic-slug resolution chain as `/review-mr` Step 2b (MR → linked issue → epic → slug). Reuse an existing `planning/<epic-slug>/` folder if one is found; derive a new slug and confirm with the user otherwise. Do not proceed with a bare `<epic-slug>` placeholder — the output file must resolve to a real path.
3. Ask the user for the required template fields:
   - Repository (absolute path)
   - Branch
   - Review Scope (e.g. `HEAD~1..HEAD`)
   - Output File — pick from the path convention above based on scope
   - Requirements (one or more bullets)
   - Constraints (one or more bullets)
   - Evidence (bash commands + exit codes)
   - Review Focus (one or more bullets)
4. Write the completed document to the scope-appropriate `*-review-request.md` path (never top-level `planning/reviews/`).

### Step 2: Run codex-flow with progress monitoring

Launch codex-flow as a background task:

```bash
codex-flow review <review-request-path>
```

Run with `run_in_background: true`. Then immediately start a Monitor to show live progress:

```bash
sleep 2
PROGRESS=$(ls -t /tmp/codex-flow-progress-state-*/codex-flow/runs/*/*.jsonl 2>/dev/null | head -1)
if [ -n "$PROGRESS" ]; then
  tail -f "$PROGRESS" | while IFS= read -r line; do
    jq -r '"[codex] \(.status) \(.phase): \(.message)"' <<< "$line" 2>/dev/null
    [[ "$line" == *"workflow_complete"* ]] && break
  done
fi
```

Run via the Monitor tool — each parsed line appears as a notification showing what phase Codex
is in. The Monitor exits when Codex completes. The background task completion notification
confirms the output file is ready.

### Step 3: Read and display results

Read the output file produced by `codex-flow` (the path from the `Output File` field in the
review request). Display the findings to the user.

### Step 4: Post-consumption cleanup (only when this command is invoked standalone)

When `/codex-review` is called from a higher-level command (`/review-mr`, `/review-fix`), that command owns the intermediate lifecycle and will delete the review-request + codex-review files after folding them into a final published artifact. **Do not delete anything here in that case.**

When invoked standalone by the user, the codex-review output is the deliverable; the review-request stays in place so a re-invocation can reuse it. The next standalone `/codex-review` run against the same feature will overwrite both.

## Notes

- The output file path is determined by the `Output File` field in the review request document — `codex-flow` resolves it relative to the repository.
- `codex-flow` aborts if Codex modifies any file other than the output file — the read-only guarantee is enforced automatically.
- To integrate Codex findings into a full consensus review, use `/review-code`, `/review-design`, `/review-mr`, or `/review-fix` instead.
