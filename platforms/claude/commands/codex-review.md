---
name: codex-review
description: Run a Codex review via codex-flow from a review request document
---

# Codex Review Command

Run `codex-flow review` against a review request document and display the findings.

## Usage

```
/codex-review planning/reviews/<feature>-review-request.md
```

If no path is provided, generate a new review request document from the template first.

## Actions

### Step 1: Resolve the review request document

**If a path was provided:** verify it exists and starts with `# Review Request`.

**If no path was provided:**
1. Read `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md`
2. Ask the user for the required fields:
   - Repository (absolute path)
   - Branch
   - Review Scope (e.g. `HEAD~1..HEAD`)
   - Output File (e.g. `planning/reviews/<feature>-codex-review.md`)
   - Requirements (one or more bullets)
   - Constraints (one or more bullets)
   - Evidence (bash commands + exit codes)
   - Review Focus (one or more bullets)
3. Write the completed document to `planning/reviews/<feature>-review-request.md`

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

## Notes

- The output file path is determined by the `Output File` field in the review request document — `codex-flow` resolves it relative to the repository.
- `codex-flow` aborts if Codex modifies any file other than the output file — the read-only guarantee is enforced automatically.
- To integrate Codex findings into a full consensus review, use `/review-code`, `/review-design`, `/review-mr`, or `/review-fix` instead.
