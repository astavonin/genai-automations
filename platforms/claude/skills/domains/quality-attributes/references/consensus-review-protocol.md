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

**Before invoking Codex, generate a review request document** from the template at
`~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md` and write it to
`planning/reviews/<feature>-review-request.md`. Fill in all fields from the current review
context (repository, branch, scope, requirements from the design doc, evidence from `/verify`,
review focus from the calling command). The `Output File` field must point to
`planning/reviews/<feature>-codex-review.md` — codex-flow writes its output there automatically.

Run Codex via `codex-flow`:

```bash
codex-flow review planning/reviews/<feature>-review-request.md
```

`codex-flow` validates the request document, invokes `codex exec`, enforces the read-only
guarantee (aborts if Codex modifies any file other than `Output File`), and writes a
standardised Markdown artifact. After it completes, read the output file:

```bash
cat planning/reviews/<feature>-codex-review.md
```

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
- Codex is invoked via `codex-flow review planning/reviews/<feature>-review-request.md` — never call `codex` directly
- The final report sections are: Consensus findings → Codex-only findings → Test-coverage findings
