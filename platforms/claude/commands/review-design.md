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

1. Load design document from `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`, **and its sibling `analysis.md` if one exists** — pass both inline in every agent prompt. The Design-Level Constraint below tells each agent to corroborate the header's `**Class:**` against `analysis.md` → `## Change Class` and to raise a disagreement as its own finding; agents may not call Read themselves, so without the file inline that rule cannot fire in the one review where the class is first declared. `analysis.md` also carries `## Ticket Constraints`, which the Ticket Constraint Guardrail depends on.
2. Run the **Consensus Review Protocol** (Steps 0, A–E and **Step G**; skip Step F and Step H — those two are code/fix/MR-only) against the design document. Step G uses its **design-review verifier variant**; single-agent and Codex-only findings are adversarially reverified before they reach the report.

   ```
   Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
   ```
   (`test_coverage = no`)

   - **Step 0 review-request document, two parts:** populate its `## Constraints` → `**Class:**` line with the **higher** of the design doc header's `**Class:**` value and `analysis.md` → `## Change Class` (either alone where only one is set), **and** paste the Change Class Calibration table beneath that section's bullet list, fresh from `~/.claude/skills/domains/quality-attributes/references/review-checklist.md`. Codex runs with `--ignore-user-config --ignore-rules`, so the pasted table is the only grading scale it receives — the bundled reviewer skill carries a pointer to it plus the two carve-outs, never the table itself. A request with a class and no table falls back to `PRODUCT-NEW` with compatibility at `PRODUCT-SHIPPED`, which is the over-rigor this mechanism exists to remove
   - **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel — skip Step F (no code or tests to evaluate)
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate: Steps B–D (Claude consensus) → Step E (Codex cross-aggregate) → **Step G** (adversarial reverification, design criteria). Single-agent Claude findings and Codex-only findings are reverified 2-of-2; survivors land in `## Reverified Findings`, and nothing unreverified reaches the report. Skip Steps F and H.
   - **Each agent prompt must include the full "Design-Level Constraint" section below** — paste it verbatim before the review checklist so agents know what to flag and what to skip. **This applies to the Step G verifiers too**, not only the three primary reviewers: a verifier without the flag list and the Ticket Constraint Guardrail applies different scope rules than the reviewer whose finding it is adjudicating.
   - **Each of the three primary reviewer prompts must also carry the full "Premise Question" section below**, pasted verbatim — the three primary reviewer prompts, not the Step G verifier prompts: a verifier's output contract is a `VERDICT:` line per finding, with no slot for a non-finding answer, so pasting the question there produces an instruction a verifier can satisfy only by ignoring it. (`tests/verify-config-consistency.sh` reads this bullet.)
   - **Before launching Step G verifiers**, resolve absolute paths for `design.md`, its sibling `analysis.md` (pass `none` only if the file genuinely does not exist), and the repository root via the Step 0 review-request `Repository:` value or `pwd`. Relative paths do not resolve in a verifier agent, and the failure is silent — both verifiers fail their reads, both return REFUTED, and rule 3 discards every finding with no warning. If any path cannot be resolved, do not launch: surface the Step G warning and treat all eligible findings as discarded-with-warning.
3. Format consolidated findings as a markdown review report (see Output Format below); lift each PREMISE: block into ## Premise Answers verbatim, writing `no answer returned` where a reviewer omitted its block. (`tests/verify-config-consistency.sh` reads this line.)
4. **Write the report to `planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`**

5. **Verify the status marker** (`review_file = planning/<goal>/milestone-XX/issues/<NNN-name>/design-review.md`):
   ```
   Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
   ```

6. **If the review status is `APPROVED`, update the design doc header — two edits, not one:**
   ```bash
   # In planning/<goal>/milestone-XX/issues/<NNN-name>/design.md:
   # **Status:** Draft  →  **Status:** Approved
   # and add below **Revision:**  —  **Approved:** <YYYY-MM-DD>, at Revision <N>, via design review
   ```
   Use the Edit tool for both. Read the doc's current `**Revision:**` value rather than assuming it — the number recorded is the revision this review actually read, and it moves on every fix pass. `DESIGN-TEMPLATE.md` omits the field by design: a Draft has nothing to record, so this step is what creates it. Skip both edits if status is `CHANGES REQUESTED` or `REJECTED`.

7. **Update planning state** (`approved_phase = implementing 🔨`, `review_label = design review`, `approved_next = ready for implementation`, `escalation = standard`):
   ```
   Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
   ```

8. After writing, ask the user if they want to `open <path>` the review file

9. **Report the outcome in the conversation:** the status marker, finding counts by severity, and the single most severe finding as one line. Nothing else — the report file holds the detail. This is a ceiling, not a template: a review aggregates 3–5 parallel agents, and without it the aggregate lands in the conversation instead of the file.

```
Read ~/.claude/skills/workflows/round-verdict/SKILL.md
```

State its line, unprompted: **`Another round: yes|no — <reason>`**. The fragment carries the signals the reason rests on; do not restate them here.

10. **Phase gate (MANDATORY):** Do not auto-invoke `/implement`. Wait for the user to explicitly invoke `/implement` or an equivalent explicit directive. Reviewer `APPROVED` is NOT authorization — it is a precondition for asking the user. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization. See CLAUDE.md Critical Rules for the two-part test.

## Design-Level Constraint (MANDATORY — pass to every reviewer agent)

This is a **design review**, not a code review. Reviewers must stay at the architectural level.

**Grade against the change class before assigning any severity.** The design doc header declares `**Class:**` (`CI` | `TEST` | `PRODUCT-NEW` | `PRODUCT-SHIPPED`, ordered in that sequence), corroborated by `analysis.md` → `## Change Class`; the calibration table is `~/.claude/skills/domains/quality-attributes/references/review-checklist.md` → Change Class Calibration, and the definitions are `~/.claude/skills/domains/architecture/SKILL.md` → Change Class. A missing fallback is Low in `CI` and High in `PRODUCT-SHIPPED` — same finding, different severity. Demanding rigor the class does not warrant is a defect in the review, since the mechanism it asks for has to be maintained forever. Where the header and `analysis.md` disagree, grade against the **higher** class and raise the disagreement as its own finding. Where neither declares a class, or the header is left as the template's verbatim alternation (`CI | TEST | PRODUCT-NEW | PRODUCT-SHIPPED`), treat it as undeclared: review as `PRODUCT-NEW` and flag the missing declaration as Medium — the calibration table's `PRODUCT-NEW` row already grades compatibility at `PRODUCT-SHIPPED` for a defaulted class.

**Flag (design-level concerns):**
- Missing or ambiguous contracts between components (e.g. "error propagation from write failures is undefined")
- Undefined or contradictory state machine transitions
- Component boundaries that make unit testing impossible (no seam, no injection point defined)
- Missing non-goals or scope ambiguities that will cause disagreement during implementation
- Design decisions that commit to a performance-hostile approach without documenting the trade-off
- Security or safety gaps at the architecture level (e.g. "auth is never checked on inbound messages")
- Concepts named but never defined (e.g. a field appears in a diagram but has no explanation)
- On-Device Verification section absent when the feature's on-device scope is YES or YES-UNKNOWN (as recorded in `analysis.md ## On-Device Scope`) — flag as Critical
- On-Device Verification section present but entry point missing, unnamed, or set to a template placeholder (e.g. `<script-or-make-target>` copied verbatim from the template) — flag as High; without a real entry point neither humans nor CI can invoke the tests
- On-Device Verification section present but steps are not derived from project documentation (invented steps, no source cited) — flag as High
- On-Device Verification section present but entry point is neither confirmed to exist in the repo nor listed as a deliverable of this feature — flag as High
- On-Device Verification section present but expected outcome or failure indicators are undefined — flag as High
- `CI` or `TEST` design whose §3 enumerates a failure mode of the environment — substrate, dependency, or infrastructure behaviour, not a path the change's own code takes — on a bullet whose `**From:**` tag reads `analysis`. It covers Functional Requirement, Non-Functional Requirement, and Constraint bullets alike, and catches a failure mode the artifact is required to handle rather than a recorded fact or limitation of the environment. The tag is the test, and the fix is to drop the requirement or carry it through `## 8. Open Questions` to a recorded user Decision the tag can cite. This is the Class fit criterion's failure-mode-enumeration case in its §3 form under Review Scope with its severity fixed; the calibration table's downgrade rows do not reach it, since an over-broad §3 is not an unhandled condition, a missing fallback, or an uncovered path. (`tests/verify-config-consistency.sh` reads this bullet.) — flag as Medium
- A §3 item that exists to justify the chosen mechanism rather than to constrain it: a Functional Requirement, Non-Functional Requirement, or Constraint where a cheaper §7 option's exclusion rests on the item alone, so the item rather than cost decides the comparison — read §7's `Cost:` and `Misses:` lines to settle it. The rule's target is a bullet whose `**From:**` tag reads `analysis`; a `ticket`, `incident`, `spec`, or `decision` referent cites a source outside the design itself and is exempt. The fix is to drop the item and re-price §7 without it, or carry it through `## 8. Open Questions` to a recorded user Decision the tag can cite. (`tests/verify-config-consistency.sh` reads this bullet.) — flag as Medium

**Ticket Constraint Guardrail (applies to all flag rules above):**
Before flagging a design for violating a ticket restriction, consult `analysis.md` `## Ticket Constraints`. Only ACCEPTED and REVISED entries are enforceable — DROPPED entries and restrictions not listed must not be flagged. If the section is absent (research predates this convention, no ticket text was available in-session, or no ticket-originated restrictions were found), no ticket-originated restrictions are enforceable in this review — flag only design-quality issues.

**Acceptance Criteria Guardrail (same shape, different section):**
`analysis.md` → `## Acceptance Criteria Assessment` is the authoritative AC set, not the ticket's original list. An AC recorded `→ DROPPED` left scope at research time with the user's decision — **do not flag a design for failing to cover it**, and do not reinstate it as a gap. An AC recorded `ALREADY MET → KEEP` is a behaviour the design must preserve rather than build, so a design that rebuilds it is over-scope, not thorough. Where the section is absent, the ticket's AC list is context only and no AC-coverage finding is enforceable. `## Project Fit` is read by its **decision marker**, never by the bare verdict. Three branches:

- `→ PROCEED` — a decision the user made. Not a design defect, and not re-raised here.
- `→ REDIRECTED` — the issue's scope or home changed on record. **Grade the design against the redirected scope**, and flag a design that still implements the pre-redirect one: that design solves a problem the user moved away from, and it is the failure the redirect exists to prevent.
- **no marker** — never put to the user, so a design that proceeds as though it were settled is flagged: the concern is open, and the design should have surfaced it. That distinction is the whole point of the marker — without it an agent-authored misfit and a user-approved one are byte-identical, and this guardrail would suppress the first along with the second.

**Do NOT flag (implementation-level — out of scope for design review):**
- Specific language constructs (`[[nodiscard]]`, `mutable`, `noexcept`, `static_assert`, etc.)
- Exact method signatures, return types, or parameter names
- Code snippets or pseudocode in findings or fixes
- Compilation or linkage issues
- Naming conventions for variables, enumerators, or files
- Implementation patterns (how to guard against null, how to implement a switch, etc.)

**Finding descriptions must name the architectural concern, not the fix.** The fix direction must also stay at concept level — "define an error propagation contract for write failures" not "change return type to `[[nodiscard]] bool`."

## Premise Question (MANDATORY — pass to the three primary reviewer prompts)

**Should this design exist in this shape?** Answer this before you list findings, in one paragraph.

A finding says *the mechanism does not work as specified*. This question asks the other thing: whether a requirement or the whole approach should exist at all. Answer against the artifacts this prompt supplies — the design document and its sibling `analysis.md` — and do not go looking for others. Grounds that qualify — `analysis.md` records a Decision or a Ticket Constraint that the design's shape contradicts; the design contradicts its own frame, so a requirement the rest of the document makes unnecessary is still in §3; the requirement is the defect, so the fix is to delete it rather than implement it.

Where your answer challenges the frame, name the §3 requirement or the `analysis.md` entry it rests on. An answer resting on an artifact you were not given is out of reach — say that instead of asserting it.

Return the answer as a block headed `PREMISE:`, before your findings list. "The frame is sound" is a complete answer. This answer is not a finding: it carries no severity, it is not graded, and it cannot change the approval bar. (`tests/verify-config-consistency.sh` reads this section.)

## Review Scope

Each of the 3 agents evaluates these design-level attributes, every one of them graded against the declared change class per the Design-Level Constraint above:
- **Class fit:** The declared `**Class:**` matches what the change actually touches, and the design's depth matches the class — flag a `PRODUCT-SHIPPED` design that names no compatibility surface, and equally a `CI` or `TEST` design carrying fallbacks, migration paths, or failure-mode enumeration its class does not warrant; a `CI` or `TEST` design that skips a reachable path must state the gap in §6 → Tests Not Written — an undeclared gap reads as an oversight, not a decision
- **Completeness:** All components, interfaces, and state transitions defined with enough clarity to implement consistently
- **Correctness:** No internal contradictions, no undefined concepts referenced in diagrams or tables
- **Contracts:** Error handling strategy, resource lifetime, thread-safety boundaries stated at component level
- **Testability:** Injection points and isolation boundaries identified at design level (not implementation detail)
- **Performance:** Design commits to no approach with known hot-path implications without documenting the trade-off
- **Safety/Security:** No structural gap that guarantees a safety or security violation regardless of implementation
- **Extendability:** Component boundaries allow future change without redesign
- **Minimality:** The design's mechanism is no larger than §3 requires — flag any component, background process, cache, abstraction layer, or configuration surface that no Functional Requirement, Non-Functional Requirement, or Constraint in §3 needs. This covers public interfaces too: flag multiple methods that share the same read target, preconditions, and side effects but could be expressed as a single call with a discriminated return type. Separate methods over a shared resource risk silently skipping an action type on a given call site; a unified call enforces exhaustive handling at the type level.
- **On-Device Verification (always — check `analysis.md ## On-Device Scope`; if on-device scope is YES or YES-UNKNOWN and the section is absent from the design doc, flag as Critical; if the section is present, verify: entry point is named (`**Entry point:**` field populated and not a template placeholder such as `<script-or-make-target>`), steps are derived from project documentation not invented, entry point either already exists in the repo or is explicitly listed as a deliverable of this feature, expected outcome and failure indicators are defined).**

## Output Format

Produce a markdown report:

```markdown
# Design Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <feature name>
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject
**Codex:** ✓ ran | ✗ not run — <reason if skipped>
**Step G:** <N> eligible → <C> confirmed, <R> refuted, <U> unparseable | ✗ not run — <reason if skipped>
**Class:** <value> (declared | defaulted)

## Findings (<N total — consensus of 3 reviewers>)

### Critical
- **C1** [attribute] Description of the architectural concern — fix direction at concept level only, no code or language constructs

### High
- **H1** [attribute] Description...

### Medium
- **M1** [attribute] Description...

### Low
- **L1** [attribute] Description...

## Reverified Findings

Single-agent Claude findings and Codex-only findings that survived Step G adversarial reverification — both verifiers returned `VERDICT: CONFIRMED`. These carry the same weight as consensus findings and count toward the assessment. Include even if 0 — write "None."

- **V1** [severity] [Reverified] Description...

## Premise Answers (advisory — not graded)

Each reviewer's answer to the Premise Question, verbatim and unmerged. These are not findings: no severity, no IDs, no consensus, and outside the approval bar. One row per reviewer, always — write `no answer returned` where a reviewer omitted its `PREMISE:` block.

- **Reviewer 1** — <answer verbatim>
- **Reviewer 2** — <answer verbatim>
- **Reviewer 3** — <answer verbatim>

## Recommendation
<rationale and required actions — concept level only; no implementation specifics>
```

IDs are prefixed by severity for the main Findings section (C = Critical, H = High, M = Medium, L = Low) and by `V` for Reverified Findings. Number sequentially within each section (e.g., `V1`, `V2`). IDs are stable within a review session.

**The Step G report line above has its alternation pinned byte-for-byte against the other two sites** — see `~/.claude/skills/workflows/review-output-format/SKILL.md`'s shared-alternation paragraph for the rule and the fourth-site guard it describes. (`tests/verify-config-consistency.sh` reads this line.)

## Assessment

- ✅ **Approve:** Zero Critical and zero High findings **across `## Findings` and `## Reverified Findings` combined**, and every Medium fixed — reverified findings carry the same weight, so an approval that ignores them is wrong → proceed to implementation
- ⚠️ **Request Changes:** One or more Critical or High findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → return to Phase 2

**A Medium costs a fix, not a round.** Zero Critical and zero High with Mediums open takes `CHANGES REQUESTED` here, since this command only reports; the Mediums are then fixed and the approval follows without a second review. `/review-design-fix-loop` does both in one run.

**`## Premise Answers` sits outside this bar.** The three bullets above read `## Findings` and `## Reverified Findings` and nothing else. A premise answer carries no severity and no ID, so it cannot move the assessment — the operator reads the section and decides what to do with it. (`tests/verify-config-consistency.sh` reads this paragraph.)

## After Resolving CHANGES REQUESTED Findings

When a review returns CHANGES REQUESTED and the findings are resolved through Q&A and doc updates:

1. Run `/verify-docs`, passing the resolved `<issue-folder>` (per `~/.claude/skills/workflows/issue-folder-resolve/SKILL.md`). The folder argument is required — the command enumerates planning docs from it and from nothing else, so omitting it makes both scans report `Clean` over an empty file list.
2. Fix any blockers reported by `/verify-docs`.
3. Only then re-run `/review-design` for the follow-up review cycle.

**Unless the resolved findings were Mediums only.** A Medium costs a fix, not a round, so re-running `/review-design` would spend the round this bar exists to save. Where the review carried zero Critical and zero High, and the Mediums are now fixed with the build and test suites passing, close it without another review pass: overwrite `design-review.md`'s `**Status:**` to `APPROVED`, its `**Assessment:**` to `✅ Approve`, and its `## Recommendation` to name the closed findings; add a `## Mediums Fixed Without Re-Review` heading listing them; then run `~/.claude/skills/workflows/review-planning-update/SKILL.md` so the phase leaves `changes requested 🔄`. Without this step the work parks there indefinitely, because no other command writes that approval.

This prevents the next reviewer from raising findings that are artifacts of incomplete or inconsistent doc updates rather than genuine design issues.

## Critical Rule

**NO code implementation without approval.**
