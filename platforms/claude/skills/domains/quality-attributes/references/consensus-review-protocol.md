# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

## How It Works

Three focus-differentiated reviewer agents evaluate the subject in parallel. The full pipeline is Steps 0–H:

- **Step 0:** Write Codex review-request doc before any agents launch
- **Step A:** 3 Claude reviewers (differentiated focus) + Codex (background) + test-coverage agent (Step F, code reviews only) launch simultaneously
- **Steps B–D:** Claude consensus — findings need 2/3 agreement; single-agent findings route to Step G except test-correctness and cross-site findings which go directly to the report
- **Step E:** Codex cross-aggregate — Codex-only findings route to Step G
- **Step F:** Test-coverage agent (code reviews only) — findings included directly, not filtered by consensus
- **Step G:** Single-finding reverification — 2 agents verify each single-agent/Codex-only finding; include if ≥1 confirms
- **Step H:** Manual passes (code reviews only) — Cross-Site Consistency Pass and Test Quality Pass completion check

## Protocol Steps

### Step 0: Prepare Codex review request (before launching any agents)

**This step must complete before Step A.** Write the Codex review request document from the
template at `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md` and save it to
`planning/reviews/<feature>-review-request.md`. Fill in all fields from the current review
context (repository, branch, scope, requirements, evidence, review focus). The `Output File`
field must point to `planning/reviews/<feature>-codex-review.md`.

This takes seconds and unblocks Codex from starting the moment Step A fires.

### Step A: Launch 3 Independent Reviewers, Codex, and test-coverage agent simultaneously

> **🚫 HARD GATE — do not send this message until BOTH conditions are met:**
> 1. All Agent calls for this review are present in this message.
> 2. The `codex-flow` Bash call (`run_in_background: true`) is present in this message.
>
> **No justification overrides this gate.** "GitLab unreachable", interruptions, time pressure, and any other reason do NOT permit skipping `codex-flow`. If `codex-flow` cannot launch, do not send the agent calls either — surface the blocker to the user and resolve it before proceeding.

**Send all of the following in a single message so they run in parallel:**
- Three **reviewer (opus)** Agent calls (Steps B–D)
- One `codex-flow` Bash call with `run_in_background: true`:
  ```bash
  codex-flow review planning/reviews/<feature>-review-request.md
  ```
- For **code reviews only:** one test-coverage Agent call (Step F) — skip for design reviews

Do not split these across separate messages. Codex is typically the slowest; starting it in the
same batch as the Claude agents eliminates its wall-clock cost from the critical path.

**Immediately after (next message): start a Monitor to surface Codex progress:**

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

Run this via the Monitor tool so each parsed line appears as a notification. The Monitor exits
automatically when Codex emits `workflow_complete`. The background Bash completion notification
then confirms the output file is ready to read.

Each Claude agent receives the same input (subject, MR/design context, full design doc if one exists, review checklist) and works independently. Assign differentiated focus areas to reduce overlap and increase depth per domain:

**Agent 1 — Safety, Security, Performance:**
- Safety: error handling, edge cases, resource cleanup (RAII/defer), thread safety, undefined behavior
- Security: input validation, injection vulnerabilities, secrets handling, authentication/authorization
- Performance: hot-path operations, memory leaks, algorithm efficiency, caching

**Agent 2 — Testability, Correctness:**
- Testability: full Test Quality Pass (enumerate every test — assertion specificity, name/assertion alignment, falsifiability, negative paths)
- Correctness: behavioral bugs — wrong output, data corruption, silent invalid-input acceptance, invariant bypasses
- Code standards: library reuse, common library promotion

**Agent 3 — Observability, Maintainability, Extendability, Supportability:**
- Observability: logging at critical paths, metrics, cross-boundary tracing
- Maintainability: naming, complexity, comments explain WHY not WHAT, project conventions
- Extendability: modularity, abstraction level, extension points
- Supportability: actionable error messages, debugging information, operational concerns

Focus area is a depth-first emphasis, not an exclusive scope. An agent that notices a Critical or High issue outside its focus area must still report it.

Each agent produces a raw findings list: each finding has a `title`, `severity`, and `description`.

Severity scale (same for all agents):
- `Critical` — will definitely fail, crash, or cause data loss
- `High` — significant correctness or security issue
- `Medium` — notable quality concern (test gaps, maintainability)
- `Low` — minor suggestion

### Step B: Aggregate — Issue Consensus

Group findings from all three agents by topic. Two findings refer to the same issue if they
describe the same root cause in the same code location (fuzzy match on concept, not wording).

**Inclusion rule:** include a finding only if **2 or more agents** flagged it.

Do not discard single-agent findings — route them to **Step G** for reverification.

**Exception — single-agent findings that bypass Step G and go directly to the final report:**
- **Test-correctness findings** (name/assertion alignment, vacuous assertions, missing negative paths, bare sleeps): include directly. These are observable facts; a reverifier would confirm the same fact.
- **Cross-site consistency findings** (build flag mismatches across Makefile/CI jobs, function signature mismatches across declarations/overrides/mocks, config value mismatches across consumers): include directly. These are enumerable facts, not judgment calls.

All other single-agent findings → Step G reverification.

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

### Step E: Codex Cross-Model Verification (aggregation)

**Codex-skip handler:** If `codex-flow` was not launched in Step A for any reason:
- Do NOT proceed to Steps F–H or write the review file.
- Surface: `⚠️ Codex cross-check was not run. Review is incomplete. Launching Codex now.`
- Run `codex-flow review planning/reviews/<feature>-review-request.md` with `run_in_background: true`.
- Wait for completion, then continue with Step E aggregation below.

Codex was launched in Step A (background Bash). Once it completes (you will be notified),
read its output:

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

After Step E, the working set contains:
1. Consensus findings (with corroboration tags where applicable)
2. Codex-only findings (routed to Step G for reverification)

The full report is assembled after Steps F–H complete.

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

If a design doc exists (passed inline below), read it. For each acceptance criterion listed, verify that at least one test explicitly covers it. Report any acceptance criterion with no corresponding test as a High finding titled "No test for acceptance criterion: <criterion text>".

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
6. Name/assertion alignment — enumerate EVERY test function by name. For each one: does the test name describe the same scenario and outcome that the assertions actually verify? A mismatch (e.g. name says "rollback sets rollbackDetected" but body never asserts error_code == "rollbackDetected") is a test correctness bug. Rate as High.
7. Per-function negative coverage — for every public function or method that has at least one test: verify at least one negative/failure test exists for each distinct failure mode (wrong input, null return, resource error, boundary violation). Safety invariants (e.g. "action must NOT fire when ID mismatches") require an explicit negative test asserting the action was NOT taken. Rate missing safety-invariant tests as High, other missing failure tests as Medium.

Rate each finding: Critical (no tests for public API), High (significant gap or safety-invariant violation), Medium (anti-pattern, missing edge case), Low (minor improvement).
Output a raw list: title, severity, description, location.
```

**Cross-aggregate its output** after both it and the Claude consensus (Steps B–D) are available:

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** test-coverage agent | Mark as **✓ Corroborated by test-coverage agent** |
| Claude consensus only | Include as-is |
| Test-coverage agent only | Include under **"Test-coverage findings"** (separate section) |

### Step G: Single-Finding Reverification

After Steps B–F complete, collect all findings that require reverification:
- Single-agent Claude findings **not** covered by the direct-inclusion exceptions in Step B
- Codex-only findings from Step E

If the set is empty, skip Step G entirely.

For each finding, launch **2 independent reviewer (opus) agents** in parallel with this focused prompt:

```
You are verifying a specific code review finding. Your ONLY job is to determine whether this finding is a genuine issue in the code shown. Do not report other findings.

Finding:
  Title: [title]
  Severity: [severity]
  Description: [description]
  Location: [file:line]

Relevant code (±20 lines of context around the cited location):
[code excerpt]

Is this a genuine issue? Answer YES or NO followed by one sentence of reasoning.
```

**Aggregation rule:**
- ≥1 of 2 verifiers answers YES → include in final report, marked **✓ Reverified**
- Both answer NO → discard

Run all reverification agents for all findings in a single parallel batch — do not serialize per finding.

**Note:** Step F (test-coverage agent) findings are not subject to Step G — they come from a dedicated specialized agent and are included directly in the Test-coverage findings section.

### Step H: Manual Passes (code review only — always required after Steps B–G)

After all agent and Codex outputs are aggregated, the **main reviewer** must manually complete both enumeration passes. These cannot be delegated to agents — they require deliberate cross-file auditing that agents perform inconsistently.

**1. Cross-Site Consistency Pass**
For every function/method signature, build command, interface definition, or configuration value modified by the diff: enumerate every site that references that contract (call sites, overrides, mocks, CI jobs, Makefile targets, config consumers) and verify they are consistent. Follow the full procedure in `review-checklist.md`. These findings are NOT filtered by the 2/3 consensus rule — any mismatch found here is included regardless of whether agents flagged it.

**2. Test Quality Pass completion check**
Verify the test-coverage agent (Step F) enumerated every test function touched by the diff by name. For any test function not enumerated by the agent, manually complete the per-test checks: assertion specificity, name/assertion alignment, falsifiability, bare sleeps.

Add all Step H findings to the final report under **"Manual pass findings"** (separate section after test-coverage findings).

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
- **Step 0 (write review request doc) must complete before Step A fires** — it is a prerequisite, not a Codex phase
- **Step A is a single message** containing all Agent calls + the background `codex-flow` Bash call — never split across messages
- Codex is invoked via `codex-flow review planning/reviews/<feature>-review-request.md` with `run_in_background: true` — never call `codex` directly
- The final report sections are: Consensus findings → Codex-only findings → Reverified findings (Step G) → Test-coverage findings (Step F) → Manual pass findings (Step H)
