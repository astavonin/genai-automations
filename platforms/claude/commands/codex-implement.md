---
name: codex-implement
description: Run a Codex implementation via codex-flow from a design document
---

# Codex Implement Command

Run `codex-flow implement` against a design document and display the implementation output.

## Usage

```
/codex-implement planning/<goal>/milestone-XX/design/<feature>-design.md
```

If no path is provided, look for the current milestone's design document.

## Actions

### Step 1: Resolve the design document

**If a path was provided:** verify it exists and starts with `# Design`.

**If no path was provided:** scan `planning/` for the active milestone's design doc:
```bash
ls planning/<goal>/milestone-XX/design/*-design.md
```
If exactly one is found, use it. If multiple are found, ask the user to specify.

### Step 2: Confirm before running

State the design document path and the implementation output path
(`<design-stem>.implementation-output.md` in the same directory) and ask the user to confirm
before proceeding — `codex-flow implement` modifies repository files.

### Step 3: Run codex-flow

```bash
codex-flow implement <design-doc-path>
```

`codex-flow` validates the document, invokes `codex exec` in workspace-write mode (allows
file modifications), runs the verification commands from the design doc's `Verification`
block, and writes a standardised output artifact.

### Step 4: Read and display results

Read the output file printed by `codex-flow` (`<design-stem>.implementation-output.md`).
Display the summary, files changed, verification results, and any open issues to the user.

## Notes

- The design document must follow `~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md` — `codex-flow` parses the `Implementation Context` section for Repository, Requirements, Constraints, Verification, and Context Files.
- `codex-flow implement` runs in `workspace-write` sandbox — Codex can modify files in the repository.
- After implementation, run `/review-code` as the mandatory code review checkpoint.
