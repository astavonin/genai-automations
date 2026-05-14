---
name: review-design
description: Review design before implementation using reviewer agent
---

# Design Review Command

**MANDATORY CHECKPOINT:** Review design proposal before any code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

Read review skills before starting:
```
Read ~/.claude/skills/domains/quality-attributes/SKILL.md
Read ~/.claude/skills/domains/quality-attributes/references/review-checklist.md
Read ~/.claude/skills/domains/quality-attributes/references/consensus-review-protocol.md
```

## Status Marker Convention (§4)

Every design review file MUST contain exactly one status marker as the **first non-empty line after the H1 title**, within the first 20 lines:

```
**Status:** APPROVED
```

Allowed states: `APPROVED` | `CHANGES REQUESTED` | `REJECTED` — all uppercase, no emoji, no verb/noun mixing.

This marker is machine-readable and used by the `/implement` gate (`head -20 <file> | grep -m 1 '^\*\*Status:\*\*'`). A review without the canonical marker will cause the compaction gate to skip at `/implement`.

## Actions

1. Load design document from `planning/<goal>/milestone-XX/design/<feature>-design.md`
2. Run the **Consensus Review Protocol** (Steps A–E) against the design document

   > **⚠️ PARALLEL-LAUNCH GATE**
   > Every call in Step A MUST be in **one message**. Splitting across messages serializes the review.
   > Self-check before sending: does this response contain every Agent call AND the `codex-flow` Bash call?
   > If any are missing — stop, add them, then send.

   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate once all four have returned: Steps B–D for Claude consensus, then cross-aggregate with Codex
   - **Each agent prompt must include the full "Design-Level Constraint" section above** — paste it verbatim before the review checklist so agents know what to flag and what to skip
3. Format consolidated findings as a markdown review report (see Output Format below)
4. **Write the report to `planning/<goal>/milestone-XX/reviews/<feature>-design-review.md`**

5. **Verify the status marker** before declaring the review complete:
   ```bash
   head -20 planning/<goal>/milestone-XX/reviews/<feature>-design-review.md | grep -m 1 '^\*\*Status:\*\*'
   ```
   - If the marker is found with a canonical state (`APPROVED`, `CHANGES REQUESTED`, or `REJECTED`) → proceed.
   - If the marker is missing or malformed → **do not declare the review complete**. Surface an error and either re-invoke the reviewer agent or ask the user to add the marker manually before continuing.

6. After writing, ask the user if they want to `open <path>` the review file
7. Wait for user approval (MANDATORY)
8. Block until approved

## Final Step — Push planning to backup

After the review file is written and the marker verified, push planning state to backup:

```
Read ~/.claude/skills/workflows/push-planning/SKILL.md
```

Follow the steps in that fragment: run `projctl sync push`. On failure, surface the standard warning and continue — do not fail this skill.

## Design-Level Constraint (MANDATORY — pass to every reviewer agent)

This is a **design review**, not a code review. Reviewers must stay at the architectural level.

**Flag (design-level concerns):**
- Missing or ambiguous contracts between components (e.g. "error propagation from write failures is undefined")
- Undefined or contradictory state machine transitions
- Component boundaries that make unit testing impossible (no seam, no injection point defined)
- Missing non-goals or scope ambiguities that will cause disagreement during implementation
- Design decisions that commit to a performance-hostile approach without documenting the trade-off
- Security or safety gaps at the architecture level (e.g. "auth is never checked on inbound messages")
- Concepts named but never defined (e.g. a field appears in a diagram but has no explanation)

**Do NOT flag (implementation-level — out of scope for design review):**
- Specific language constructs (`[[nodiscard]]`, `mutable`, `noexcept`, `static_assert`, etc.)
- Exact method signatures, return types, or parameter names
- Code snippets or pseudocode in findings or fixes
- Compilation or linkage issues
- Naming conventions for variables, enumerators, or files
- Implementation patterns (how to guard against null, how to implement a switch, etc.)

**Finding descriptions must name the architectural concern, not the fix.** The fix direction must also stay at concept level — "define an error propagation contract for write failures" not "change return type to `[[nodiscard]] bool`."

## Review Scope

Each of the 3 agents evaluates these design-level attributes:
- **Completeness:** All components, interfaces, and state transitions defined with enough clarity to implement consistently
- **Correctness:** No internal contradictions, no undefined concepts referenced in diagrams or tables
- **Contracts:** Error handling strategy, resource lifetime, thread-safety boundaries stated at component level
- **Testability:** Injection points and isolation boundaries identified at design level (not implementation detail)
- **Performance:** Design commits to no approach with known hot-path implications without documenting the trade-off
- **Safety/Security:** No structural gap that guarantees a safety or security violation regardless of implementation
- **Extendability:** Component boundaries allow future change without redesign
- **Minimality:** Flag public interfaces where multiple methods share the same read target, preconditions, and side effects but could be expressed as a single call with a discriminated return type. Separate methods over a shared resource risk silently skipping an action type on a given call site; a unified call enforces exhaustive handling at the type level.

## Output Format

Produce a markdown report using the reviewer agent's standard template:

```markdown
# Design Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature name>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description of the architectural concern — fix direction at concept level only, no code or language constructs

### High
- **H1** [attribute] Description...

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Codex-Only Findings

Findings raised by Codex not present in Claude consensus. Write "None." if empty.

- **X1** [severity] Description...

## Recommendation
<rationale and required actions — concept level only; no implementation specifics>
```

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity (C1, C2, H1, H2, M1, …). IDs are stable within a review session and used when discussing or resolving findings.

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings → proceed to implementation
- ⚠️ **Request Changes:** One or more High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → return to Phase 2

## After Resolving CHANGES REQUESTED Findings

When a review returns CHANGES REQUESTED and the findings are resolved through Q&A and doc updates:

1. Run `/verify-docs` on all modified files before requesting re-review.
2. Fix any blockers reported by `/verify-docs`.
3. Only then re-run `/review-design` for the follow-up review cycle.

This prevents the next reviewer from raising findings that are artifacts of incomplete or inconsistent doc updates rather than genuine design issues.

## Critical Rule

**NO code implementation without approval.**
