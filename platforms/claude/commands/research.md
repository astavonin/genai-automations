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
2. Investigate existing codebase patterns
3. Understand current architecture
4. Identify integration points and dependencies
5. Ask clarifying questions if requirements are unclear

## Output

**File:** `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md`

**Contains:**
- Codebase analysis
- Architecture diagrams (Mermaid)
- Research findings
- Integration points
- Dependency analysis
- A `## Prior Context` section, holding the Action 1 `search docs` run

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

**Planning checkpoint** (`new_phase = research ✅`, `progress_line = - research complete — analysis.md written` extended with the constraint outcome — append one of: `(N constraints validated: A accepted, R revised, D dropped)` | `(no ticket-originated constraints found)` | `(no ticket text — constraint validation skipped)`, `escalation = standard`):
```
Read ~/.claude/skills/workflows/planning-checkpoint/SKILL.md
```

**Next step:** Do not auto-invoke `/design`. Wait for the user to type `/design` or an equivalent explicit directive. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization — see CLAUDE.md Critical Rules for the two-part test.

