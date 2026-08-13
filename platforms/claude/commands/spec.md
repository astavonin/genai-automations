---
name: spec
description: Produce a coding specification for an article — scope, functional/non-functional requirements, public API contract, and unit/integration test requirements. Phase 1 of the article authoring workflow.
---

# Spec Command

Produce a specification for the current article issue — the **contract** `/review-article` checks the article against. Which kind of contract applies depends on the page type, resolved below: a `main` page gets a coding contract, an `appendix` page a fact contract.

## Usage

```
/spec [<issue-folder-path>]
```

The path argument selects the page type and therefore the contract. Without it the folder is derived from the active issue in `planning/progress.md`, which tracks main articles only — **so an appendix page must be given explicitly.**

## Page type (do this first)

```
Read ~/.claude/skills/workflows/page-type/SKILL.md
```

That fragment owns the path forms, the template per type, the companion-repo policy, and the mandatory rejection rule for a `planning/book/` path matching neither form. Resolve the page type from the argument or the derivation, echo it on one line, and stop with the fragment's error text if the path matches neither form.

**`main` — this spec is a coding contract.** It defines what the CODE must do, not what the ARTICLE should say. Article-shape decisions (theory scope, reader arc, section outline, diagrams, language-neutrality) are handled at `/write` time via the article brief (`brief.md`). The spec must not include article scope, theory scope, or reader-facing content decisions. `/review-article` Scope 1 (Code Accuracy) validates the implementation against it (`SPEC-TEMPLATE.md`).

**`appendix` — this spec is a fact contract**, since an A-page has no companion implementation for a coding contract to constrain. It records every claim the page will make, the authoritative source behind it, and the command or document lookup that established it (`APPENDIX-SPEC-TEMPLATE.md`). Those facts can only be produced here: this session has the kernel tree, the datasheets, and hardware access. Web-Claude writes the prose and cannot verify a single hardware claim, so anything not verified at spec time ships unverified. `/review-article` Scope 2A validates the draft against it.

`<issue-folder>` below means the resolved folder. Steps flagged **appendix** replace their `main` counterpart; everything unflagged applies to both.

## Agent

**architecture-research-planner (opus)** — spec writing must be delegated to this agent. Never write or edit spec files inline with Write/Edit tools.

## Actions

### Step 0: Read context

```
Read ~/.claude/skills/workflows/planning/SPEC-TEMPLATE.md            # main
Read ~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md   # appendix
Read CLAUDE.local.md                         # companion repos table + technical familiarity
cat planning/progress.md                     # identify active issue + folder
cat planning/book/milestone-XX-<name>/status.md   # article notes (main)
cat planning/book/appendix/status.md              # Pages + Linked from rows (appendix)
```

Read only the template for the resolved page type.

Also read `<issue-folder>/analysis.md` if it exists.

**appendix:** `analysis.md` here is pre-existing research, **not** verified fact. Read `planning/book/appendix/status.md` → "Known defects in research notes" before using any of it. Every claim carried from `analysis.md` into §2 must be re-verified against an authoritative source and recorded in §5 with the command or document lookup that established it. Carrying a claim across on the strength of it already being written down is exactly the failure this mode exists to stop.

If `planning/book/todos.md` exists:

```
Read ~/.claude/skills/workflows/article-review/TODOS.md
```

Derive the identifier and match entries per `~/.claude/skills/workflows/page-type/SKILL.md` → "Identifier derivation and TODO matching", which states both branches — step 0a for an **appendix** page, steps 1–4 for a `main` page. For an **appendix** page each matched entry is a claim the page must establish. A `main` page whose part cannot be determined skips the TODO scan and proceeds — do not halt; an appendix page has no part and that is not a skip condition. Follow the Type B Predicate and Article Identifier Derivation rules in TODOS.md to extract open entries. Type A (inline placeholder) TODOs are not extracted here — placeholders belong in the draft, not the spec; only Type B items become spec requirements.

Pass extracted Type B items to the agent in Step 3 as additional requirements context with instruction: "These open TODOs must be resolved by this article — incorporate their resolution as Functional Requirements, Non-Functional Requirements, or Test Requirements in the appropriate spec sections. Do not list them as a separate TODO section."

### Step 1: Locate evidence sources

**main:** From the `CLAUDE.local.md` companion repos table, resolve the local path for the current article's part. Confirm the directory exists before proceeding. If the path does not exist, stop and ask the user.

**appendix:** There is no companion repo to locate — an A-page's evidence is external. Enumerate what is reachable in this session and record it, because §5 can only cite sources that were actually available:

- **Target hardware.** Check reachability (`CLAUDE.local.md` names the device and access method). If reachable, on-device measurement is available and every hardware claim in §2 must use it. If not reachable, say so explicitly — hardware claims then carry `[UNVERIFIED: no device access]` and `/write` propagates that into brief.md §9.
- **Kernel and driver documentation** for the claimed subsystem (kernel.org docs, in-tree `Documentation/`, man pages).
- **Vendor documentation** — datasheets, TRMs, errata — for any SoC, sensor, or peripheral claim.
- **Specifications** — RFCs, ITU-T, ISO, OASIS — for any protocol or format claim.
- **Companion repo, optional.** Resolve the repo for the part owning most of this page's Blocks column if one exists. It is corroboration, never the authority: an A-page documents what the hardware and specification do, not what one implementation happens to assume.

Do not stop when a source is unavailable. Record the gap and let §2 carry the claim as unverified — a spec that halts produces nothing, and a spec that silently drops the claim is how the fabrication got in.

### Step 2: Q&A (short — only for genuine ambiguity)

Read the article notes from `status.md` (**main**), or the Pages and Linked-from rows for this page (**appendix**). If the scope and behaviours are clear enough to write the spec without clarification, skip directly to Step 3 and say "No questions — proceeding to spec."

If clarification is needed, ask at most 2–3 questions, one at a time. Ask only when:
- The in/out of scope boundary is genuinely ambiguous from the article notes
- Whether a behaviour is testable without hardware is unclear (unit vs. integration boundary)
- Whether a type is new or modifies an existing contract is unclear
- **NOT** when the question is about the article rather than the code. Questions about article shape ("should this article cover theory X?", "what's the target length?", "what's the target audience depth?") are NOT spec-time questions. The writer agent handles those at `/write` time via the article brief. If a question surfaces here that is article-shaped rather than code-shaped, do not ask it; skip it and proceed. Do not record it as a spec deferral either — record it nowhere; it will re-surface at `/write` time if it matters.

### Step 3: Spawn architecture-research-planner

Pass to the agent:
- The article notes from `status.md` for this issue (main), or the Pages + Linked from rows and the Known-defects table (appendix)
- The analysis.md content (if it exists) — in **appendix** mode label it **unverified prior research**; in `main` mode pass it as before, with no trust designation
- The companion repo local path and instruction to read all relevant source files before writing (main), or the Step 1 evidence-source inventory including device reachability (appendix)
- The full template structure for the resolved page type — all 5 sections required
- Any Q&A answers from Step 2

**Agent instructions — main:**

1. Read all relevant source files in the companion repo first. Identify what currently exists vs. what is new or modified.
2. Write `<issue-folder>/spec.md` following SPEC-TEMPLATE.md exactly.

**Agent instructions — appendix:**

1. Enumerate every claim the page will make, from the status.md topic row and the depth each dependent article needs. Claims come before sources: decide what must be true, then go find out whether it is.
2. For each claim, establish it against an authoritative source, and **run the check rather than recalling the answer**. A hardware claim is verified by querying the device, not by reasoning about the SoC. A specification claim cites document and section. A kernel-behaviour claim cites the documentation path or the source file.
3. Record every check in §5 as a reproducible command or lookup with its actual captured output. §5 is the deliverable that justifies §2 — a claim in §2 with no §5 row is unverified regardless of how confident it reads.
4. Any claim that could not be established gets `[UNVERIFIED: <what is missing>]` in §2 and no §5 row. Never drop it silently and never soften it into something that sounds checked.
5. Write `<issue-folder>/spec.md` following APPENDIX-SPEC-TEMPLATE.md exactly.

**Section rules to enforce — appendix:**

- **Scope (§1):** which concepts this page carries and which it defers, plus the dependent articles from the Blocks column and the depth each needs. Depth is set by what the dependents require, not by what is interesting.
- **Claims (§2):** one row per assertion, each with its authoritative source. Numbers, alignments, device names, register widths, and format layouts are all claims. Prose that asserts nothing checkable does not belong here.
- **Source Requirements (§3):** pass/fail rules — SR1 no claim from memory (verified §2 table only; the unverified table is exempt by construction), SR2 hardware claims verified on-device, SR3 vendor claims cite a document section, SR4 specification claims cite a numbered section, SR5 a device is named only after its presence is confirmed and absence is recorded as absence, SR6 the claimed token appears literally in the §5 output, SR7 every §5 row records where and when it ran, SR8 every claim ID appears in exactly one §2 table and every `Verified by` names a §5 row whose `Establishes` lists that ID. Read `APPENDIX-SPEC-TEMPLATE.md` §3 in full for the exact rule text — this list is a summary, not a replacement — and its `## Rules` section for the authoring principles behind them.
- **Terminology Contract (§4):** terms this page defines that dependent articles then use. These bind: a main article citing this A-page for a definition must find the same definition here.
- **Verification Procedure (§5):** the command or lookup per claim, with captured output. This is the section only this session can produce.

**Section rules to enforce — main:**

- **Scope (§1):** Both lists must be explicit. **In Scope / Out of Scope describe what the CODE does and does not do.** "Reader" here means the reader of the coding contract (an implementer), not the reader of the article. Do not use Out of Scope to describe article-level content decisions (theory deferrals, appendix references, prose scope). Article-content decisions are made at `/write` time.
  - Valid Out of Scope entry: `Multi-planar V4L2 buffers (V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE) are not handled by this code.`
  - INVALID Out of Scope entries (belong at `/write` time, not spec time): `Pixel format theory deferred to Appendix A1.`, `Historical context of V4L2 not covered in this article.`
- **Functional Requirements (§2):** Observable outputs and side effects only. No implementation choices, no crate names, no "use X pattern." Each FR must be independently verifiable.
- **Non-Functional Requirements (§3):** Hard constraints — safety flags, performance bounds, compile targets, dependency rules, runtime restrictions. Phrased as pass/fail, not aspirations.
- **Public API Contract (§4):** Types and their invariants. No method signatures, no crate choices. State what the type guarantees, not how it does it.
- **Test Requirements (§5):**
  - Unit tests: runnable in CI without hardware and without network; mocks/fakes allowed; one row per test case
  - Integration tests: require real-but-accessible infrastructure (vivid virtual device, local socket, etc.); one row per test case
  - Hardware tests: always deferred unless the article is explicitly about on-device testing; state which article they belong to and what dependency blocks them

### Step 4: Post-write

1. Confirm the header reads `**Status:** Draft`. `/spec` leaves it there however finished the spec looks — `/review-spec` is the only writer of `Approved`, and the field is meant to record a review rather than the author's decision to stop editing. `SPEC-TEMPLATE.md` → `## Rules` states the rule for both templates; `APPENDIX-SPEC-TEMPLATE.md` points there.
2. Run the spec's own evidence. The board is reachable here by construction — the spec was just written against it — and a `main` spec scans nothing and prints that reason.

   ```bash
   spec-verify "<issue-folder>"
   ```

   `0` means the scan ran or had nothing to scan; any non-zero exit is a blocker, and exit `127` means the package is not installed (`pip install -e ./tools/docgate`). A non-zero `FAIL:` count stops this command: report the failing rows and the token each lost, and hand them back for re-running on the board, since a `FAIL` is discharged by re-capturing §5 and never by editing the `Conclusion:` until it matches. A non-zero `SKIP:` count reports and does not stop.
3. Ask the user if they want to `open <path>` the spec file.
4. Push planning to backup:
   ```
   Read ~/.claude/skills/workflows/push-planning/SKILL.md
   ```

## Output

**File:** `<issue-folder>/spec.md`

**main contains:**
- Header (article, repo, issue, status)
- §1 Scope — in / out of scope (explicit lists)
- §2 Functional Requirements
- §3 Non-Functional Requirements
- §4 Public API Contract (types + invariants)
- §5 Test Requirements (unit, integration, hardware)

**appendix contains:**
- Header (page, dependent articles, evidence sources, device reachability, status)
- §1 Scope — concepts carried / deferred, dependent articles and the depth each needs
- §2 Claims — every assertion with its authoritative source
- §3 Source Requirements — pass/fail sourcing rules
- §4 Terminology Contract — definitions dependent articles bind to
- §5 Verification Procedure — command or lookup per claim, with captured output

## Next Step

**main:** after the spec is correct, the user implements in the companion repo (Phase 2), then `/write` produces the brief (Phase 3).

**appendix:** there is no implementation phase — the spec's §5 is the work. Go straight to `/write` on the same issue folder, which reads §2 and §5 as verified facts for brief.md §7.5 only — §8 is not used for an appendix page (`write.md` → 2d "Routing (appendix)").
