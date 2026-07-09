---
name: review-design
description: Review design before implementation using reviewer agent
---

# Design Review Command

**MANDATORY CHECKPOINT:** Review design proposal before any code is written.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol

## Setup

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
```

## Status Marker Convention

```
Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
```

## Actions

### Step 0: Pre-flight — check for open questions (blocking gate)

```
Read ~/.claude/skills/workflows/design-open-questions-gate/SKILL.md
```

Only proceed when the gate passes.

1. Load design document from `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`
2. Run the **Consensus Review Protocol** (Steps 0, A–G; skip Step F and Step H — both are code-only) against the design document

   ```
   Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
   ```
   (`test_coverage = no`)

   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel — skip Step F (no code or tests to evaluate)
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate: Steps B–D (Claude consensus) → Step E (Codex cross-aggregate) → Step G (single-finding reverification)
   - **Each agent prompt must include the full "Design-Level Constraint" section below** — paste it verbatim before the review checklist so agents know what to flag and what to skip
3. Format consolidated findings as a markdown review report (see Output Format below)
4. **Write the report to `planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`**

5. **Verify the status marker** (`review_file = planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`):
   ```
   Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
   ```

6. **If the review status is `APPROVED`, update the design doc header:**
   ```bash
   # In planning/<goal>/milestone-XX/issues/<NNN-name>/design.md, change:
   # **Status:** Draft  →  **Status:** Approved
   ```
   Use the Edit tool to make this change. Skip this step if status is `CHANGES REQUESTED` or `REJECTED`.

7. **Update planning state** (`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`):
   ```
   Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
   ```

8. After writing, ask the user if they want to `open <path>` the review file
9. **Phase gate (MANDATORY):** Do not auto-invoke `/implement`. Wait for the user to explicitly invoke `/implement` or an equivalent explicit directive. Reviewer `APPROVED` is NOT authorization — it is a precondition for asking the user. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization. See CLAUDE.md Critical Rules for the two-part test.

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
- On-Device Verification section absent when the feature's on-device scope is YES (as recorded in `analysis.md ## On-Device Scope`) — flag as Critical
- On-Device Verification section present but entry point missing, unnamed, or set to a template placeholder (e.g. `<script-or-make-target>` copied verbatim from the template) — flag as High; without a real entry point neither humans nor CI can invoke the tests
- On-Device Verification section present but steps are not derived from project documentation (invented steps, no source cited) — flag as High
- On-Device Verification section present but entry point is neither confirmed to exist in the repo nor listed as a deliverable of this feature — flag as High
- On-Device Verification section present but expected outcome or failure indicators are undefined — flag as High

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
- **On-Device Verification (always — check `analysis.md ## On-Device Scope`; if on-device scope is YES and the section is absent from the design doc, flag as Critical; if the section is present, verify: entry point is named (`**Entry point:**` field populated and not a template placeholder such as `<script-or-make-target>`), steps are derived from project documentation not invented, entry point either already exists in the repo or is explicitly listed as a deliverable of this feature, expected outcome and failure indicators are defined).**

## Output Format

Produce a markdown report:

```markdown
# Design Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature name>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject
**Codex:** ✓ ran | ✗ not run — <reason if skipped>

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

IDs are prefixed by severity: C = Critical, H = High, M = Medium, L = Low. Number sequentially within each severity. IDs are stable within a review session.

## Assessment

- ✅ **Approve:** Zero Critical, zero High, and zero Medium findings → proceed to implementation
- ⚠️ **Request Changes:** One or more High or Medium findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → return to Phase 2

## After Resolving CHANGES REQUESTED Findings

When a review returns CHANGES REQUESTED and the findings are resolved through Q&A and doc updates:

1. Run `/verify-docs` on all modified files before requesting re-review.
2. Fix any blockers reported by `/verify-docs`.
3. Only then re-run `/review-design` for the follow-up review cycle.

This prevents the next reviewer from raising findings that are artifacts of incomplete or inconsistent doc updates rather than genuine design issues.

## Critical Rule

**NO code implementation without approval.**
