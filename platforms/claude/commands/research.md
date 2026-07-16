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

1. Investigate existing codebase patterns
2. Understand current architecture
3. Identify integration points and dependencies
4. Ask clarifying questions if requirements are unclear

## Output

**File:** `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md`

**Contains:**
- Codebase analysis
- Architecture diagrams (Mermaid)
- Research findings
- Integration points
- Dependency analysis

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

## Usage

```
"I'll use architecture-research-planner agent to investigate [feature/area]..."
```
