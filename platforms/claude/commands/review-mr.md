---
name: review-mr
description: Review MR code and generate YAML for projctl comment
---

# MR Review Command

Conduct a code review of a GitLab Merge Request using the reviewer agent and generate
a structured YAML findings file for posting inline comments via `projctl comment`.

## Agent

**reviewer** (opus model)

## Setup

Read review skills before starting:
```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

## Prerequisites

- MR exists in GitLab and the branch is pushed
- `projctl` installed and configured
- `projctl` configured and platform authenticated (run: `projctl --help` to verify)

## Workflow

### Step 1: Resolve MR

Parse the MR reference provided by the user:

```
/review-mr !134        # MR number with exclamation prefix
/review-mr 134         # bare MR number
```

**Known Limitation:** Auto-detection from current branch is not supported. Always provide
the MR number explicitly.

### Step 2: Load MR Context

```bash
projctl load mr <mr_number>
```

Extract: MR title, source branch, target branch, description, list of changed files.

If load fails (MR does not exist, permissions error, network issue):
- Report the specific error to the user
- Stop and do not proceed

### Step 3: Gather Diff

Use the source branch obtained from Step 2 (not `HEAD`, which may be on a different branch):

```bash
git fetch origin <source_branch> <target_branch>
git diff origin/<target_branch>...origin/<source_branch> --stat   # file summary
git diff origin/<target_branch>...origin/<source_branch>           # full diff for review
```

**Large Diff Handling:** If the diff is very large (>100KB):
1. Show the `--stat` summary to the user
2. Warn about the size and potential context window limits
3. Suggest reviewing specific files or splitting the review across sessions
4. Optionally proceed with the most critical changed files only

### Step 4: Multi-Agent Consensus Review

Run the **Consensus Review Protocol** (Steps 0, A–E) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Step 0 (do first, before any agents):** Write `planning/reviews/MR<number>-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** `origin/<target_branch>...origin/<source_branch>`
- **Output File:** `planning/reviews/MR<number>-codex-review.md`
- **Requirements:** key requirements extracted from the MR description
- **Evidence:** `git diff origin/<target_branch>...origin/<source_branch> --stat` output
- **Review Focus:** bugs, security issues, logic errors, standards compliance

**Step A (single message):** Launch simultaneously:
- 3 × reviewer (opus) Agent calls with the full diff, MR title/description, and review checklist
- `codex-flow` Bash call with `run_in_background: true`:
  ```bash
  codex-flow review planning/reviews/MR<number>-review-request.md
  ```

Aggregate once all four have returned per protocol Steps B–E.

Severity scale:
- `Critical` - Must fix before merge (security, data loss, crashes)
- `High` - Should fix before merge (significant correctness/maintainability issues)
- `Medium` - Consider fixing (improvements, test gaps, style issues)
- `Low` - Optional suggestions (minor enhancements)

**Content sanitization:** Do NOT use `@username` patterns in finding descriptions.
GitLab will interpret these as real user mentions and send notifications.

### Step 5: Generate and Validate YAML

**5a. Generate YAML**

Write the review to `planning/reviews/MR<number>-review.yaml` following the schema below.
Include ALL findings: consensus findings first, then Codex-only findings (prefix their title
with `[Codex]` so reviewers can distinguish them).

If this file already exists (re-review), it will be overwritten. Previous review output
is not preserved. Copy the file manually before re-running if you need to keep it.

**5b. Validate YAML**

Before saving, parse and verify:
1. Valid YAML syntax (no parse errors)
2. Required top-level fields present: `mr_number`, `title`, `review_date`, `findings`
3. `mr_number` is an integer (not a string)
4. Each finding has required fields: `severity`, `title`, `description`
5. Each finding with a location uses a specific line number present in the diff — never `:1` as a placeholder
6. Severity values are exactly one of: `Critical`, `High`, `Medium`, `Low` (case-sensitive)

If validation fails:
- Report the specific validation errors to the user
- Re-attempt YAML generation with corrected instructions
- Do not proceed to Step 6 until validation passes

### Step 6: Display Summary and Post Instructions

Show the user:
- Total finding count by severity (Critical: N, High: N, Medium: N, Low: N)
- Overall assessment based on findings:
  - **Approve** — zero `Critical` and zero `High` findings
  - **Request Changes** — one or more `Critical` or `High` findings
- Full path to the YAML file

Ask the user if they want to `open <path>` the YAML file before displaying the post instructions.

Then display:
```
Review written to: planning/reviews/MR<number>-review.yaml

To preview (dry-run):
  projctl comment planning/reviews/MR<number>-review.yaml --dry-run

To post inline comments to the MR:
  projctl comment planning/reviews/MR<number>-review.yaml
```

The command never posts automatically. Posting requires explicit user action.

**Re-posting warning:** Running `comment` more than once on the same YAML will create duplicate comments on the MR. If a previous posting attempt failed or was partial, resolve the underlying issue (e.g. fix `:1` line numbers in the YAML) before re-running — do not retry blindly.

---

## YAML Schema

```yaml
mr_number: 134                          # integer, REQUIRED
title: "Brief MR title"                 # string, REQUIRED (match MR title)
review_date: "2026-02-11"               # YYYY-MM-DD, REQUIRED

findings:
  - severity: Critical                  # REQUIRED: Critical | High | Medium | Low
    title: "Brief problem statement"    # REQUIRED: concise, specific
    description: |                      # REQUIRED: what breaks and why it matters — 1-3 sentences max
      Short, plain statement of the problem and its impact.
    location: "path/to/file.cc:123"     # Single file:line (use this OR locations)
    locations:                          # Multiple files (use this OR location)
      - "path/to/file.cc:181"
      - "path/to/other.h:28"
    fix: |                              # OPTIONAL: concrete recommendation
      Specific code change or approach to fix the issue.
    guideline: "C++ Core Guidelines F.53"  # OPTIONAL: null if none
```

**Description writing rules:**
- 1–3 sentences maximum — state what breaks and what the impact is
- Plain language: write for a developer skimming a review, not a formal report
- Never passive-aggressive: no "you should have", "obviously", "this ignores", "dangerously", "poorly"
- Focus on the problem, not the author — describe what the code does, not what the person did
- Bad: "This function dangerously ignores the error return value." Good: "If the error return is ignored here, the caller proceeds with an invalid state."

**Schema rules:**
- `location` (singular) and `locations` (plural list) are mutually exclusive
- Every finding must have at least one location; findings without locations are skipped
- Line ranges (`123-145`) are supported; only start line is used for inline posting
- **Always use a specific line number from the diff.** If no exact line is known, omit `location`/`locations` entirely — the tool will fall back to a general MR note. Never use `:1` as a placeholder; GitLab returns HTTP 500 for inline comments on lines not present in the diff.
- Use `null` for optional fields with no value (not empty string)
- Use `|` for multi-line strings (description, fix)
- Order findings by severity: Critical → High → Medium → Low

**Clean review (no findings):**
```yaml
mr_number: 134
title: "Brief MR title"
review_date: "2026-02-11"
findings: []
```

---

## Example Output

```yaml
mr_number: 156
title: "Add adaptive cache invalidation"
review_date: "2026-02-11"

findings:
  - severity: Critical
    title: "SQL injection via unsanitized user input"
    description: |
      `build_query()` concatenates `filter` directly into the SQL string.
      Any caller-controlled value can read or modify arbitrary tables.
    location: "src/db/query_builder.cc:45"
    fix: "Use parameterized queries: `db.execute(\"SELECT ... WHERE name = ?\", [filter])`"
    guideline: "OWASP A03:2021 Injection"

  - severity: High
    title: "Race condition in cache invalidation"
    description: |
      `valid_` is read and written in `invalidate()` without synchronization.
      Concurrent calls can leave the cache in a partially-invalidated state.
    location: "src/cache/cache_manager.cc:87"
    fix: "Protect the check-then-act with a mutex, or use std::atomic with compare-exchange."
    guideline: "C++ Core Guidelines CP.2"

  - severity: Medium
    title: "Missing unit test for invalidation during in-flight read"
    description: |
      No test covers invalidation called while a read is pending.
      The scenario exists in the integration test but not in isolation.
    location: "tests/cache/test_cache_manager.cc:1"
    fix: "Add a unit test that calls invalidate() concurrently with a pending read."
    guideline: null

  - severity: Low
    title: "Unused constructor parameter"
    description: "`timeout_ms` is stored but never read. Remove it or wire it up."
    location: "src/cache/cache_manager.cc:12"
    fix: "Remove the parameter or implement timeout behavior."
    guideline: null
```
