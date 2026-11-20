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
PROGRESS_DIR=$(codex-flow progress-dir <design-doc-path> 2>/dev/null)
PROGRESS=$(ls -t "$PROGRESS_DIR"/*.jsonl 2>/dev/null | head -1)
if [ -n "$PROGRESS" ] && [ "$(( $(date +%s) - $(stat -c %Y "$PROGRESS") ))" -le 30 ]; then
  tail -n +1 -f "$PROGRESS" | while IFS= read -r line; do
    jq -r '"[codex] \(.status) \(.phase): \(.message)"' <<< "$line" 2>/dev/null
    [[ "$line" == *"workflow_complete"* ]] && break
  done
else
  echo "[codex] no progress log under 30s old in ${PROGRESS_DIR:-<unresolved>} — live progress unavailable; the background task's completion notification is the authority"
fi
```

Run via the Monitor tool — each parsed line appears as a notification. The Monitor exits when Codex emits `workflow_complete`. The background task completion notification confirms the output file is ready.

Both guards are load-bearing. `codex-flow progress-dir` is what scopes the search to *this* repository — progress logs are stored per repository under a `sha256` key, so globbing every repository's directory attaches the monitor to whichever run on the machine wrote most recently and reports its `workflow_complete` as this run's success. The freshness test then rejects a *previous* run of the same repository, which matters because a request rejected during validation is parsed before any log exists, so this run may have written nothing at all.

`codex-flow` validates the document, invokes `codex exec` with `--dangerously-bypass-approvals-and-sandbox` and no `--sandbox` flag (`danger-full-access` is `run_implementation()`'s internal `sandbox=` value, not argv — Codex runs unsandboxed and may touch anything the user can), runs the verification commands from the design doc's `Verification` block, and writes a standardised output artifact.

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
- `codex-flow implement` runs Codex with **no sandbox** — `tools/codex-flow/codex_flow/runner.py` → `run_implementation()` passes `sandbox="danger-full-access"`, which adds `--dangerously-bypass-approvals-and-sandbox` and, unlike review mode, does *not* pass `--ignore-user-config --ignore-rules`, so `~/.codex/config.toml` and the user's `.rules` apply. Codex can write outside the target repository.
- After implementation, run `/review-code` as the mandatory code review checkpoint.
