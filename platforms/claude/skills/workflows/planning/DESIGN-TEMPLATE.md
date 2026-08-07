## Writing Rules

**This section is guidance for the writer. Do not copy it into the design doc** — a `## Writing Rules` heading in a `design.md` is a `/verify-docs` blocker, in the same class as a stray `RESOLVED` marker.

**One statement per fact.** A fact belongs in exactly one place. When you find an argument stated twice, delete the copy — do not relocate it. Relocating inflates: measured on a real compaction pass, moving five arguments out of Detailed Design cost 1,215 words there and added 1,031 to Trade-offs, because the Pros/Cons form is more verbose than the inline sentence it replaced. Never expand an inline paragraph into a Pros/Cons block while moving it.

**Dedup direction: keep the statement at the point of decision, delete the restatement.** Deleting the decision-point copy and keeping the summary strips the fact from where a reader needs it — on one pass a build-cache limit and a CI credential variable survived only in Trade-offs, gone from the two Detailed Design subsections that depended on them.

**No self-history.** A design doc describes the design, not its own editing. Cut "previously", "this was changed to", "as noted above", revision narration, and reviewer-round references. One exception: a note explaining a load-bearing numbering gap stays (e.g. "the requirement numbering is non-contiguous — no requirement carries FR-9 or FR-10"), because without it a reader reads the gap as a missing requirement.

**No defensive register.** The rule and its detector list live in `~/.claude/agents/architecture-research-planner.md` → Prose Register. A non-zero register count blocks in `/verify-docs`; the detector list is non-exhaustive, so zero is necessary, not sufficient.

**Length: a target and a ceiling per section.** Run the tool — it prints both, plus your delta and a verdict per row:

```bash
bash ~/.claude/scripts/doc-metrics.sh <path-to-design.md>
```

- `ok` — at or under the section's target.
- `over-target` — past the target. Advisory. Discharge it with one line of justification naming what the extra words buy.
- `OVER-CEILING` — past the ceiling the tool prints on that row, or past the whole-document ceiling on the `TOTAL` row. **This blocks in `/verify-docs`.** Ceilings exist only for Detailed Design, Test Requirements, and the document total; other sections show `-` and can only read `over-target`.

The tool owns every number, so nothing here can drift from it. Each target is that section's median and each ceiling its p75, measured across the design documents on this machine after canonicalising headings by content — so a document using the older 7-section numbering is scored against the same slots. Sample sizes differ per section and are smallest for Test Requirements; roughly half the existing corpus already meets each target, and about a quarter is over a ceiling.

Prose words means words outside fenced blocks and headings, plus table cell text at half weight. `wc -l` is meaningless here: the repo bans manual line wrapping, so one paragraph is one line and a 400-word addition to an existing paragraph shows a delta of zero. Table cells count at half because tabulating genuinely compresses — but excluding them outright let a section go from 5,021 words to zero by wrapping each line in pipes, with no word removed.

Sections whose content is itself the completeness argument are never compressed: derivation and closure tables with evidence, audit assertion lists, contract tables, named implementation invariants, Trade-offs Pros/Cons blocks, Mermaid diagrams, and template-mandated command blocks. Most are fenced blocks, which do not count at all, or table rows, which count at half. Use a table because the content is tabular, not to move prose out of measurement.

---

# Design — <Feature Name>

**Goal:** `<goal-folder-name>`
**Milestone:** `milestone-XX-<name>` · [%N](URL)
**Feature:** [#N](URL)
**Branch:** `feature/<branch-name>`
**Status:** Draft | Approved | Superseded
**Revision:** 1

---

## 1. Problem Statement

What problem does this solve? Why now?

---

## 2. Goals and Non-Goals

### Goals
- ...

### Non-Goals
- ...

---

## 3. Implementation Context

**Repository:** `/absolute/path/to/repo`

*(Every Functional Requirement, Non-Functional Requirement, and Constraint bullet below ends with an inline `From:` tag, written as bold Markdown — two asterisks, not a single-backtick mention — placed at the end of the bullet. Never write it as a bold label opening its own line: that form breaks codex-flow's requirement parser. Five values, each naming something a reader other than the author can retrieve except the last: `ticket <id>`, `incident <date>`, `decision <date>`, `spec <name>`, `analysis`.)*

*(`decision <date>` applies only where `analysis.md` → `## Clarifications` records that question with a real Decision, not an assumption default; everything else the author reasoned out alone — including a review finding first raised in a review report — carries `analysis`.)*

*(The five backtick-quoted values in the paragraph above are read by a test: `tests/verify-doc-metrics.sh` extracts them and compares them against `doc-metrics.sh`'s own accepted set. Reword the surrounding prose freely, but keep all five values on that one paragraph and re-run the suite afterwards.)*

**Functional Requirements:**
- ... — **From:** analysis

**Non-Functional Requirements:**
- ... — **From:** analysis

**Constraints:**
- ... — **From:** analysis

**Verification:**

*Extract from the project's `README.md` or `CLAUDE.md`. Must cover all three workflows.*

```bash
# Build / compile
<command>

# Test
<command>

# Debug / run
<command>
```

**On-Device Verification:** *(MANDATORY when the feature is device-verifiable and the project has documented device procedures. A feature is device-verifiable when the task, acceptance criteria, changed code path, CI/HIL job, verifier script, or project guidance makes target hardware or device/HIL validation relevant. Omit with a one-line note containing the explicit tag `on-device scope: NO` only after checking those sources — e.g., "On-Device Verification: N/A — feature is software-only (on-device scope: NO)." A note without this tag is treated as ambiguous by the reviewer.)*

*Derive from the project's `CLAUDE.md`, `README.md`, or existing planning docs. Do not invent steps — only include procedures that are known for this project's device.*

**Entry point:** `<script-or-make-target>` — the single command humans and CI invoke (e.g. `make verify-device`, `scripts/verify-device.sh`, `./dev.sh test-device`). Must already exist in the repo or be listed as a deliverable of this feature.

```bash
# Build test package (MANDATORY when verification requires a special artifact — OTA image,
# firmware bundle, test APK, etc.; omit with a one-line note if a standard build suffices)
<command>

# Deploy to device
<command>

# Verify on device
<command>
```

Expected outcome on device:
- ...

Failure indicators (what to check if verification does not pass):
- ...

**CI integration:** *(how CI triggers on-device verification when no local device is available — e.g., `DEVICE_IP` env var, a runner label/tag, a dedicated CI job name, or a webhook trigger. Omit with a one-line note if CI device testing is not configured for this project.)*

**Context Files:**

*Bare repo-relative paths only, one per bullet — no symbol, no line number, no backticks required. `codex-flow implement` parses these bullets and loads each file, silently skipping any entry that does not resolve as a path, so `` `path` → `symbol()` `` or a pinned `<hash>:path:line` here yields zero context files with no warning. Name symbols in §5 Detailed Design prose instead, where the citation rule applies normally.*

- path/to/file

**Observed-Failure Ledger:** *(Include when this work fixes a failure that actually happened — a red CI job, an on-device or deployment failure, a runtime crash, a manual-testing defect, a bug report, a flake, or a review finding confirmed to reproduce. Paste the entries from `<issue-folder>/observed-failures.md` inside a `~~~markdown` fence — unfenced, their `## <date>` headings would end this section. `codex-flow implement` runs from this document and never sees the issue folder, so an omitted ledger reads to it as new work and the required regression test is skipped silently. Omit the field entirely when no failure was observed. Placed after Context Files because the On-Device Verification field absorbs everything up to it.)*

---

## 4. Architecture Overview

```mermaid
...
```

Brief narrative explaining the diagram (3–5 sentences max).

---

## 5. Detailed Design

Describe component boundaries, interfaces, and contracts — not implementations.
Focus on: what each component is responsible for, how components communicate,
and any non-obvious invariants. Avoid method signatures, pseudocode, and file-level detail.

*(Feature-specific subsections — add as needed)*

---

## 6. Test Requirements

### Unit Tests
*(Single-component tests with collaborators mocked or stubbed. List the specific behaviours and failure modes that must be covered — not file names.)*
- ...

### Integration Tests
*(Component-boundary tests that cross at least one real dependency — database, filesystem, IPC, network call. List the interaction paths that must be exercised.)*
- ...

### E2E Tests
*(System- or user-flow-level tests that exercise the feature end-to-end. Omit with a one-line note if the feature has no user-facing or cross-service flow.)*

*(Omit E2E subsection with a one-line note if no E2E tests are required for this feature)*

---

## 7. Trade-offs and Alternatives

*(Every option below declares `Cost:` and `Misses:`. The cheapest option wins. A costlier option is admissible only when every cheaper option's `Misses:` names a §3 Functional Requirement, Non-Functional Requirement, or Constraint whose `From:` value is one of the four that override. `analysis` does not override, and an item carrying no tag does not either. An argument that is not a §3 item cannot be the reason the cheap option loses — a quality that genuinely matters goes into §3 as a requirement first, where it is visible and challengeable. When nothing in §3 separates the options and the trade is still live, escalate to the user rather than choosing.)*

### Option A — <Chosen Approach>
**Cost:** ~N LOC production · ~M LOC test · K files · <new mechanism | reuses `<existing>`>
**Misses:** <FR/NFR/Constraint it fails, or "none">
**Pros:** ...
**Cons:** ...

### Option B — <Alternative>
**Cost:** ~N LOC production · ~M LOC test · K files · <new mechanism | reuses `<existing>`>
**Misses:** <FR/NFR/Constraint it fails, or "none">
**Pros:** ...
**Cons:** ...

**Decision:** Chose A because …

*(Omit section with a one-line note if there are genuinely no alternatives)*

---

## 8. Open Questions

*(None — omit this section or list specific open questions as `- [ ] <question>` items)*
