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

### Step 1: Detect on-device scope

Before Q&A, determine whether the feature's final goal involves execution on a physical device:

- Read the analysis doc and ticket description for signals: deployment targets, hardware references, CI-on-device, boot/init behavior, sensor or network interface access, OTA, embedded runtimes.
- If on-device execution is the final goal (or a mandatory part of verification), check whether the project documents how to reach the device — look in the project's `CLAUDE.md`, `README.md`, and any existing planning docs.
- Also determine whether verification requires a special test package (OTA image, firmware bundle, test APK, signed archive, etc.) that must be built before deploying. Look for packaging scripts, build targets, or CI jobs in the project that produce such artifacts.
- Also check for an existing verification entry point: search for `scripts/verify-device.sh`, Makefile targets (`verify-device`, `test-device`), or a `dev.sh` subcommand that wraps build + deploy + verify. Note whether an entry point already exists or must be created as a deliverable of this feature.

Record the outcome as one of:
- **On-device: YES** — feature targets device, project has documented procedures → On-Device Verification section is **MANDATORY** in the design doc
  - If a special test package is required: **Build test package step is MANDATORY** within that section
  - If a standard build suffices: omit the build-package step with a one-line note
  - **Entry point:** name it if it already exists; if it doesn't exist, flag it as a deliverable of this feature
- **On-device: YES, procedures unknown** — feature targets device, but no device procedures found in project docs → include an On-Device Verification stub block in Section 3 with every field explicitly marked TBD, and add an open question in Section 7 requiring resolution before implementation. Do not invent steps.
- **On-device: NO** — feature is software-only → omit the section with a one-line note

State the outcome explicitly in conversation before starting Q&A. Also write it to `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md` under a `## On-Device Scope` heading using the canonical machine-readable label — exactly one of: `YES` | `YES-UNKNOWN` | `NO` — followed by the source evidence (file name and relevant excerpt). The prose label "On-device: YES, procedures unknown" maps to the machine-readable label `YES-UNKNOWN`; always use the machine-readable form in analysis.md so downstream regex checks are reliable. If that file does not yet exist, create it with just this section. This heading is the authoritative scope signal for all downstream commands (review-design, review-code, verify) — they must read it rather than inferring scope from design doc section presence.

### Step 2: Q&A Phase (main conversation — back-and-forth dialog)

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

**Assumption vs. open question:** If the user answers "skip" or "your call", pick a reasonable default and log it as an assumption in `analysis.md` — this is NOT an open question and does not block the design. Reserve open questions for things that cannot be resolved with a reasonable assumption (e.g., requires external information or a stakeholder decision not yet made). The design is INCOMPLETE until all open questions are resolved.

### Step 3: Write clarifications to analysis doc

After the dialog, append a `## Clarifications` section to `planning/<goal>/milestone-XX/issues/<NNN-name>/analysis.md`. If that file does not exist, create it with just this section.

```markdown
## Clarifications

**Q: <question topic>**
Options considered: <option A>, <option B>, <option C>.
**Decision:** <chosen option> — <one-line reason>.

**Q: <question topic>**
**Decision:** assumption — <X> (user deferred; proceeding with this default).
```

### Step 4: Spawn architecture-research-planner

Declare: "I'll use architecture-research-planner agent to create the design document..."

Pass to the agent:
- The enriched analysis doc (including clarifications)
- The DESIGN-TEMPLATE.md structure
- The goal, milestone, feature context
- The on-device determination from step 1 — explicitly state one of:
  - "On-device verification is MANDATORY — include the On-Device Verification block in Section 3 using procedures from [source file]; build-test-package step is MANDATORY / not required (standard build suffices); entry point is [existing: `<script>` | new deliverable: must be created as part of this feature]; include 'Expected outcome on device' and 'Failure indicators' fields populated from project documentation"
  - "On-device scope detected but device procedures are unknown — include an On-Device Verification stub block in Section 3 with every field (entry point, build test package, deploy, verify, expected outcome, failure indicators) explicitly marked TBD; add an open question in Section 7 requiring resolution before implementation"
  - "No on-device scope — omit On-Device Verification with a one-line note"
- For post-review fixes: the review report and the enumerated findings to address

The agent produces `planning/<goal>/milestone-XX/issues/<NNN-name>/design.md` following the template (all 7 sections required; sections 6–7 may be omitted only when there are genuinely no alternatives or open questions, with a one-line note explaining why). The On-Device Verification block follows the same rule: MANDATORY when on-device scope is confirmed, otherwise omitted with a one-line note.

**Section 7 format rules (mandatory):**
- The section heading must be exactly `## 7. Open Questions`.
- Use ONLY unchecked `- [ ] <question>` checkboxes for genuine open questions — those requiring external information or a stakeholder decision not yet made.
- Items recorded in `analysis.md ## Clarifications` as `**Decision:** assumption — ...` are resolved defaults, NOT open questions. Do not copy them into `## 7. Open Questions`.
- If there are no open questions, write exactly: `*(None — omit this section or list specific open questions as \`- [ ] <question>\` items)*` and do not include any `- [ ]` checkbox.

### Step 5: Resolve open questions (blocking gate)

After the agent writes the design doc, read Section 7 (Open Questions) of `design.md`.

Apply the detection criteria from `~/.claude/skills/workflows/design-open-questions-gate/SKILL.md` Steps 2–3 to determine whether Section 7 is clean. That fragment is the authoritative definition — do not restate or re-derive the criteria here.

**If the gate criteria report no unresolved items:** the design is complete — proceed to the Output section.

**If the gate criteria report unresolved items:** the design is INCOMPLETE. Do not proceed to `/review-design`. Instead:

Increment the pass counter (starts at 0).

1. For each open question in turn: present it (same dialog format as Step 2 — state the context, offer concrete options), wait for the user's answer (including "accepted as known-unknown"), then immediately append that answer to `analysis.md` under `## Clarifications` (same format as Step 3) before moving to the next question.
2. After all open questions are answered, re-declare: "I'll use architecture-research-planner agent to update the design document with resolved questions..."
3. Re-invoke the architecture-research-planner agent with the updated `analysis.md` (including new clarifications) and the instruction to update `design.md`: remove from `## 7. Open Questions` ALL items — both those answered with a decision AND those accepted as known-unknown. Accepted-as-known-unknown questions are tracked in `analysis.md ## Clarifications` only; they must not remain in `design.md` Section 7. Incorporate answered decisions into the relevant design sections. After this pass, `## 7. Open Questions` must contain only the template's "none" note or be absent. Follow the Section 7 format rules above. Overwrite `design.md`.
4. Run `/verify-docs` on the modified `design.md`. If blockers are reported: invoke architecture-research-planner again scoped to fixing those blockers, then re-run `/verify-docs`. Cap at 2 consecutive blocker-fix cycles; if blockers persist, surface: "Doc consistency blockers remain — manual intervention needed." Pause and wait for user.
5. Return to the top of Step 5 and check Section 7 again using the gate criteria. Repeat until the gate passes.

**Iteration cap:** If the pass counter reaches 5 without the gate passing, stop and surface: "Design open questions unresolved after 5 passes — manual intervention needed." Pause and wait for user.

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

**After writing (only after Step 5 gate passes — all open questions resolved):**
1. Print a short summary in the conversation — 3–6 bullet points covering: chosen approach, key architectural decisions with rationale, significant trade-offs accepted. This is conversational output only; do not write it to any file.
2. Ask the user if they want to `open <path>` the design file.

**Planning checkpoint** (`new_phase = design 📝`, `progress_line = - design complete — design.md written, awaiting review`, `escalation = standard`; if the issue is not yet in the Active section, add a minimal entry first):
```
Read ~/.claude/skills/workflows/planning-checkpoint/SKILL.md
```

## Key Principle

Design files describe **HOW** the system is structured (architecture, component contracts, trade-offs), not **WHAT** to do (that's in status.md) and not **HOW EXACTLY** to implement (that emerges during coding).

## Next Step

After design is complete, use `/review-design` to get approval before implementation.
