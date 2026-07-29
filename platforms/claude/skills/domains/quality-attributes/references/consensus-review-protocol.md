# Consensus Review Protocol

A shared multi-agent review mechanism used by all `/review*` commands.

> **Path convention:** All paths in this protocol are supplied by the invoking command per its own path convention (issue-scoped or MR-scoped). Do not inline any hardcoded `planning/reviews/` string in this protocol — use `<review-request-path>` and `<codex-output-path>` as placeholders for the paths the calling command provides. If the invoking command has not declared these paths, default to `<issue-folder>/codex-review-request.md` (input) and `<issue-folder>/codex-review.md` (output).

## How It Works

Three focus-differentiated reviewer agents evaluate the subject in parallel. The full pipeline is Steps 0–H:

- **Step 0:** Write Codex review-request doc before any agents launch
- **Step A:** 3 Claude reviewers (differentiated focus) + Codex (background) + test-coverage agent (Step F, code, fix, and MR reviews only) launch simultaneously
- **Steps B–D:** Claude consensus — findings need 2/3 agreement; non-exception single-agent findings route to Step G in every review type. Direct-inclusion exceptions (test-correctness → `## Test-coverage Findings`; cross-site → `## Manual Pass Findings`) apply in code, fix, and MR reviews only.
- **Step E:** Codex cross-aggregate — Codex-only findings route to Step G in every review type
- **Step F:** Test-coverage agent (code, fix, and MR reviews only) — findings included directly, not filtered by consensus
- **Step G:** Single-finding adversarial reverification (all review types; code and design verifier variants) — 2 agents try to *refute* each single-agent/Codex-only finding with full-file context; include only if **both** verifiers return `VERDICT: CONFIRMED`; any REFUTED discards; unparseable verdicts are retried once, then discarded with a warning
- **Step H:** Manual passes (code, fix, and MR reviews only) — Cross-Site Consistency Pass and Test Quality Pass completion check

## Protocol Steps

### Step 0: Prepare Codex review request (before launching any agents)

**This step must complete before Step A.** Write the Codex review request document from the
template at `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md` and save it to
`<review-request-path>` (supplied by the invoking command). Fill in all fields from the current review
context (repository, branch, scope, requirements, observed-failure ledger, evidence, review focus).
The ledger section is validated by codex-flow and must not be left as the template placeholder:
paste `<issue-folder>/observed-failures.md`, or state `No ledger exists for this work.` A design
review has no diff and therefore never has a ledger — always the latter. The `Output File`
field must point to `<codex-output-path>` (supplied by the invoking command).

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
  codex-flow review <review-request-path>
  ```
  **Invoke it bare — do not append anything.** A trailing `; echo "exit=$?"`, `&& echo done`, or any other command makes the shell's exit status that of the *appended* command, so a failed `codex-flow` reports success in the completion notification. The notification is faithful; wrapping it is what lies. If you want the exit code, read it from the notification rather than instrumenting for it.

- For **code, fix, and MR reviews only:** one test-coverage Agent call (Step F) — skip for design reviews

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

Do not discard single-agent findings — route them to Step G for adversarial reverification (see "Non-exception single-agent findings by review type" below). This applies to every review type; only the verifier prompt differs.

**Exception — single-agent findings that bypass Step G and go directly to the final report:**
- **Test-correctness findings** (name/assertion alignment, vacuous assertions, missing negative paths, bare sleeps): include directly. These are observable facts; a reverifier would confirm the same fact. Routing: code/fix/MR reviews → `## Test-coverage Findings` section (merged alongside Step F output). Not applicable to design reviews (no tests to evaluate).
- **Observed-failure regression findings** (missing ledger entry, unresolved entry, missing regression test, symptom-mismatched test, invalid waiver): include directly. These are enumerable facts about the diff and the ledger, not judgment calls about the code — a Step G reverifier reading only the changed source would find nothing wrong with the code itself and default to REFUTED, discarding a correct finding. Routing: code/fix/MR reviews → `## Test-coverage Findings` section. Not applicable to design reviews.
- **Design structural-gate findings** (a section the design template or the review's flag list requires is absent, unnamed, or left as a template placeholder — On-Device Verification and its entry point, a concept named but never defined, a stated non-goal that is missing): include directly. These are enumerable facts about the document, settled by looking, and the flag rules already decided they are required — so the confirmation bar's "is it required for correctness?" test does not apply and would systematically discard them. Eight of the twelve design flag categories are absence claims, and an absence claim has no textual anchor to confirm against, so default-to-refute resolves against every one of them. Same rationale as the two exceptions above. Routing: design reviews → `## Findings` at the severity the flag rule prescribes.
- **Cross-site consistency findings** (build flag mismatches across Makefile/CI jobs, function signature mismatches across declarations/overrides/mocks, config value mismatches across consumers): include directly. These are enumerable facts, not judgment calls. Routing: code/fix/MR reviews → `## Manual Pass Findings` section (merged alongside Step H output). Not applicable to design reviews (no code artifacts to cross-check).

All three exception categories are code/fix/MR-review-only by construction — their triggers presuppose code or tests that a design doc does not contain.

**Non-exception single-agent findings by review type:**
- Code, fix, and MR reviews → **Step G** reverification (adversarial, code variant)
- Design reviews → **Step G** reverification (adversarial, design variant); survivors land in `## Reverified Findings`

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
- Run `codex-flow review <review-request-path>` with `run_in_background: true`.
- Wait for completion, then continue with Step E aggregation below.

**Codex-failure handler:** Launching `codex-flow` is not the same as Codex running. It is launched with `run_in_background: true`, so the Bash tool reports success for the *launch* — a request that `codex-flow` then rejects produces a non-zero exit, a message on stderr, and **no output file at all**. Read the completion notification's exit code; do not treat launch success as run success.

Before aggregating, confirm the output exists and is non-empty:

```bash
test -s <codex-output-path> && echo "codex output present" || echo "CODEX FAILED — no output"
```

If the output is missing or empty, **stop**. Do not proceed to Steps F–H, do not write the review file, and do not aggregate three agents as though this were a 3+1 consensus — silently downgrading the protocol is the failure mode this handler exists to prevent. Surface:

```
⚠️  Codex cross-check failed — review is incomplete
    exit: <exit code from the background Bash notification>
    stderr: <the error line codex-flow printed>
    recovery: fix the review request and re-run `codex-flow review <review-request-path>`
```

The most common cause is a rejected review request: `codex-flow` validates required sections and refuses the whole run if one is missing or left as a template placeholder. `Observed-Failure Ledger` is the newest such section — a request written from a stale template or from memory will lack it. Fix the request document, then re-run. Annotating `Codex: ✗ not run` and continuing is **not** an acceptable resolution for any review type; that annotation exists for the case where Codex is genuinely unavailable, not for a request you can repair. Design reviews are the likeliest to hit this — they have no diff, so their request needs the explicit `No ledger exists for this work.` line.

Once Codex has completed successfully, read its output:

```bash
cat <codex-output-path>
```

**Cross-aggregate the results:**

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** Codex | Mark as **✓ Corroborated by Codex** |
| Claude consensus only | Include as-is (already filtered by 2/3) |
| Codex only | Add to the intermediate **Codex-only working set** for routing per review type (see below) |

Two findings refer to the same issue if they describe the same root cause at the same code location (fuzzy match on concept, not wording).

**Note on naming:** "Codex-only working set" is an intermediate bucket used during aggregation — it is NOT a final report section. In every review type it feeds Step G, and survivors land in `## Reverified Findings`. Do not conflate this working-set label with the final section name.

After Step E, the working set contains:
1. Consensus findings (with corroboration tags where applicable)
2. Codex-only working set — routed per review type:
   - Code, fix, and MR reviews → Step G reverification (adversarial); survivors land in `## Reverified Findings`. **Exception:** Codex-only observed-failure regression findings (missing ledger entry, unresolved entry, missing or symptom-mismatched regression test, invalid waiver) bypass Step G and go directly to `## Test-coverage Findings` — same rationale as the Step B exception: a reverifier reading only the changed source finds nothing wrong with the code and defaults to REFUTED, discarding a correct finding.
   - Design reviews → **Step G** reverification (adversarial, design variant); survivors land in `## Reverified Findings`

For design reviews, Step G follows Step E: single-agent and Codex-only findings are adversarially reverified with the design variant, and the report is assembled from consensus findings plus Step G survivors. Steps F and H remain skipped for design reviews — there are no tests to evaluate and no changed call sites to cross-check.

For code/fix/MR reviews, the full report is assembled after Steps F–H complete.

### Step F: Test-Coverage and Pitfalls Agent (code, fix, and MR reviews only — skip for design reviews)

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
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md for the Test Quality Pass — item 8 below depends on its Step 3, so read it even if a copy was also passed inline.

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

8. Observed-failure regression coverage — run **Test Quality Pass Step 3 of the review checklist provided inline above**, in full. It carries the criteria, the severity table, and the review-type carve-outs; use it verbatim rather than improvising severities. Two points it depends on you getting right:
   - **An absent ledger is not an exemption.** In a code or fix review, "no ledger exists" is itself the defect condition — row 1 of Step 3's table, High — whenever the diff shows evidence of an observed failure (a bug-ticket reference, a `fix:`/`hotfix` branch or commit, a CI-config or script change following a red pipeline, an analysis doc describing an incident). Only in an **MR review** does an absent ledger mean the check does not apply, because external MRs have no issue folder.
   - **If a ledger was passed to you inline, evaluate every entry.** A `covered`, `waived`, or `out-of-scope` entry is resolved; `open` is not.

Rate each finding: Critical (no tests for public API), High (significant gap or safety-invariant violation), Medium (anti-pattern, missing edge case), Low (minor improvement). For observed-failure findings use item 8's table instead of this line — it carries Medium rows this scale does not.
Output a raw list: title, severity, description, location.
```

**Cross-aggregate its output** after both it and the Claude consensus (Steps B–D) are available:

| Finding source | Action |
|----------------|--------|
| In Claude consensus **and** test-coverage agent | Mark as **✓ Corroborated by test-coverage agent** |
| Claude consensus only | Include as-is |
| Test-coverage agent only | Include under **`## Test-coverage Findings`** (separate section — matches the SKILL.md template heading exactly) |

### Step G: Single-Finding Adversarial Reverification (all review types)

**Applicability.** Step G runs for `/review-code`, `/review-fix`, `/review-mr`, and `/review-design`. It does not run for `/review-article`, which uses its own aggregation and knowingly retains an unreverified Codex-only tier.

Collect all findings that require reverification once Steps B–E complete (and Step F where it runs):
- Single-agent Claude findings **not** covered by the direct-inclusion exceptions in Step B
- Codex-only findings from Step E

If the set is empty, skip Step G entirely.

**Why adversarial:** A permissive Step G would combine three permissive choices — a neutral "is this a real issue?" framing, a narrow excerpt around the location, and 1-of-2 approval — and together they would let plausible-sounding findings survive. This step tightens all three at once: skeptical framing, full context, and 2-of-2 CONFIRMED with default-to-refute. The tradeoff is explicit — a higher false-negative rate in exchange for a lower false-positive rate. That trade is only acceptable because the direct-inclusion exceptions in Step B keep **enumerable facts** out of Step G entirely; a finding that is decidably true by inspection must never face a default-to-refute filter.

**On Codex-only findings:** they route through Step G on the same 2-of-2 rule, deliberately symmetric with single-agent Claude findings. Codex-only findings without Claude corroboration are the category most prone to model-specific hallucination. The cost is that Claude verifiers can veto real Codex signal; accept it rather than adding a looser track.

#### Inputs by review type

The launching context MUST supply these, and every path MUST be **absolute** — verifier agents have no reliable CWD inheritance. A relative path that fails to resolve produces two failed reads, two REFUTED verdicts, and a silent total discard under rule 3, which emits no warning at all.

| Review type | `Location` means | Paths to supply | Read budget |
|---|---|---|---|
| code, fix, MR | `file:line` in the diff | `Repository:` | the Location file, plus ≤3 files the description names |
| design | a section of the design doc | `Design doc:`, `Analysis doc:` (or `none`), `Repository:` | the design doc in full, the analysis doc, plus project docs the design cites and existence checks under Repository |

**Obtaining the paths.** Reuse the `Repository:` value from the Step 0 review-request document; otherwise run `pwd` in the main conversation's shell. For design reviews, resolve `design.md` and its sibling `analysis.md` to absolute paths, and pass `analysis.md` whenever the file exists — it carries `## Ticket Constraints` and `## Clarifications`, which are refutation evidence the verifier cannot reach otherwise.

**If any required path cannot be resolved, do NOT launch verifiers.** Surface `⚠️ Step G cannot run: <path> unavailable. Findings requiring reverification will be skipped.` and treat every Step G-eligible finding as discarded-with-warning under rule 4. Do not silently REFUTE-and-drop.

#### Verifier prompt

Assemble from the shared skeleton plus the refutation criteria for the review type. The skeleton — role line, `Finding:` block, confirmation bar, output contract — is written once here and is identical for every review type. Only the criteria block differs. Edit the skeleton once; do not fork it per type.

```
You are the skeptic verifying a specific [code review | design review] finding. Your job is to REFUTE this finding — find evidence that it is NOT a genuine issue.

Finding:
  Title: [title]
  Severity: [severity]
  Description: [description]
  Location: [file:line, or design-doc section]
  Repository: [absolute path to repo root]
  [design only] Design doc: [absolute path]   Analysis doc: [absolute path, or "none"]

[REFUTATION CRITERIA BLOCK — per review type, below]

**Confirmation bar.** A finding is CONFIRMED if it identifies something the subject genuinely gets wrong, or genuinely fails to address. Speculative elaboration ("it could also discuss X") is not confirmed unless X is required for correctness or implementability.

**This bar does not apply to enumerable facts.** If the finding asserts that a specifically-required element is absent, malformed, or left as a template placeholder — anything settled by looking — the only question is whether the stated condition holds. Do not weigh whether the missing element is "required for correctness": a rule already decided that. Confirm it if the condition holds.

**Output format — strict.** The FIRST LINE of your response MUST be exactly one of these two strings, with no trailing text on that line:
  VERDICT: CONFIRMED
  VERDICT: REFUTED
Put ALL reasoning on line 2 and after (one to two sentences citing what you read). Do not append reasoning to the verdict line. If you cannot definitively confirm the finding is real after reading the relevant material, output `VERDICT: REFUTED` on line 1. If a file you were told to read cannot be read at all, do NOT output a verdict — respond `READ FAILED: <path>` so the launching context routes it to rule 4 instead of counting an infrastructure failure as a refutation.
```

**Refutation criteria — code, fix, and MR reviews:**

```
Read the file at Location in full using the Read tool (resolve relative paths against Repository). Then read up to 3 additional files the description names explicitly, ranked by proximity to the described failure (prefer: the interface/header for a changed source file, a caller named in the description, upstream code setting an invariant the finding claims is violated, error-handling code the finding claims is missing). Do not read speculative files.

Actively look for evidence that refutes the finding:
- Is the described precondition actually reachable in practice?
- Does surrounding code (invariants set upstream, error handling elsewhere, the calling contract) already prevent the described failure?
- Is there a guard, check, type constraint, or convention that makes the described bug impossible?
- Does the description misread what the code actually does?
```

**Refutation criteria — design reviews:**

```
Read the design doc in full using the Read tool, then the analysis doc if one is given. You may also read project documentation the design cites by name, and check whether a named entry point, script, or artifact exists under Repository. Do not review source code for implementation quality — this is a review of a proposed design, not of an implementation.

Actively look for evidence that refutes the finding:
- Does another section of the design already address this? Design docs are long; a finding raised against section 5 is frequently answered in section 6 or in an Open Questions entry.
- Does the finding misread what the design proposes?
- Is the concern out of scope for a reason traceable to an authority *outside the design itself* — an ACCEPTED or REVISED entry under `## Ticket Constraints` in the analysis doc, a recorded `## Clarifications` answer, or an explicit stated requirement? A scope exclusion the design merely asserts about itself is NOT refuting evidence: the same agent that writes the design can widen its own Scope section, and accepting that would let a design excuse itself from review.
- Is the concern speculative — does it depend on a scenario, scale, or failure mode the design excludes on stated authority?
- Is it a restatement of a trade-off the design already acknowledges and accepts with rationale?

Apply the Design-Level Constraint block supplied with this prompt — the same scope rules the primary reviewers used. A finding about implementation-level detail excluded by its do-NOT-flag list is REFUTED as out of scope. A finding raised against a DROPPED ticket constraint is REFUTED per the Ticket Constraint Guardrail. Conversely, a finding that a flag-list element is absent, unnamed, or left as a template placeholder is an enumerable fact — see the confirmation bar, and confirm it.
```

**The launching context MUST paste the Design-Level Constraint block and the Ticket Constraint Guardrail from `~/.claude/commands/review-design.md` into the design verifier prompt**, exactly as it does for the three primary reviewers. Without them the verifier applies different scope rules than the reviewers whose findings it adjudicates.

#### Cost control

The code variant reads a different file per finding, so per-finding fan-out buys real context coverage. The design variant reads the **same** document for every finding, so per-finding fan-out multiplies a constant cost by N and buys nothing.

- **Code, fix, MR:** 2 verifiers per finding, all findings in a single parallel batch.
- **Design:** **one pair of verifiers for the whole set** — they adjudicate every eligible finding in one pass over the document and emit one verdict line per finding, in the form `VERDICT: <ID> CONFIRMED` or `VERDICT: <ID> REFUTED`. Cost falls from 2N document reads to 2. Apply the aggregation rules below per finding ID.
- **Cap:** never launch more than 20 verifier agents concurrently; chunk into successive batches beyond that. An unbounded fan-out degrades into throttling, which presents as missing responses, which rule 4 converts into mass discard-with-warning — at exactly the moment filtering matters most.

**Aggregation rule.** For code, fix, and MR reviews parse only the first line of each verifier response, matching case-sensitively against `^VERDICT: (CONFIRMED|REFUTED)$`. For the batched design form, parse each `^VERDICT: <ID> (CONFIRMED|REFUTED)$` line and evaluate the rules below per finding ID; an eligible ID with no verdict line counts as `Unparseable` for that finding only. A `READ FAILED:` response counts as `Unparseable` for every finding it covers — an infrastructure failure must never be recorded as a refutation. Anything else — hedges, prose without a verdict line, missing response, agent crash — counts as `Unparseable`.

Evaluate the outcome using the ordered rules below. Rules 1 and 2 gate the Unparseable retry loop and must resolve first — they may explicitly route to rule 4 regardless of what other verdicts are present in the retried pair. Rules 3–5 apply only after rules 1 and 2 have completed (i.e., only to a fully-parseable retried pair, or when neither original verdict was Unparseable). Within rules 3–5, first match wins.

1. **Both verifiers `Unparseable`** → retry both in parallel. If retry still yields any `Unparseable`, fall through to rule 4 with the retried verdicts. Otherwise, re-evaluate against rules 3–5 with the retried verdicts.
2. **Exactly one verifier `Unparseable`** → retry that verifier once. Substitute the retry verdict. If the retry still yields `Unparseable`, fall through to rule 4 with the new pair. Otherwise, re-evaluate against rules 3–5 with the new pair.
3. **Any `REFUTED`** (either or both verifiers) → **Discard**.
4. **Any `Unparseable` remains after retry** → **Discard** and emit warning:
   ```
   ⚠️ Step G verifier failed twice for finding: <title>
       Location: <file:line, or design-doc section>
       Action: discarded (unable to reverify).
   ```
5. **Both `VERDICT: CONFIRMED`** → **Include** as ✓ Reverified.

**Deliberate asymmetry.** A single REFUTED discards; a single CONFIRMED does not include. This is the mechanism that filters plausible-but-wrong findings at the cost of dropping some correct ones. Do not "fix" it — the asymmetry is the intervention.

**Warning behavior.** Findings discarded via rule 4 (verifier failed twice) are logged as warnings to the main conversation so the user is aware; the finding is *not* held in some intermediate state. Discard-with-warning is chosen over "hold for manual triage" because none of the calling commands (`/review-mr`, `/review-code`) have a report section or workflow step for held items — held findings would silently disappear anyway. If a warning appears and the user believes the finding is real, they can add it manually.

Run all reverification agents for all findings in a single parallel batch — do not serialize per finding. **Step G is a discrete blocking phase — Step H does not start until every finding's Step G outcome is resolved (Include, Discard, or Discard-with-warning).**

**Note:** Step F (test-coverage agent) findings are not subject to Step G — they come from a dedicated specialized agent and are included directly in the `## Test-coverage Findings` section.

**Reporting.** Findings that survive Step G are prefixed with `[Reverified]` in their description when written to any downstream output. This prefix is machine-recognizable and required, not optional — the previous soft "(reverified) note" convention was ambiguous and drifted.

### Step H: Manual Passes (code, fix, and MR reviews only — always required after Steps B–G)

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
- Codex is invoked via `codex-flow review <review-request-path>` with `run_in_background: true` — never call `codex` directly
- Final report sections by review type:
  - **Code, fix, and MR reviews:** `## Findings` (consensus) → `## Reverified Findings` (Step G — holds surviving single-agent Claude and Codex-only findings) → `## Library Reuse Findings` → `## Common Library Promotion Candidates` (when present) → `## Test-coverage Findings` (Step F) → `## Manual Pass Findings` (Step H). See `~/.claude/skills/workflows/review-output-format/SKILL.md` for the authoritative section list.
  - **Design reviews:** Consensus findings → `## Reverified Findings` (Step G survivors). See `~/.claude/commands/review-design.md` for the authoritative template.
  - Note: no review type *covered by this protocol* (code, fix, MR, design) emits a separate `## Codex-Only Findings` section — Codex-only findings route through Step G and land in `## Reverified Findings` on survival, discarded otherwise. `/review-article` runs its own aggregation and does retain such a section.
