---
name: review-code
description: Review code after implementation using reviewer agent
---

# Code Review Command

**MANDATORY CHECKPOINT:** Review implementation after code is written.

## Agents

**3 × reviewer (opus)** — parallel focus-differentiated reviewers per consensus protocol (Steps A–D)
**1 × reviewer (opus)** — test-coverage agent (Step F)
**1 × codex-flow** — Codex cross-check, background Bash call (no approval prompt with `codex-flow` in allow list)

## Setup

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
```

**Then pre-read ALL implementation files** that will be reviewed — do this in the main conversation before launching the reviewer agent. Pass the file contents inline in the agent prompt so the agent never calls Read itself. This is mandatory: sub-agent Read calls trigger approval prompts; inline content does not.

Typical files to pre-read:
- All source files changed on the branch (`.h`, `.cc`, `.cpp`, `.py`, `.go`, `.rs`, `.sh`, etc.) — use `git diff origin/master...HEAD --name-only` to enumerate them
- **Interface files not in the diff:** for each changed `.cc`/`.cpp`/`.c` file, also read its `.h`/`.hpp` if it exists and is not already in the diff; for Go, read the interface definition files the changed package implements
- **Full design doc** (`planning/<goal>/milestone-XX/issues/<NNN-name>/design.md`) if one exists — pass the entire file, not just the acceptance criteria section
- **The observed-failure ledger** (`<issue-folder>/observed-failures.md`, resolved per `~/.claude/skills/workflows/issue-folder-resolve/SKILL.md`) if one exists — mandatory when present. Agents are instructed to validate its entries and waivers but may not Read it themselves; without it inline they will report a valid, user-approved waiver as a missing test, producing a finding no coder can fix. If it does not exist, say so explicitly in the prompt rather than omitting the topic.
- The review checklist

**Prior review:** If `planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md` exists from a previous review cycle, read it. Include it in every agent prompt with the instruction: "A prior review exists. For each finding previously marked CHANGES REQUESTED or REJECTED, verify whether it has been addressed in the current implementation. Re-raise unaddressed findings at their original severity; note addressed ones explicitly."

**Evidence for Codex:** Before writing the Step 0 review-request document, run the project's build and test commands and capture their output (exit codes + last 40 lines). Populate the Evidence section with this data. If the build or tests fail, note this prominently — Codex must factor it into its assessment.

**Ledger for Codex:** Populate the review-request's `## Observed-Failure Ledger` section with the contents of `<issue-folder>/observed-failures.md` **inside the template's `~~~markdown` fence** — a pasted ledger's own `## <date>` entry headings would otherwise end the section and read as empty — or the literal `No ledger exists for this work.` Codex sees only this document — omitting the section makes it flag user-approved waivers as missing tests.

## Status Marker Convention

```
Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
```

## File Overwrite Convention (§7.4)

This skill always writes a **single** file `code-review.md` inside the issue folder, **overwriting** any prior content. No versioning suffixes (`-v1`, `-v2`). No appending. Each run replaces. Git history in `planning/` preserves prior reviews if needed. The gate always reads the single latest file.

## Actions

1. Run the **Consensus Review Protocol** (Steps A–H) against the implementation

   ```
   Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
   ```
   (`test_coverage = yes`)

   - **Launch simultaneously:** 3 focus-differentiated Claude reviewer agents + test-coverage agent (Step F) + Codex (Step E) in parallel — see protocol for agent focus assignments
   - **Every Claude agent prompt must include** the pre-read files above (including the ledger) and the review checklist — the checklist carries Test Quality Pass Step 3 and its severity table, so no separate paste is needed. See the Observed-Failure Regression Requirement section below.
   - Do not wait for Claude agents to finish before starting Codex — they are independent
   - Aggregate per protocol: Steps B–D (Claude consensus) → Step E (Codex cross-aggregate) → Step F (test-coverage cross-aggregate) → Step G (single-finding adversarial reverification) → Step H (manual passes)
   - **Before launching Step G verifier agents:** reuse the `Repository:` value from the Step 0 Codex review-request document if one was written (same value Codex used); otherwise obtain it by running `pwd` in the main conversation's shell. Supply this path as the `Repository:` field in each verifier prompt (see protocol §Step G "How the main conversation obtains Repository"). Without it, relative paths in a finding's location cannot be resolved and Step G findings will be silently REFUTED-and-discarded.
2. Format consolidated findings as a markdown review report:
   ```
   Read ~/.claude/skills/workflows/review-output-format/SKILL.md
   ```
   (`review_type = Code Review`, `fix_review_extras = no`)
3. **Write the report to `planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md`** (overwriting any prior version)

4. **Verify the status marker** (`review_file = planning/<goal>/milestone-XX/issues/<NNN-name>/code-review.md`):
   ```
   Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
   ```

5. After writing, ask the user if they want to `open <path>` the review file

5b. **Report the outcome in the conversation:** the status marker, finding counts by severity, and the single most severe finding as one line. Nothing else — the report file holds the detail. This is a ceiling, not a template: a review aggregates 3–5 parallel agents plus Codex, and without it the aggregate lands in the conversation instead of the file.

6. **Update planning state** (`approved_phase = code review ✅`, `review_label = code review`, `approved_next = ready for MR`, `escalation = elevated`):
   ```
   Read ~/.claude/skills/workflows/review-planning-update/SKILL.md
   ```

7. **Phase gate (MANDATORY):** Do not auto-invoke `/verify`. Wait for the user to explicitly invoke `/verify` or an equivalent explicit directive. Reviewer `APPROVED` is NOT authorization — it is a precondition for asking the user. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization. See CLAUDE.md Critical Rules for the two-part test.

## Review Scope

Agents use differentiated focus areas — see the consensus protocol for per-agent assignments. All agents still report Critical/High issues outside their primary focus.

- **Agent 1:** Safety, Security, Performance
- **Agent 2:** Testability, Correctness, Code standards (library reuse, promotion)
- **Agent 3:** Observability, Maintainability, Extendability, Supportability

Additional cross-cutting checks applied by all agents:
- **Minimality:** The implementation is no larger than the approved design requires — flag an added indirection, abstraction, generalisation, or configuration knob that serves no §3 requirement and no §5 contract. This covers public API surface too: flag multiple methods that share the same underlying resource, preconditions, and side effects where a single call with a discriminated return type would eliminate the risk of a caller silently skipping an action type
- **Design adherence:** Matches approved design
- **Standards compliance:** Coding standards and static analysis per language guidelines
- **On-Device Verification entry point:** Read `analysis.md` under `## On-Device Scope`. If on-device scope is YES or YES-UNKNOWN, verify the entry-point script or Makefile target exists on disk regardless of whether the design doc contains an On-Device Verification section. If the design doc section is absent but on-device scope is YES or YES-UNKNOWN, flag that absence as a Critical finding for design adherence. If the `**Entry point:**` field contains a template placeholder (e.g., `<script-or-make-target>` copied verbatim from the template), flag as High immediately — do not attempt a disk existence check on a placeholder value. If the entry-point was listed as a deliverable, verify it is implemented and covers the documented build/deploy/verify steps, and that it reflects the expected outcomes and failure indicators from the design doc. Flag as High if the entry-point is missing or incomplete; flag as Critical if the design doc section is absent despite confirmed on-device scope.

## Behavioral Bug Test Requirement

```
Read ~/.claude/skills/workflows/behavioral-bug-test/SKILL.md
```

## Observed-Failure Regression Requirement

If any part of the diff fixes a failure that actually happened, a test reproducing it must be in the diff and recorded in the issue folder's ledger.

```
Read ~/.claude/skills/workflows/regression-test/SKILL.md
```

Applicability and the trigger list live in that fragment — do not work from a paraphrase. Instruct **all** agents (the 3 consensus reviewers and the Step F test-coverage agent) to run the checklist's Test Quality Pass Step 3, which carries the criteria and the severity table inline. An absent ledger is not an exemption: when the diff shows evidence of an observed failure, a missing entry is itself a High finding.

## Assessment

- ✅ **Approve:** Zero Critical, zero High, and zero Medium findings → proceed to `/verify`
- ⚠️ **Request Changes:** One or more High or Medium findings → fix and re-review
- ❌ **Reject:** One or more Critical findings → redesign needed

## After Resolving CHANGES REQUESTED Findings

When a review returns CHANGES REQUESTED and fixes touch `docs/` or `planning/**/issues/*/` files:

1. Run `/verify-docs`, passing the resolved `<issue-folder>` (per `~/.claude/skills/workflows/issue-folder-resolve/SKILL.md`). The folder argument is required — the command enumerates planning docs from it and from nothing else, so omitting it makes both scans report `Clean` over an empty file list.
2. Fix any blockers reported by `/verify-docs`.
3. Only then re-run `/review-code`.

## Next Step

After the user explicitly invokes `/verify`, run tests and static analysis (Phase 6). Do not suggest or auto-invoke `/verify` — the phase gate above applies.
