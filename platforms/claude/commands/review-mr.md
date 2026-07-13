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

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
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
projctl load mr <mr_number> --comments
```

Extract: MR title, source branch, target branch, description, list of changed files, and all existing comments (human and automated). Pass existing comments to reviewer agents as context so they avoid duplicating already-raised points and can see what discussion has already happened on the MR.

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

### Step 3b: Pre-read Context

Before launching any agents, gather inline context to pass in agent prompts:
- **Interface files not in the diff:** for each changed `.cc`/`.cpp`/`.c` file, also read its `.h`/`.hpp` if it exists and is not in the diff; for Go, read interface definition files the changed package implements
- **Full design doc** (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`) if one exists — the entire file, not just acceptance criteria
- **Prior review:** if `planning/reviews/MR<number>-review.yaml` exists from a prior review cycle, read it. Instruct each agent: "A prior review exists. For each prior finding, verify whether it has been addressed. Re-raise unaddressed findings at their original severity."

### Step 4: Multi-Agent Consensus Review

Run the **Consensus Review Protocol** (Steps 0, A–H) from:
`~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md`

**Step 0 (do first, before any agents):** Write `planning/reviews/MR<number>-review-request.md`
from the review request template:
- **Repository:** absolute path to the current repo
- **Review Scope:** `origin/<target_branch>...origin/<source_branch>`
- **Output File:** `planning/reviews/MR<number>-codex-review.md`
- **Requirements:** key requirements extracted from the MR description
- **Evidence:** run the project's build and test commands; capture exit codes + last 40 lines of output and paste here. If unavailable, use `git diff --stat` as a fallback.
- **Review Focus:** bugs, security issues, logic errors, standards compliance

```
Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
```
(`test_coverage = yes`)

**Step A (single message):** Launch simultaneously:
- 3 × reviewer (opus) Agent calls with the full diff, MR title/description, review checklist, and the **Writing Style** rules from this skill (sound human, be friendly, never blame, focus on the problem not the person — full rules are under "YAML Schema → Writing style" below)
- 1 × test-coverage reviewer (opus) Agent call per **Step F** of the consensus protocol — use the exact prompt defined there, passing the full diff as the subject under review
- `codex-flow` Bash call with `run_in_background: true`:
  ```bash
  codex-flow review planning/reviews/MR<number>-review-request.md
  ```

Aggregate once all five have returned per protocol Steps B–H:
- Test-coverage findings that also appear in Claude consensus: mark as corroborated
- Test-coverage-only findings: merge into the YAML findings list as regular findings (no separate section — YAML format has no sections)
- Step G reverified findings: merge into the YAML findings list. Prefix the finding description with exactly `[Reverified] ` (bracketed literal, single trailing space) so downstream consumers can distinguish findings that survived the adversarial pass from consensus findings. This prefix is required, not optional.

**Before launching Step G verifier agents:** reuse the `Repository:` absolute path already written into `planning/reviews/MR<number>-review-request.md` (Step 0) — this is the same value Codex used. If Step 0 was skipped or the `Repository:` field is missing/empty, fall back to running `pwd` in the main conversation's shell. If both fail, do NOT launch Step G verifier agents — surface the warning defined in protocol §Step G "How the main conversation obtains Repository" and treat all Step G-eligible findings as discarded-with-warning under rule 4 semantics. Supply the resolved path as the `Repository:` field in each verifier prompt.

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
Include ALL findings from the aggregation pipeline in this order: consensus findings first, then Step G `[Reverified]` survivors (single-agent Claude and Codex-only findings that both verifiers CONFIRMED — Step G rejects — REFUTED and unparseable-after-retry — MUST NOT appear in the YAML; rule 4 warnings surface unparseable-after-retry cases to the user, not the YAML), then Step F test-coverage-only findings. Do NOT prefix titles with `[Codex]` or any other source label — all findings appear identically regardless of origin; use only the `[Reverified]` description prefix defined in Step 4 for Step G survivors.

**Before writing each finding description:** rewrite it to follow the Writing Style rules below — sound human, friendly, no blame, focus on the problem not the person. Raw reviewer agent wording may not follow these rules; the aggregation step is where style is enforced.

If this file already exists (re-review), it will be overwritten. Previous review output
is not preserved. Copy the file manually before re-running if you need to keep it.

**5b. Validate YAML**

Before saving, parse and verify:
1. Valid YAML syntax (no parse errors)
2. Required top-level fields present: `mr_number`, `title`, `review_date`, `codex`, `findings`; `approval` is optional (defaults to `"approved"`) but when present must be one of `"approved"`, `"changes_requested"`, `"none"`
3. `mr_number` is an integer (not a string)
4. Each finding has required fields: `severity`, `title`, `description`
5. Each finding with a location uses a specific line number present in the diff — never `:1` as a placeholder
6. Severity values are exactly one of: `Critical`, `High`, `Medium`, `Low` (case-sensitive)
7. Any finding that identifies **incorrect runtime behavior** (wrong output, data corruption, silent invalid-input acceptance, infinite loop, security bypass) MUST include a `Required test:` line inside its `fix:` field describing: what input triggers the bug and what the test asserts

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

### Step 7: Update Planning State and Push

**If the MR being reviewed is linked to an active issue in `progress.md`** (look for the MR number in the Active section or `status.md`):

Update `planning/progress.md` Active entry:
- Append `- MR review written: <N> findings (Critical: N, High: N, Medium: N, Low: N)`
- Update `**Last Updated:**` to today's date.

**Always** push planning to backup after writing the YAML:
```bash
```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```
Follow the steps in that fragment. Surface the §8.2 warning block on failure; do not fail the skill.

---

## Reply Drafting Guidelines

When drafting replies to reviewer comments (for posting via `projctl comment` with a `replies:` section), apply the same writing style as finding descriptions (see above), plus:

- When agreeing: state what was fixed, one sentence, done.
- When pushing back: explain the reasoning directly — the goal is shared understanding, not winning the point.

**Re-posting warning:** Running `comment` more than once on the same YAML will create duplicate comments on the MR. If a previous posting attempt failed or was partial, resolve the underlying issue (e.g. fix `:1` line numbers in the YAML) before re-running — do not retry blindly.

---

## YAML Schema

```yaml
mr_number: 134                          # integer, REQUIRED
title: "Brief MR title"                 # string, REQUIRED (match MR title)
review_date: "2026-02-11"               # YYYY-MM-DD, REQUIRED
codex: ran                              # REQUIRED: "ran" | "not run: <reason>"
approval: approved                      # "approved" | "changes_requested" | "none" — default: "approved"
                                        # projctl comment applies this automatically after posting findings

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

**Writing style — applies to all review output (finding descriptions, fix suggestions, and replies):**
- Sound human: write like messaging a colleague, not filing a report. No opener boilerplate ("Thank you for the feedback", "Great point", "You are correct that…").
- Be friendly: acknowledge the point before explaining or disagreeing. Short sentences, first person is fine.
- Never blame: don't mention how a mistake happened ("I forgot", "this was left over", "accidentally"). Don't attribute problems to prior authors or external constraints. State what's wrong or what changed — nothing more.
- Focus on the problem, not the person: describe what the code does, not what the author did or failed to do.
- 1–3 sentences per finding description — state what breaks and what the impact is.
- No passive-aggressive language: never "you should have", "obviously", "this ignores", "dangerously", "poorly".
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
codex: ran
findings: []
```

---

## Example Output

```yaml
mr_number: 156
title: "Add adaptive cache invalidation"
review_date: "2026-02-11"
codex: ran

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
