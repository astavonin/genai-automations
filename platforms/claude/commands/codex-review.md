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

### Step 2: Run codex-flow

```bash
codex-flow review <review-request-path>
```

`codex-flow` validates the document, invokes `codex exec` in read-only mode, enforces
the write-only-to-Output-File guarantee, and writes the findings to the path specified
in the `Output File` field of the review request.

### Step 3: Read and display results

Read the output file produced by `codex-flow` (the path printed by the command).
Display the findings to the user.

## Notes

- The output file path is determined by the `Output File` field in the review request document — `codex-flow` resolves it relative to the repository.
- `codex-flow` aborts if Codex modifies any file other than the output file — the read-only guarantee is enforced automatically.
- To integrate Codex findings into a full consensus review, use `/review-code`, `/review-design`, `/review-mr`, or `/review-fix` instead.
