# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

## How It Works

Three focus-differentiated reviewer agents evaluate the subject in parallel. The full pipeline is Steps 0–H:

- **Step 0:** Write Codex review-request doc before any agents launch
- **Step A:** 3 Claude reviewers (differentiated focus) + Codex (background) + test-coverage agent (Step F, code and MR reviews only) launch simultaneously
- **Steps B–D:** Claude consensus — findings need 2/3 agreement; non-exception single-agent findings route to Step G (code and MR reviews) or to the `## Single-Agent Findings` section (design reviews). Direct-inclusion exceptions (test-correctness → `## Test-coverage Findings`; cross-site → `## Manual Pass Findings`) apply in code/MR reviews only.
- **Step E:** Codex cross-aggregate — Codex-only findings route to Step G (code and MR reviews) or to the `## Codex-Only Findings` section (design reviews)
- **Step F:** Test-coverage agent (code and MR reviews only) — findings included directly, not filtered by consensus
- **Step G:** Single-finding adversarial reverification (code and MR reviews only — skipped for design reviews) — 2 agents try to *refute* each single-agent/Codex-only finding with full-file context; include only if **both** verifiers return `VERDICT: CONFIRMED`; any REFUTED discards; unparseable verdicts are retried once, then discarded with a warning
- **Step H:** Manual passes (code and MR reviews only) — Cross-Site Consistency Pass and Test Quality Pass completion check

## Protocol Steps

### Step 0: Prepare Codex review request (before launching any agents)

**This step must complete before Step A.** Write the Codex review request document from the
template at `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md` and save it to
`planning/reviews/<feature>-review-request.md`. Fill in all fields from the current review
context (repository, branch, scope, requirements, evidence, review focus). The `Output File`
field must point to `planning/reviews/<feature>-codex-review.md`.

**⚠️ Heading format is validated literally by codex-flow.** The first line of the document MUST be:
```
# Review Request — <name>
```
Any variation (`# Code Review Request:`, `# Review:`, `# Code Review —`, etc.) causes an immediate rejection with "Review request must start with a Review Request heading." Copy line 1 of the template verbatim and substitute only `<Feature / Fix Name>`.

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
- For **code and MR reviews only:** one test-coverage Agent call (Step F) — skip for design reviews

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

Do not discard single-agent findings — route them per review type (see "Non-exception single-agent findings by review type" below): Step G for code/MR reviews, or the `## Single-Agent Findings` section for design reviews.

**Exception — single-agent findings that bypass Step G and go directly to the final report:**
- **Test-correctness findings** (name/assertion alignment, vacuous assertions, missing negative paths, bare sleeps): include directly. These are observable facts; a reverifier would confirm the same fact. Routing: code/MR reviews → `## Test-coverage Findings` section (merged alongside Step F output). Not applicable to design reviews (no tests to evaluate).
- **Cross-site consistency findings** (build flag mismatches across Makefile/CI jobs, function signature mismatches across declarations/overrides/mocks, config value mismatches across consumers): include directly. These are enumerable facts, not judgment calls. Routing: code/MR reviews → `## Manual Pass Findings` section (merged alongside Step H output). Not applicable to design reviews (no code artifacts to cross-check).

Both exception categories are code/MR-review-only by construction — their triggers presuppose code or tests that a design doc does not contain.

**Non-exception single-agent findings by review type:**
- Code/MR reviews → **Step G** reverification (adversarial)
- Design reviews → included directly in the design review's `## Single-Agent Findings` section (no reverification — Step G is code/MR-only)

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
| Codex only | Add to the intermediate **Codex-only working set** for routing per review type (see below) |

Two findings refer to the same issue if they describe the same root cause at the same code location (fuzzy match on concept, not wording).

**Note on naming:** "Codex-only working set" is an intermediate bucket used during aggregation — it is NOT a final report section. For code/MR reviews it feeds Step G; for design reviews it feeds the `## Codex-Only Findings` section of the design report. Do not conflate this working-set label with the final section name.

After Step E, the working set contains:
1. Consensus findings (with corroboration tags where applicable)
2. Codex-only working set — routed per review type:
   - Code/MR reviews → Step G reverification (adversarial); survivors land in `## Reverified Findings`
   - Design reviews → included directly in the `## Codex-Only Findings` section (no reverification — Step G is code/MR-only)

For design reviews, Step E is the last aggregation step: after this, the report is assembled from consensus findings, Codex-only findings, and single-agent findings (per Step B non-exception routing). Steps F, G, and H are skipped for design reviews.

For code/MR reviews, the full report is assembled after Steps F–H complete.

### Step F: Test-Coverage and Pitfalls Agent (code and MR reviews only — skip for design reviews)

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
7. Per-function negative coverage — for every public function or method that has at least one test: verify at least one negative/failure test exists for each distinct failure mode. Treat a mode as distinct when it reaches a different validation rule, guard branch, dependency failure, invariant, or recovery behavior; do not invent null, wrong-type, or other categories the language or boundary cannot represent. Safety invariants (e.g. "action must NOT fire when ID mismatches") require an explicit negative test asserting the action was NOT taken. Rate missing safety-invariant tests as High, other missing failure tests as Medium.

Rate each finding: Critical (no tests for public API), High (significant gap or safety-invariant violation), Medium (anti-pattern, missing edge case), Low (minor improvement).
Output a raw list: title, severity, description, location.
```

**Cross-aggregate its output** after both it and the Claude consensus (Steps B–D) are available:

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** test-coverage agent | Mark as **✓ Corroborated by test-coverage agent** |
| Claude consensus only | Include as-is |
| Test-coverage agent only | Include under **`## Test-coverage Findings`** (separate section — matches the SKILL.md template heading exactly) |

### Step G: Single-Finding Adversarial Reverification (code and MR reviews only)

**Applicability.** Step G runs only for `/review-code` and `/review-mr`. It does **not** run for `/review-design`. Design-review routing for single-agent Claude findings and Codex-only findings is handled at Step B and Step E respectively — see those sections. This section describes code/MR-review behavior only.

After Steps B–F complete, collect all findings that require reverification:
- Single-agent Claude findings **not** covered by the direct-inclusion exceptions in Step B
- Codex-only findings from Step E

If the set is empty, skip Step G entirely.

**Why adversarial:** A permissive Step G would combine three permissive choices — a neutral "is this a real issue?" framing, a narrow code excerpt around the location, and 1-of-2 approval — and the three together would let plausible-sounding findings survive reverification. This step deliberately tightens all three simultaneously: skeptical framing, full-file context (read via the Read tool), and 2-of-2 CONFIRMED with default-to-refute. The tradeoff is explicit — a higher false-negative rate (some real single-agent findings will be discarded) in exchange for a lower false-positive rate.

**On Codex-only findings:** Codex-only findings route through Step G with the same 2-of-2 CONFIRMED rule. This is deliberately symmetric with single-agent Claude findings, not an oversight: Codex-only findings without Claude corroboration are the exact category most prone to model-specific hallucination, and the adversarial pass is where we filter those. The cost is that Claude verifiers can veto real Codex signal; accept this rather than adding a separate looser track.

For each finding, launch **2 independent reviewer (opus) agents** in parallel with the prompt below. The launching context (the main conversation running this protocol) MUST supply an absolute `Repository:` path — the reviewer agent has no reliable CWD inheritance, and relative `file:line` locations cannot be resolved without it.

**How the main conversation obtains Repository:** Unified path for both `/review-code` and `/review-mr`: reuse the `Repository:` value already written into the Step 0 review-request document (`planning/reviews/<feature>-review-request.md`). If Step 0 was skipped, or the value is missing/empty, fall back to running `pwd` in the main conversation's shell. If both fail, do NOT launch Step G verifier agents — surface a warning to the user (`⚠️ Step G cannot run: Repository path unavailable. Findings requiring reverification will be skipped.`) and treat all Step G-eligible findings as discarded-with-warning under rule 4 semantics. Do not silently REFUTE-and-drop.

```
You are the skeptic verifying a specific code review finding. Your job is to REFUTE this finding — find evidence that it is NOT a genuine issue.

Finding:
  Title: [title]
  Severity: [severity]
  Description: [description]
  Location: [file:line]      # may be relative — resolve against Repository below
  Repository: [absolute path to repo root]

Read the file at Location in full using the Read tool (resolve relative paths against Repository). Then read up to 3 additional files that the finding's description names explicitly, ranked by proximity to the described failure (prefer: the interface/header for a changed source file, a specific caller mentioned in the description, upstream code that sets an invariant the finding claims is violated, error-handling code the finding claims is missing). Do not read speculative files — only files the description itself names or unambiguously points to. Total read budget: the Location file plus at most 3 named dependencies.

Actively look for evidence that refutes the finding:
- Is the described precondition actually reachable in practice?
- Does surrounding code (invariants set upstream, error handling elsewhere, the calling contract) already prevent the described failure?
- Is there a guard, check, type constraint, or convention that makes the described bug impossible?
- Does the description misread what the code actually does?

**Output format — strict.** The FIRST LINE of your response MUST be exactly one of these two strings, with no trailing text on that line:
  VERDICT: CONFIRMED
  VERDICT: REFUTED
Put ALL reasoning on line 2 and after (one to two sentences citing the specific code you read). Do not append reasoning to the verdict line. If you cannot definitively confirm the finding is real after reading the relevant files, or if the file at Location cannot be read for any reason, output `VERDICT: REFUTED` on line 1.
```

**Aggregation rule.** Parse only the first line of each verifier response. Match case-sensitively against `^VERDICT: (CONFIRMED|REFUTED)$`. Anything else — hedges, prose without a verdict line, missing response, agent crash — counts as `Unparseable`.

Evaluate the outcome using the ordered rules below. Rules 1 and 2 gate the Unparseable retry loop and must resolve first — they may explicitly route to rule 4 regardless of what other verdicts are present in the retried pair. Rules 3–5 apply only after rules 1 and 2 have completed (i.e., only to a fully-parseable retried pair, or when neither original verdict was Unparseable). Within rules 3–5, first match wins.

1. **Both verifiers `Unparseable`** → retry both in parallel. If retry still yields any `Unparseable`, fall through to rule 4 with the retried verdicts. Otherwise, re-evaluate against rules 3–5 with the retried verdicts.
2. **Exactly one verifier `Unparseable`** → retry that verifier once. Substitute the retry verdict. If the retry still yields `Unparseable`, fall through to rule 4 with the new pair. Otherwise, re-evaluate against rules 3–5 with the new pair.
3. **Any `REFUTED`** (either or both verifiers) → **Discard**.
4. **Any `Unparseable` remains after retry** → **Discard** and emit warning:
   ```
   ⚠️ Step G verifier failed twice for finding: <title>
       Location: <file:line>
       Action: discarded (unable to reverify).
   ```
5. **Both `VERDICT: CONFIRMED`** → **Include** as ✓ Reverified.

**Deliberate asymmetry.** A single REFUTED discards; a single CONFIRMED does not include. This is the mechanism that filters plausible-but-wrong findings at the cost of dropping some correct ones. Do not "fix" it — the asymmetry is the intervention.

**Warning behavior.** Findings discarded via rule 4 (verifier failed twice) are logged as warnings to the main conversation so the user is aware; the finding is *not* held in some intermediate state. Discard-with-warning is chosen over "hold for manual triage" because none of the calling commands (`/review-mr`, `/review-code`) have a report section or workflow step for held items — held findings would silently disappear anyway. If a warning appears and the user believes the finding is real, they can add it manually.

Run all reverification agents for all findings in a single parallel batch — do not serialize per finding. **Step G is a discrete blocking phase — Step H does not start until every finding's Step G outcome is resolved (Include, Discard, or Discard-with-warning).**

**Note:** Step F (test-coverage agent) findings are not subject to Step G — they come from a dedicated specialized agent and are included directly in the `## Test-coverage Findings` section.

**Reporting.** Findings that survive Step G are prefixed with `[Reverified]` in their description when written to any downstream output. This prefix is machine-recognizable and required, not optional — the previous soft "(reverified) note" convention was ambiguous and drifted.

### Step H: Manual Passes (code and MR reviews only — always required after Steps B–G)

After all agent and Codex outputs are aggregated, the **main reviewer** must manually complete both enumeration passes. These cannot be delegated to agents — they require deliberate cross-file auditing that agents perform inconsistently.

**1. Cross-Site Consistency Pass**
For every function/method signature, build command, interface definition, or configuration value modified by the diff: enumerate every site that references that contract (call sites, overrides, mocks, CI jobs, Makefile targets, config consumers) and verify they are consistent. Follow the full procedure in `review-checklist.md`. These findings are NOT filtered by the 2/3 consensus rule — any mismatch found here is included regardless of whether agents flagged it.

**2. Test Quality Pass completion check**
Verify the test-coverage agent (Step F) enumerated every test function touched by the diff by name. For any test function not enumerated by the agent, manually complete the per-test checks: assertion specificity, name/assertion alignment, falsifiability, bare sleeps.

Add all Step H findings to the final report under **`## Manual Pass Findings`** (separate section after `## Test-coverage Findings` — matches the SKILL.md template heading exactly).

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
- Final report sections by review type:
  - **Code and MR reviews:** `## Findings` (consensus) → `## Reverified Findings` (Step G — holds surviving single-agent Claude and Codex-only findings) → `## Library Reuse Findings` → `## Common Library Promotion Candidates` (when present) → `## Test-coverage Findings` (Step F) → `## Manual Pass Findings` (Step H). See `~/.claude/skills/workflows/review-output-format/SKILL.md` for the authoritative section list.
  - **Design reviews:** Consensus findings → Codex-only findings → Single-agent findings. See `~/.claude/commands/review-design.md` for the authoritative template.
  - Note: code/MR reviews do not emit a separate `## Codex-Only Findings` section — Codex-only findings route through Step G and land in `## Reverified Findings` on survival, discarded otherwise.
