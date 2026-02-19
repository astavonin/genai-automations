---
name: review-mr
description: Review MR code and generate YAML for ci-platform-manager comment
---

# MR Review Command

Conduct a code review of a GitLab Merge Request using the reviewer agent and generate
a structured YAML findings file for posting inline comments via `ci-platform-manager comment`.

## Agent

**reviewer** (opus model)

## Prerequisites

- MR exists in GitLab and the branch is pushed
- `ci-platform-manager` installed and configured
- Platform CLI authenticated (`glab` for GitLab)

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
ci-platform-manager load !<mr_number>
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

Run the **Consensus Review Protocol** (Steps A–E) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Launch simultaneously: Steps A–D (Claude) and Step E (Codex) in parallel.**

Do not wait for Claude agents to finish before starting Codex — they are independent.
Aggregate once all four have returned.

**Steps A–D: Claude consensus**

Pass to each of the 3 independent reviewer agents:
- Full diff (or focused subset for large diffs)
- MR title and description
- Review checklist from `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- Instruction to produce a raw findings list: `title`, `severity`, `description`, `location(s)`

After all 3 agents complete, aggregate per the protocol (Steps B–C):
- **Issue included:** 2 or more agents flagged it
- **Severity:** level that 2+ agents agree on; if all 3 differ, use the middle level

**Step E: Codex cross-model verification**

Run from the project's working directory (in parallel with Step A):
```bash
codex review "DO NOT make any changes. Only print your findings. Review for bugs, security issues, logic errors, and standards compliance. Rate each finding Critical, High, Medium, or Low. Be concise."
```

Cross-aggregate with the Claude consensus findings per the protocol.

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

If this file already exists (re-review), it will be overwritten. Previous review output
is not preserved. Copy the file manually before re-running if you need to keep it.

**5b. Validate YAML**

Before saving, parse and verify:
1. Valid YAML syntax (no parse errors)
2. Required top-level fields present: `mr_number`, `title`, `review_date`, `findings`
3. `mr_number` is an integer (not a string)
4. Each finding has required fields: `severity`, `title`, `description`
5. Each finding has at least one location (`location` or `locations`)
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

Then display:
```
Review written to: planning/reviews/MR<number>-review.yaml

To preview (dry-run):
  ci-platform-manager comment planning/reviews/MR<number>-review.yaml --dry-run

To post inline comments to the MR:
  ci-platform-manager comment planning/reviews/MR<number>-review.yaml
```

The command never posts automatically. Posting requires explicit user action.

---

## YAML Schema

```yaml
mr_number: 134                          # integer, REQUIRED
title: "Brief MR title"                 # string, REQUIRED (match MR title)
review_date: "2026-02-11"               # YYYY-MM-DD, REQUIRED

findings:
  - severity: Critical                  # REQUIRED: Critical | High | Medium | Low
    title: "Brief problem statement"    # REQUIRED: concise, specific
    description: |                      # REQUIRED: WHY this is an issue
      Technical explanation of the problem, its impact, and why it matters.
    location: "path/to/file.cc:123"     # Single file:line (use this OR locations)
    locations:                          # Multiple files (use this OR location)
      - "path/to/file.cc:181"
      - "path/to/other.h:28"
    fix: |                              # OPTIONAL: concrete recommendation
      Specific code change or approach to fix the issue.
    guideline: "C++ Core Guidelines F.53"  # OPTIONAL: null if none
```

**Schema rules:**
- `location` (singular) and `locations` (plural list) are mutually exclusive
- Every finding must have at least one location; findings without locations are skipped
- Line ranges (`123-145`) are supported; only start line is used for inline posting
- Locations without `:line` are normalized to `:1`
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
      The `build_query()` function at line 45 concatenates the user-provided
      `filter` parameter directly into the SQL string without sanitization.
      An attacker can inject arbitrary SQL and read or modify any table.
    location: "src/db/query_builder.cc:45"
    fix: |
      Use parameterized queries: `db.execute("SELECT ... WHERE name = ?", [filter])`
    guideline: "OWASP A03:2021 Injection"

  - severity: High
    title: "Race condition in cache invalidation"
    description: |
      The invalidation check in `CacheManager::invalidate()` reads and writes
      the `valid_` flag without synchronization. Concurrent calls can result
      in a partially-invalidated cache being treated as valid.
    location: "src/cache/cache_manager.cc:87"
    fix: |
      Protect the check-then-act sequence with a mutex or use std::atomic
      with a compare-exchange operation.
    guideline: "C++ Core Guidelines CP.2"

  - severity: Medium
    title: "Missing unit test for invalidation edge case"
    description: |
      The case where invalidation is called while an in-flight read is pending
      has no test coverage. This path is exercised in the integration scenario
      but not in isolation.
    location: "tests/cache/test_cache_manager.cc:1"
    fix: |
      Add a test that triggers invalidation concurrently with a pending read,
      verifying the read either completes with old data or is retried.
    guideline: null

  - severity: Low
    title: "Unused parameter in constructor"
    description: |
      The `timeout_ms` parameter in `CacheManager::CacheManager()` is stored
      but never used in any method. Either remove it or implement the timeout.
    location: "src/cache/cache_manager.cc:12"
    fix: "Remove unused parameter or implement timeout behavior."
    guideline: null
```
