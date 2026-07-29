---
name: codex-implement
description: Run a Codex implementation via codex-flow from a design document
---

# Codex Implement Command

Run `codex-flow implement` against a design document and display the implementation output.

## Usage

```
/codex-implement planning/<goal>/milestone-XX/issues/<NNN-name>/design.md
```

If no path is provided, look for the current milestone's design document.

## Actions

### Step 1: Resolve the design document

**If a path was provided:** verify it exists and starts with `# Design`.

**If no path was provided:** scan `planning/` for the active milestone's design doc:
```bash
ls planning/<goal>/milestone-XX/issues/
```
If exactly one is found, use it. If multiple are found, ask the user to specify.

### Step 2: Confirm before running

State the design document path and the implementation output path
(`<design-stem>.implementation-output.md` in the same directory) and ask the user to confirm
before proceeding — `codex-flow implement` modifies repository files.

### Step 3: Run codex-flow with progress monitoring

Launch codex-flow as a background task:

```bash
codex-flow implement <design-doc-path>
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

Run via the Monitor tool — each parsed line appears as a notification. The Monitor exits when
Codex emits `workflow_complete`. The background task completion notification confirms the output
file is ready.

`codex-flow` validates the document, invokes `codex exec` in workspace-write mode (allows
file modifications), runs the verification commands from the design doc's `Verification`
block, and writes a standardised output artifact.

### Step 4: Read and display results

Read the output file printed by `codex-flow` (`<design-stem>.implementation-output.md`).
Display the summary, files changed, verification results, and any open issues to the user.

### Step 5: Resolve the observed-failure ledger

If this implementation fixed a failure that actually happened, the ledger entry `/diagnose` or `/ci-debug` wrote is still `**Status:** open` — Codex returns JSON, not planning files, so nothing has discharged it. Left open, `/verify` Step 6d blocks with "add the regression test" for a test that already exists.

```
Read ~/.claude/skills/workflows/issue-folder-resolve/SKILL.md
```

Resolve `<issue-folder>`, and for each entry in `<issue-folder>/observed-failures.md` that this run addressed: replace `**Status:** open` with `**Status:** covered` (edit the line in place — a second Status line makes the entry malformed) and fill `**Test:**` and `**Evidence:**` from Codex's `verification_results`. If Codex reported `"Regression test: BLOCKED — ..."` in `open_issues`, leave the entry `open` and surface that blocker to the user.

Before Step 3 runs, if this work fixes a failure that actually occurred, paste the entries from `<issue-folder>/observed-failures.md` into the design doc's §3 `**Observed-Failure Ledger:**` field. `codex-flow implement` is given only the design document — it never sees the issue folder — so an omitted ledger reads to Codex as new work and the required regression test is silently skipped.

## Notes

- The design document must follow `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md` — `codex-flow` parses the `Implementation Context` section for Repository, Functional Requirements, Non-Functional Requirements, Constraints, Verification, and Context Files.
- `codex-flow implement` runs in `workspace-write` sandbox — Codex can modify files in the repository.
- After implementation, run `/review-code` as the mandatory code review checkpoint.
