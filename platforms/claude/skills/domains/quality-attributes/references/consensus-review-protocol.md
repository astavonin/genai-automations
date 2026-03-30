# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

## How It Works

Three independent reviewer agents evaluate the subject in parallel. A finding is only
included in the final output if **at least 2 of 3 agents** independently flag it.
The consensus severity is determined the same way: the severity level that **at least
2 agents agree on**. If all three differ, use the middle severity (e.g., Critical/High/Low
→ use High).

## Protocol Steps

### Step A: Launch 3 Independent Reviewers and Codex in Parallel (+ test-coverage agent for code reviews)

Spawn three **reviewer (opus)** agents and Codex simultaneously. For **code reviews** also spawn
the test-coverage agent (Step F) in the same batch — do not launch it for design reviews.
All agents run in parallel to minimise wall-clock time. Each Claude agent:
- Receives the same input: the subject under review + MR/design context (title, description)
- Receives: `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`
- Works **independently** — no shared state, no knowledge of other agents' outputs
- Produces a raw findings list: each finding has a `title`, `severity`, and `description`

Severity scale (same for all agents):
- `Critical` — will definitely fail, crash, or cause data loss
- `High` — significant correctness or security issue
- `Medium` — notable quality concern (test gaps, maintainability)
- `Low` — minor suggestion

### Step B: Aggregate — Issue Consensus

Group findings from all three agents by topic. Two findings refer to the same issue if they
describe the same root cause in the same code location (fuzzy match on concept, not wording).

**Inclusion rule:** include a finding only if **2 or more agents** flagged it.

Discard any finding that only 1 agent raised.

### Step C: Aggregate — Severity Consensus

For each included finding, collect the severities reported by the agents that flagged it:

| Votes | Rule |
|-------|------|
| 2/2 or 3/3 agree | Use agreed severity |
| 2/3 agree | Use the agreed severity |
| All 3 differ | Use the middle severity (sort Critical→High→Medium→Low, pick middle) |

### Step D: Produce Consolidated Findings List

Output: a deduplicated list of findings, each with:
- Consensus `title` (synthesize from agreeing agents)
- Consensus `severity`
- `description` — synthesized explanation of why the issue exists
- `location(s)` — from whichever agent(s) identified the specific code site
- `fix` — synthesized recommendation (where agents agree on the approach)

### Step E: Codex Cross-Model Verification

Codex runs in parallel with Step A (not after Step D). Once both the Claude consensus (Steps B–D)
and the Codex output are available, cross-aggregate them.

Run Codex via Bash from the project's working directory:

**For design/code reviews:**
```bash
~/.claude/scripts/codex-pipe \
  --prompt "Review the following for quality attributes (supportability, extendability, maintainability, testability, performance, safety, security, observability). List findings with severity Critical, High, Medium, or Low. Be concise." \
  --output /tmp/codex-review.txt \
  <subject-file>
```

**For MR reviews** — substitute `<source>` and `<target>` with the actual branch names
obtained in Step 2 of the calling command (e.g. `spring-core-crm` and `main`):
```bash
codex review "DO NOT make any changes. Only print your findings. \
Review the diff from origin/<target> to origin/<source>. \
Focus on bugs, security issues, logic errors, and standards compliance. \
Rate each finding Critical, High, Medium, or Low. Be concise." \
> /tmp/codex-review.txt 2>&1
```

**IMPORTANT — always redirect Codex output to a file.** Never pipe to `head` or truncate inline.
Codex spends multiple turns reading files before printing findings; truncating early discards all results.

**IMPORTANT — always set a 600-second timeout** on the Bash call that runs Codex.
The default 120-second timeout is too short for non-trivial codebases and will kill the process
before findings are printed, producing an empty or incomplete output file.

After the command completes, read the file in full:
```bash
wc -l /tmp/codex-review.txt   # check size first
```
- If ≤ 300 lines: read the whole file with the Read tool in one call.
- If > 300 lines: read iteratively in 200-line chunks (offset + limit) until the end of file.

**Cross-aggregate the results:**

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** Codex | Mark as **✓ Corroborated by Codex** |
| Claude consensus only | Include as-is (already filtered by 2/3) |
| Codex only | Include separately under **"Codex-only findings"** |

Two findings refer to the same issue if they describe the same root cause at the same code location (fuzzy match on concept, not wording).

The final output handed to the calling command contains:
1. Consensus findings (with corroboration tags where applicable)
2. Codex-only findings (separate section, labeled clearly)

### Step F: Test-Coverage and Pitfalls Agent (code review only — skip for design reviews)

A dedicated **reviewer (opus)** agent runs in parallel with Step A, focused exclusively on test
quality. It does **not** participate in the 3-agent consensus (Steps B–C) — its output is
cross-aggregated separately, the same way Codex findings are handled in Step E.

**Only applicable when actual code and tests exist.** Do not launch this agent for design
reviews (`/review-design`) — there is no code or test suite to evaluate yet.

**Prompt the agent with:**
```
You are a test-quality reviewer. Your ONLY job is to find gaps in test coverage and test anti-patterns.
Do NOT report on code correctness, security, or architecture — those are covered by other reviewers.

Read ~/.claude/skills/domains/testing/SKILL.md for the testing rules.
Read ~/.claude/skills/domains/testing/references/advanced-testing.md for anti-patterns.

Evaluate the subject under review for:
1. Missing unit tests — public functions/methods with no test, untested edge cases (null, empty, boundary, error)
2. Missing integration tests — component boundaries that touch DB/HTTP/broker with no integration test
3. Integration tests not tagged to run separately (missing //go:build integration, @pytest.mark.integration, etc.)
4. Test anti-patterns:
   - Tests that depend on execution order
   - Tests that duplicate production logic instead of testing outcomes
   - Bare sleep() used as a wait strategy
   - Overly brittle mocks (mocking internals instead of boundaries)
   - No assertion or a single trivial assertion that can never fail
   - Flaky indicators (time-dependent assertions, non-deterministic ordering)
5. Mock overuse — infrastructure (DB, cache, broker) mocked instead of using a fake or testcontainers

Rate each finding: Critical (no tests for public API), High (significant gap), Medium (anti-pattern, missing edge case), Low (minor improvement).
Output a raw list: title, severity, description, location.
```

**Cross-aggregate its output** after both it and the Claude consensus (Steps B–D) are available:

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** test-coverage agent | Mark as **✓ Corroborated by test-coverage agent** |
| Claude consensus only | Include as-is |
| Test-coverage agent only | Include under **"Test-coverage findings"** (separate section) |

## What Each Agent Should NOT Flag

To keep signal high, instruct each agent to skip:
- Pre-existing issues not introduced by the change under review
- Subjective style preferences
- Potential bugs that depend on specific inputs without clear evidence
- Nitpicks a senior engineer would not raise in a review

## Notes

- Each agent must be told the same context (title, description, diff or design doc)
- Agents must not be shown each other's output before Step B
- The aggregation (Steps B–C) is performed by the main conversation, not by a subagent
- Step E (Codex) and Step F (test-coverage agent) both run **in parallel** with Steps A–D
- Redirect Codex output to a file (`> /tmp/codex-review.txt 2>&1`) and read the file after it completes — never truncate with `head`
- The final report sections are: Consensus findings → Codex-only findings → Test-coverage findings
