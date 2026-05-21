---
name: design
description: Create design proposal for implementation
---

# Design Command

Create detailed design proposal based on requirements and research findings.

## Agent

**architecture-research-planner (opus)** — all design doc work, including initial creation and applying review fixes, must be delegated to this agent. Never write or edit design files inline with Write/Edit tools in the main conversation.

## Skills Required

- domains/architecture (architecture patterns)
- domains/quality-attributes (quality considerations)

## Actions

### Step 0: Read context

```
Read ~/.claude/skills/workflows/complete-workflow/SKILL.md
Read ~/.claude/skills/workflows/planning/DESIGN-TEMPLATE.md
Read ~/.claude/skills/domains/architecture/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
```

Also read:
- `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md` (if it exists)
- The linked issue via `projctl load issue <N>` (if a ticket number is known)

### Step 1: Q&A Phase (main conversation — back-and-forth dialog)

Before spawning the agent, run a clarifying dialog in the main conversation.

**How to drive it:**
- Read the analysis and ticket first; ask only questions that are genuinely ambiguous — not things that can be inferred from context
- Ask **one question at a time**
- For each question: state what you found in the research, then offer 2–3 concrete options with a one-line trade-off per option
- Wait for the user's answer before asking the next question
- Follow up if an answer opens a new ambiguity
- Signal completion explicitly: "No further questions — ready to proceed"
- If the user answers "skip" or "your call": pick a reasonable default, note it as an assumption

**Standing question before finalizing any API surface:** ask whether multiple methods that share the same resource, preconditions, and side effects should collapse into a single call with a discriminated return type. Separate methods risk callers silently skipping a variant; a unified call enforces exhaustive handling at the type level. State the trade-off and let the user decide.

**Example question format:**
> I checked the vendor tree — Boost is available. For the state machine, three directions:
> 1. **Boost.MSM** — full-featured, already in project, but heavy compile times
> 2. **SML** (header-only, C++17) — lightweight, no new dependency, less documentation
> 3. **Hand-rolled** — zero dependency, full control, maintenance burden
>
> Which direction?

**Non-blocking:** unanswered questions become open questions in the design doc, not blockers.

### Step 2: Write clarifications to analysis doc

After the dialog, append a `## Clarifications` section to `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md`. If that file does not exist, create it with just this section.

```markdown
## Clarifications

**Q: <question topic>**
Options considered: <option A>, <option B>, <option C>.
**Decision:** <chosen option> — <one-line reason>.

**Q: <question topic>**
**Decision:** open question — proceeding with assumption: <X>.
```

### Step 3: Spawn architecture-research-planner

Declare: "I'll use architecture-research-planner agent to create the design document..."

Pass to the agent:
- The enriched analysis doc (including clarifications)
- The DESIGN-TEMPLATE.md structure
- The goal, milestone, feature context
- For post-review fixes: the review report and the enumerated findings to address

The agent produces `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` following the template (all 7 sections required; sections 6–7 may be omitted only when there are genuinely no alternatives or open questions, with a one-line note explaining why).

## Output

**File:** `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`

**Contains:**
- Header metadata (goal, milestone + GL/GH ref, feature ref, branch, status, revision)
- Problem statement
- Goals and non-goals
- Implementation context (repo, requirements, constraints, verification commands, context files)
- Architecture overview with Mermaid diagram
- Detailed design (component boundaries and interfaces — not implementation details or method signatures)
- Trade-offs and alternatives
- Open questions

**After writing:** Ask the user if they want to `open <path>` the design file.

## Key Principle

Design files describe **HOW** the system is structured (architecture, component contracts, trade-offs), not **WHAT** to do (that's in status.md) and not **HOW EXACTLY** to implement (that emerges during coding).

## Final Step — Push planning to backup

After writing the design file, push planning state to backup using the shared push fragment:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment: run `projctl sync push`. On failure, surface the standard warning and continue — do not fail this skill.

## Next Step

After design is complete, use `/review-design` to get approval before implementation.
