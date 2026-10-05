---
name: research
description: Run research phase using architecture-research-planner agent
---

# Research Command

Investigate existing codebase patterns and architecture using the architecture-research-planner agent.

## Agent

**architecture-research-planner** (opus model)

## Skills Required

- languages/* (language-specific patterns)
- domains/architecture (architecture patterns)

## Actions

0. Read workflow and domain skills to ensure phase context:
   ```
   Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
   Read ~/.claude/skills/domains/architecture/SKILL.md
   ```

1. Run one `search docs` query before writing `analysis.md`, built from the issue title and the distinctive nouns of the request — never the raw ticket text pasted verbatim:
   ```bash
   projctl search docs "<query>" [--related]
   ```
   Record the query string as run, the `--related` flag state, and the outcome — these three lines open the `## Prior Context` section described under Output below.

   **One query is mandatory here; a second, narrower one is permitted during Action 6** when the first missed the AC or fit question being graded. A second run is a lookup, not a record: cite it inline in the verdict it supports (`search docs "<query>" → <path> → <heading>`) and **never paste it into `## Prior Context`**, which holds the Action 1 run alone — its three opening lines describe one run, and a second pasted there makes the `N of M shown` disclosure unreadable.
**Brief the agent on the AC grading before spawning it.** Actions 2–4 below are the agent's investigation, and the verdicts are produced inside it — so the ticket's AC list and the verdict table from `## Acceptance Criteria Assessment` go into its launch prompt. Briefing it afterwards buys a second agent round, or grading in the main conversation with no codebase context, which is where an uncited `ALREADY MET` comes from.

2. Investigate existing codebase patterns
3. Understand current architecture
4. Identify integration points and dependencies
5. Ask clarifying questions if requirements are unclear
6. Grade each acceptance criterion and the issue's fit with the project, per `## Acceptance Criteria Assessment` below — the agent wrote the verdicts during Actions 2–4; this step collects the user's decisions in the main conversation.

## Output

**File:** `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md`

**Contains:**
- Codebase analysis
- Architecture diagrams (Mermaid)
- Research findings
- Integration points
- Dependency analysis
- A `## Prior Context` section, holding the Action 1 `search docs` run
- A `## Project Fit` section — always, per `## Acceptance Criteria Assessment` → `### Project fit` below
- An `## Acceptance Criteria Assessment` section **when the ticket text states acceptance criteria**; absent otherwise, with the reason on the `progress_line` rather than an empty section

**`## Prior Context`:** three lines, then a locator table's rows, nothing else. **First line:** the query string verbatim. **Second line:** the `--related` flag state. **Third line:** `N of M shown` — `M` is the run's own reported matched-unit total, never a count of the rows this section actually pastes, since a silently truncated read must not read as full coverage. `PRIOR_CONTEXT_ROWS` is **40** — `research.md` owns this value, and `review-mr.md` is its one other consuming site. Paste no more than that many rows.

What gets pasted is the locator table's rows alone: its header row, its alignment row, and its data rows. `search docs` also emits a `## Roadmap` block and a `## Prior decisions` heading ahead of the table, plus a footer. **Dropped:** `## Roadmap`, `## Prior decisions`, and the footer are dropped, because pasting either heading closes this section early and everything after it escapes `doc-metrics`'s skip.

**Gate:** reduction runs only when the header row names the five declared columns, in order — `score`, `tier`, `repo`, `path`, `heading`. Any other shape (an older `projctl` not yet carrying this format) takes the zero-row path below rather than pasting a shape the reduction does not recognize.

A run that exits non-zero, or matches zero sections, still produces the section: the query and flag-state lines are written as usual, and the third line records the exit status or `0 of 0` in place of a row count. Omitting the section entirely is indistinguishable from a step that never ran.

**This section is parsed by a test.** `tests/verify-config-consistency.sh` extracts `## Output` via `extract-section` and asserts, sentence by sentence, the `**Third line:**` disclosure, the `**Dropped:**` heading list, the `**Gate:**` column list, and the `PRIOR_CONTEXT_ROWS` value against `review-mr.md`'s copy. Reword a bold lead-in or move a token out of its sentence without re-running that suite and the drift is silent.

**Citation form:** every code reference is **file + symbol** (`` `src/pipeline/pipeline.cc` `` → `` `process_frame()` ``), or a quoted distinctive token where no symbol exists. A line number is valid only pinned to a pushed commit, as `<short-hash>:path:line`. `analysis.md` is written once and never revisited, so an unpinned line number in it rots for the life of the issue without anyone noticing.

**After writing:** Ask the user if they want to `open <path>` the analysis file.

## Ticket Constraint Validation

After `analysis.md` is written, perform this step before declaring research complete:

**Precondition — ticket text availability:** This step applies only when explicit ticket text is available in-session (loaded via `/load issue N`, `/load epic N`, or the equivalent `projctl load issue N` / `projctl load epic N` command, or supplied verbatim by the user in the current conversation). If no ticket text is available, do not create the `## Ticket Constraints` section. Append `(no ticket text — constraint validation skipped)` to the `progress_line` passed to the Planning checkpoint below. Do not attempt to re-derive ticket restrictions from memory, prior sessions, or the codebase.

1. Scan the ticket text (description, non-goals, acceptance criteria) for explicit restriction statements — "no X", "avoid Y", "out of scope", named non-goals. Do not infer constraints from the codebase, from prior conversations in this session, or from the AI's own priors. Include a candidate constraint only when the exact restriction phrase appears in the ticket text, or a rephrasing that preserves the noun and the negation (e.g. "no Python" → "avoid Python code" qualifies; "keep it simple" does not).
2. If any found, append a `## Ticket Constraints` section to `analysis.md`:
   ```
   - **<constraint as stated>** — practical risk: <one line on what breaks if this holds>
   ```
3. In the main conversation, present each constraint and ask: "This restriction was stated in the ticket — does it hold? What happens if we relax it?"
4. Record the user's decision inline in `analysis.md` next to each constraint:
   - `→ ACCEPTED` — constraint stands as stated (optional rationale may follow: `→ ACCEPTED — <note>`)
   - `→ REVISED: <new wording>` — constraint refined
   - `→ DROPPED: <reason>` — constraint removed
   DROPPED entries are NOT deleted from `analysis.md` — they remain with the `→ DROPPED: <reason>` marker so future auditors can see why. Keep the rationale legible. Phase 3 (design review) must consult `## Ticket Constraints` before flagging a design for violating a ticket restriction.
5. If no ticket-originated restrictions are found, do not create the `## Ticket Constraints` section and do not present a prompt to the user. Append `(no ticket-originated constraints found)` to the `progress_line` passed to the Planning checkpoint below.

Phase 2 (design) and Phase 3 (design review) MUST treat `## Ticket Constraints` as the authoritative source for ticket-originated restrictions. Original ticket text is context only — not a constraint list. Phase 3 reviewers must consult `## Ticket Constraints` before flagging a design for violating a ticket restriction.

**Example `## Ticket Constraints` block** (DROPPED entries are retained with their rationale — not deleted):

```markdown
## Ticket Constraints

- **No new Python code** — practical risk: re-implementing contracts Python already encodes in bash leads to field drift and test gaps. → DROPPED: restriction caused reimplementation of Python contracts in shell; relaxed to allow extending existing Python tooling only
- **Must remain stateless** — practical risk: limits retry and recovery options. → ACCEPTED
- **Must remain backwards compatible with v1 API** — practical risk: locks the design to the v1 schema regardless of data model needs. → REVISED: new endpoints may use the v2 schema; v1 endpoints must continue to work unchanged
```

## Acceptance Criteria Assessment

Ticket Constraint Validation above grades the ticket's *restrictions*; this grades its *acceptance criteria* — whether each is implementable, already satisfied, or not worth doing — and whether the issue fits the project's general approach at all. Research is the cheapest point to learn an AC is already met: later, the cost is a design built around work nobody needed.

**This step straddles the agent boundary, unlike the sibling above.** The **verdicts** are produced by the research agent *during* the investigation, because they need the codebase context it holds in Actions 2–4 — so the AC list reaches it in its launch prompt, not afterwards. The **decisions** are collected after `analysis.md` is written, in the main conversation, the way Ticket Constraint Validation collects its own. Grading in the main conversation after the agent has finished is the shape to avoid: it either spends a second agent round or produces an `ALREADY MET` citation nobody read the code for, which is the verdict this section says to distrust.

**Two gates, not one — the subsections below are independent.**

`## Acceptance Criteria Assessment` needs acceptance criteria to grade, so it takes the same precondition Ticket Constraint Validation states: without explicit ticket text in-session, do not create it, and append `(no ticket text — AC assessment skipped)` to the `progress_line`. Where ticket text exists but states no acceptance criteria, do not create it either, and append `(no acceptance criteria in ticket text)`. Never reconstruct an AC from the codebase, from a prior session, or from what the issue "obviously" wants — an invented AC graded by this step reads as the ticket's own.

**`## Project Fit` is unconditional.** It judges the issue's direction against the project, which research knows from the request whether or not a ticket exists, so it runs on every research pass and its verdict always reaches the `progress_line`. A no-ticket or no-AC pass still produces it.

### What the agent writes

The research agent assigns each AC one verdict, in `analysis.md` under `## Acceptance Criteria Assessment`. It has the codebase context from Actions 2–4, so this costs no extra investigation round.

**The graded list covers every acceptance criterion the ticket text states, and `N` equals that count.** An AC that is listed and unmarked is in scope; an AC that is never listed at all leaves scope with no verdict, no reason, and nothing downstream permitted to reinstate it — this section is the authoritative set and the design review is barred from grading coverage against the ticket, so an omission is a silent drop with less trace than writing `→ DROPPED` on it. An AC you cannot grade is listed with the blocker in place of a verdict, never left out. Completeness runs only in this direction: covering every stated AC is required, and inventing one that the ticket does not state is forbidden by the precondition above.

| Verdict | Means | Evidence required |
|---|---|---|
| `FEASIBLE` | implementable as stated, within this issue's scope | none — the default |
| `ALREADY MET` | the repository already satisfies it | **mandatory** — file + symbol, or a quoted distinctive token. No citation, no verdict |
| `INFEASIBLE: <what blocks it>` | cannot be met as stated: a capability that does not exist, a contradiction with an architecture invariant, a dependency outside this issue | the blocker, named |
| `DROP CANDIDATE: <why>` | feasible but not worth doing — duplicates another AC, asserts a dependency's behaviour, or costs more than it protects | the reasoning, one line |

`ALREADY MET` is the verdict to distrust. It is the only one that removes work, and a wrong one ships a gap nobody tested. State what you read; "the code appears to handle this" is not a citation.

**Read `## Prior Context` before re-reading anything.** Action 1's `search docs` run is already on the page, above this section, and it indexes the planning corpus — prior `analysis.md`, `design.md` and review reports. That is where "we already built this" and "we decided against this" are recorded. Where the Action 1 query missed the criterion being graded, run the one permitted second query (Action 1) and cite it inline.

**What each kind of evidence can settle, which is not the same for both verdicts.** A code read shows what exists; a recorded decision shows what was intended, and this corpus holds plenty of decisions for work that was planned and never built — the index is the only place an in-flight milestone is visible at all.

- `DROP CANDIDATE` asserts that something is **not worth doing**, a judgement about value. A recorded decision settles that on its own, and is the best evidence available for it.
- `ALREADY MET` asserts that the repository **already behaves** a certain way. Only the code can settle that, so the table's file-and-symbol citation stands as its own requirement — a prior decision corroborates it and never replaces it. This is the one verdict that removes work, and "we decided to build it" is not "it is built".

### What the user decides

**The verdicts are a recommendation. Only the user's recorded decision changes the AC set.**

**A `FEASIBLE` AC needs no decision and gets no marker — it is in scope exactly as the ticket states it.** That is what makes the other three verdicts worth presenting: only they propose a change. Downstream readers take absence of a marker as active, never as excluded, and `/design` states that rule at its own site.

Present every AC that is **not** `FEASIBLE` in the main conversation — the verdict, its evidence, and what changes if it stands — and record the answer inline beside the verdict:

- `→ KEEP` — the AC stands as written (an `ALREADY MET` kept this way becomes a regression to protect, not work to do)
- `→ REVISED: <new wording>` — narrowed, widened, or restated
- `→ DROPPED: <reason>` — removed from scope

`DROPPED` entries are never deleted from `analysis.md`; they stay with their reason so a later reader sees what left scope and why. **Never drop or rewrite an AC on your own authority, and never treat silence as a decision** — scope is the user's, the same rule `/ticket` criterion T1 states. An AC you believe is pointless and the user keeps is simply in scope.

An AC you presented and the user did not answer is **unresolved, not dropped**. Leave its verdict with no decision marker and say so at the Planning checkpoint; `/design` opens Q&A with it. Writing `→ DROPPED` on an unanswered recommendation is the one move this whole step exists to prevent.

### Project fit

One judgement for the issue as a whole, written under `## Project Fit` in `analysis.md`.

**Start from `## Prior Context`, not from a fresh read.** Those rows are the Action 1 `search docs` hits across the planning corpus, and a `TENSION` is usually only visible there — an in-flight milestone, a decision recorded in another issue's `design.md`, a convention set by a review. A code read cannot show you work that is planned but not yet written. Then read locally for what the index does not carry: the project's `CLAUDE.md` and `README`, its architecture docs, `planning/progress.md`, the milestone `status.md`, and the epic's `overview.md`, which is a local cache and needs no tracker call.

| Verdict | Means |
|---|---|
| `FITS` | the issue's direction matches the project's architecture, conventions and current roadmap |
| `TENSION: <what>` | it works, but cuts against an established pattern, an in-flight piece of work, or a stated convention |
| `MISFIT: <what>` | it contradicts an architecture decision, duplicates work already planned elsewhere, or belongs in a different component |

A `TENSION` or `MISFIT` is surfaced as a question and nothing more. It never silently redirects the issue, rewrites its scope, or becomes a design that solves a different problem.

**The answer is recorded with a marker, exactly as an AC decision is.** `FITS` needs none — nothing was asked. The other two carry one:

- `→ PROCEED: <reason>` — the user saw the tension and chose to go ahead; the design names it as a trade-off and does not re-ask
- `→ REDIRECTED: <what changes>` — the issue's scope or home changed; the AC decisions above are re-taken against the new scope, since a redirect can turn a `FEASIBLE` into an `INFEASIBLE`

**An unmarked `TENSION` or `MISFIT` is an open question, not an approved trade-off.** Without the marker, a concern the agent raised on its own is indistinguishable from one the user accepted — and the downstream readers are instructed to treat an approved one as settled, so the missing marker is what turns a guardrail against redirecting an issue into a way of suppressing a real misfit. Both consumers key on the marker, never on the bare verdict.

**Register:** what you write into `analysis.md` here is measured. `doc-metrics` skips `## Prior Context` because a machine pasted it, and skips nothing else — so these two sections face the register gate, and `REGISTER:` above 0 on `analysis.md` is a hard `/verify-docs` blocker. `/research` never runs that check; `/design` runs it three times, so a hedged verdict reason costs a fix round trip one phase later. Write each reason as a plain statement of fact: what blocks it, what already does it, what it duplicates. No "appears to", "may possibly", "it is worth noting that".

**Phase 2 (design) and Phase 3 (design review) MUST treat `## Acceptance Criteria Assessment` as the authoritative AC set.** Do not design for an AC recorded `→ DROPPED`, and do not flag a design for failing to cover one. An AC recorded `ALREADY MET → KEEP` is a behaviour to preserve and test, not to build. The ticket's original AC list is context only.

**Example block:**

```markdown
## Acceptance Criteria Assessment

- **Configuration survives a reboot** — `FEASIBLE`
- **Reads fall back to the last good config on a parse error** — `ALREADY MET`: `src/config/loader.cc` → `load_or_last_good()` already retains and returns the previous parse. → KEEP (regression to protect, not work to do)
- **Config reload completes within 50ms** — `INFEASIBLE: no reload path exists; the process reads config once at startup, so this AC presumes a capability this issue would have to add first.` → REVISED: config is re-read on SIGHUP; no latency bound this issue
- **The vendor SDK rejects a malformed payload** — `DROP CANDIDATE: asserts the SDK's own behaviour, with no repository code between the input and the assertion.` → DROPPED: covered by the vendor's own tests

## Project Fit

`TENSION: the issue adds a second config parser while milestone-03 is consolidating onto one.` → PROCEED: the consolidation lands later and will absorb this parser. Surfaced 2026-10-05.
```

The first entry shows the shape that matters most: a `FEASIBLE` AC carries a verdict and no arrow, and is in scope as written. Three of the four entries here propose a change and so carry a decision; the one that proposes nothing does not need one.

**Planning checkpoint** (`new_phase = research ✅`, `progress_line = - research complete — analysis.md written` extended with the constraint outcome — append one of: `(N constraints validated: A accepted, R revised, D dropped)` | `(no ticket-originated constraints found)` | `(no ticket text — constraint validation skipped)` — and then the AC outcome, one of `(N ACs: F feasible, A already met, I infeasible, C drop-candidate)` | `(no acceptance criteria in ticket text)` | `(no ticket text — AC assessment skipped)`, **followed in every case by** `fit: FITS|TENSION|MISFIT` since `## Project Fit` is unconditional, `escalation = standard`):

The four AC counters are **verdicts, one axis**, so `N = F+A+I+C` holds exactly — the sibling constraint counter counts decisions on its one axis for the same reason. Where any entry left scope or went unanswered, append the decisions as their own pair: `, D dropped, U unresolved`. Mixing the two axes in one list is what makes a recorded number irreproducible, since a `DROP CANDIDATE → KEEP` and a `FEASIBLE → DROPPED` each have two defensible homes.
```
Read ~/.claude/skills/workflows/planning-checkpoint/SKILL.md
```

**Next step:** Do not auto-invoke `/design`. Wait for the user to type `/design` or an equivalent explicit directive. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization — see CLAUDE.md Critical Rules for the two-part test.

