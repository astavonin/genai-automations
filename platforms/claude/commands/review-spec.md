---
name: review-spec
description: Review a spec before it becomes code or prose — grades whether its evidence establishes the claims it makes.
---

# Spec Review Command

Grades whether a spec's evidence establishes its claims. It runs between `/spec` and `/write`, where nothing else reads the document: `spec-verify` re-executes §5 and checks the tokens each Conclusion turns on, and its own `COVERS:` line names what it leaves — over-reach on genuine evidence.

Standalone and user-invoked. Not wired into `/spec`, not a precondition of `/write`, and it advances no milestone phase.

## Usage

```
/review-spec <issue-folder> [<companion-repo-path>]
```

`<issue-folder>` resolves through:

```
Read ~/.claude/skills/workflows/page-type/SKILL.md
```

That fragment's "Obtaining the path" and "Resolution" sections own the argument-first rule and both path forms, as they do for `/review-article`. An appendix spec must be passed explicitly — the `progress.md` derivation reaches only main articles. Stop with the fragment's error text on a `planning/book/` path matching neither form.

If `<issue-folder>/spec.md` is absent, report the missing file and stop — launch no agents.

`<companion-repo-path>` is read by the **main** criteria set only. Resolve it through the "Companion repo resolution" rule in:

```
Read ~/.claude/commands/review-article.md
```

That rule owns the precondition, the argument fallback, and the ambiguity handling. Do not restate it here. It keys on the article's part number and never reads `SPEC-TEMPLATE.md`'s own `**Companion repo:**` header field, so pass the path as an argument wherever the two would disagree.

## Agents

**3 × reviewer (opus)** — run in parallel per consensus protocol, plus Codex (Step E).

## Setup

```
Read ~/.claude/skills/workflows/review-setup/SKILL.md
```

## Status Marker Convention

```
Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
```

## Paths

| Protocol placeholder | Value |
|---|---|
| `<review-request-path>` | `<issue-folder>/codex-review-request.md` |
| `<codex-output-path>` | `<issue-folder>/codex-review.md` |
| report | `<issue-folder>/spec-review.md` |

Delete the review-request and the Codex raw output once `spec-review.md` is published.

## Actions

### Step 0: Pre-flight

**1. Run the spec's mechanical checks first.**

```bash
spec-verify "<issue-folder>"
```

Its summary counters are attention direction for the reviewers, never a verdict on this review. **No `spec-verify` result blocks the run, and no `FAIL` row is cited as a finding on its own** — a `FAIL` is as often a stale corpus as a wrong spec. Exit `127` means the package is not installed (`pip install -e ./tools/docgate`); rerun after installing.

What reaches each reviewer, on the appendix branch:

| Field | What a reviewer does with it |
|---|---|
| Per-row `PASS` / `FAIL` / `SKIP` | A `PASS` row is where over-reach hides — the mechanical check already said yes, so only judgment is left. A `FAIL` directs attention without settling anything. |
| `GRAPH:` and the six-field check | These discharge SR8 and SR7. No agent re-derives them; both are already blocking checks at `/spec` Step 4 and in `/verify-docs`. |
| `TOKENS:` and `COVERS:` | An all-skip run means SR6 established nothing and every claim is judgment-only. `COVERS:` names the residue this command exists for. |

A main spec scans nothing and exits `0` with that reason, so the main branch gets no counters. Its criteria need only the spec and the companion repository.

**2. Select the criteria set from the header field.** Read the lines of `spec.md` above the first `## ` heading, skipping fenced blocks — the same bounds `tools/docgate/docgate/specverify.py` → `spec_kind()` uses.

| Header carries | Criteria set |
|---|---|
| `**Page:**`, on a path Usage resolved to `appendix` | Appendix — SP-1, SP-2, SP-4, SP-5, SP-6, SP-9 |
| `**Article:**`, on a path Usage resolved to `main` | Main — SP-7, SP-8, SP-9 |
| neither, both, or one the resolved page type contradicts | **Blocker — stop.** Report the fields found and the resolved page type, clear an `Approved` in the spec's `**Status:**` field to `Draft`, and launch no agents. |

Keying on §5's presence instead would let an appendix spec that lost or retitled §5 grade as a main spec and skip the entailment criteria entirely. Both fields present is a blocker rather than a first-match win: `spec_kind()` returns on whichever line it reaches first, so the same header would select a different criteria set once its lines were reordered, and `spec-verify` does not settle the case for you.

A header field the resolved page type contradicts is the same blocker on the same grounds — two sources naming different sets, with no rule that settles which wins. An appendix spec carrying `**Article:**` selects the main set, so SP-1 to SP-6 never run and SP-7 and SP-8 grade against a companion repo an appendix page does not have; the likely outcome is zero findings and `Approved`. The stop writes no report, so Step 2 item 3 never runs — clearing the field here is what keeps an `Approved` earned under the old convention from standing on a spec no reviewer could grade.

**3. Write the Codex review request** to `<review-request-path>` per Step 0 of the consensus protocol, from `~/.claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md`. Paste the selected criteria set into its `## Requirements` section.

A spec review has no diff, so the ledger section carries the reason on the same line rather than the template's bare placeholder: `No ledger exists for this work — spec review, no diff to regress.` Codex reads only this document, and its bundled reviewer skill runs the observed-failure regression pass unconditionally, so a bare absence reads as an unresolved gap and returns a High that no spec edit can clear. The template's own rule says it — an absence is defensible only when the reason travels with it.

This settles the pass for *this review*, not for the spec's subject matter. A failure that actually happened to the document under review still belongs in a ledger somewhere; what it does not belong to is a review with nothing to regress against.

`Repository:` stays the planning repo the template pins it to, so the paths the criteria are graded against travel in `## Context` — the two fields `~/.claude/skills/workflows/article-review/CODEX-REQUEST-TEMPLATE.md` already carries there under the same read-only invocation:

```
**Spec:** <absolute path to spec.md>
**Companion code repo:** <absolute path, or "n/a — appendix spec">
```

Codex is the only one of the four reviewers whose instructions are a document rather than a prompt, so the paths the other three receive at launch reach it only here.

### Step 1: Run the review

Run the **Consensus Review Protocol** (Steps 0, A–E and **Step G**; skip Step F and Step H — both presuppose code and tests a spec does not contain) against `<issue-folder>/spec.md`.

```
Read ~/.claude/skills/workflows/review-hard-gate/SKILL.md
```
(`test_coverage = no`)

- **Launch simultaneously:** 3 Claude reviewer agents (Steps A–D) **and** Codex (Step E) in parallel.
- **Every reviewer prompt carries the selected criteria set pasted whole**, plus the agent's emphasis row below and the `spec-verify` counters. Never paste the other branch's set, and never paste a subset.
- **The criteria set replaces the eight quality attributes `~/.claude/agents/reviewer.md` mandates**, and each agent returns a raw findings list rather than its own `# Review Summary` document. A reviewer that keeps the attribute mandate grades a document those attributes were not written for, and the focus-split rule then carries every such finding into a report no criterion defines.
- **Resolve absolute paths before launching** — `spec.md`, and on the main branch the companion repo — and carry both in every reviewer prompt, in the same form Step G below requires. SP-7 and SP-8 are graded against that tree and nothing else; a reviewer holding no path grades mechanism claims from recall, which is the failure this command exists to remove.
- **Every reviewer fetches the sources its assigned claims cite, using its own tools.** Reading a claim's source is what separates this review from grading it from recall — no source text is stored anywhere, and no fetched document, on-device output or intermediate file survives the run.
- Aggregate: Steps B–D (Claude consensus) → Step E (Codex cross-aggregate) → **Step G** (adversarial reverification, spec-review variant below).
- **Before launching Step G verifiers**, resolve absolute paths for `spec.md`, its sibling `analysis.md` (pass `none` only if the file genuinely does not exist), the repository root, and — on the main branch — the companion repo. Relative paths do not resolve in a verifier agent and the failure is silent: both verifiers fail their reads, both return REFUTED, and every eligible finding is discarded with no warning. If any path cannot be resolved, do not launch; surface the Step G warning and treat all eligible findings as discarded-with-warning.
- **Each Step G verifier prompt carries the same selected criteria set *and* the two questions from "Step G — Spec-Review Verifier Variant" below, both pasted whole.** A verifier without the criteria block grades by different rules than the reviewer whose finding it is adjudicating. One without the two questions falls back to the skeleton's closing default — "if you cannot definitively confirm, output `VERDICT: REFUTED`" — which discards every entailment finding, the class this command exists to produce.

### Step 2: Write and gate the report

1. Format the consolidated findings per Output Format below and write them to `<issue-folder>/spec-review.md`. One final published output, overwritten in place on every re-run — no `-r<N>` or `-final` suffix; git history is the retry log.

2. **Verify the status marker** (`review_file = <issue-folder>/spec-review.md`):
   ```
   Read ~/.claude/skills/workflows/status-marker-verify/SKILL.md
   ```

3. **Set the spec's `**Status:**` field from the review outcome.** Read the field's current value in `<issue-folder>/spec.md` first, then apply the matching row with the Edit tool — an Edit whose `old_string` is absent errors out, so the starting value is read, never assumed.

   The first four rows key on the field's **exact** value. Both templates ship the literal `Draft | Approved`, which contains each of them and would otherwise match two rows prescribing opposite actions; a value present but neither exactly `Draft` nor exactly `Approved` takes the last row instead, and an absent field takes the row above it.

   | Field currently reads | Review status | Action |
   |---|---|---|
   | `Draft` | `APPROVED` | edit to `Approved` |
   | `Approved` | `APPROVED` | none — already correct |
   | `Approved` | `CHANGES REQUESTED` or `REJECTED` | edit to `Draft` |
   | `Draft` | `CHANGES REQUESTED` or `REJECTED` | none |
   | no `**Status:**` field | any | none — do not add the field |
   | any other value, the templates' `Draft \| Approved` included | any | edit to `Approved` on `APPROVED`, to `Draft` otherwise |

   This command is the only writer of `Approved`; `/spec` writes `Draft`, and a spec already reading `Approved` before this command existed is re-run through it rather than grandfathered. A review that fails such a spec clears the field it did not earn.

4. Delete `<review-request-path>` and `<codex-output-path>`.

5. **No planning-state update runs.** A spec review advances no milestone phase.

6. Ask the user if they want to `open <path>` the review file.

7. **Report the outcome in the conversation:** the status marker, finding counts by severity, and the single most severe finding as one line. Nothing else — the report file holds the detail.

8. **Phase gate (MANDATORY):** do not auto-invoke `/write`, `/spec`, or any other command. Wait for the user. Reviewer `APPROVED` is NOT authorization — it is a precondition for asking. Conversational acknowledgements (see Definitions in CLAUDE.md) are NOT authorization.

## Appendix-Spec Criteria (MANDATORY — paste whole into every reviewer and every Step G verifier prompt)

Selected when the header carries `**Page:**`.

Six criteria; the numbering skips SP-3, and the six below are the whole set. Each of the first five grades one verified §2 claim against the §5 rows that claim's `Verified by` names, and no other row. Where the missing support sits in an unnamed row, the finding is that `Verified by` needs extending, never that the claim needs weakening. SP-9 grades the document's structure and no claim.

No criterion names a claim, a row, or a string from any spec. A reviewer handed this block has not been handed the answers.

- **SP-1 — Entailment (High).** The claim holds as written — quantifier and subject included — and its predicate stays inside the surface the row's command observed. A claim that no member of a set exposes something, graded against an enumeration of that whole set, is inside it; a claim about which component performs a function, graded against one component's output, is not. The test covers the row's choice of command too: whether it can settle the claim, not merely that it ran.
- **SP-2 — Untested sufficiency (High).** A claim that an operation succeeds, is permitted, or is sufficient is established only by a row that attempted it. A permission-model claim read off an ownership listing is the recurring form.
- **SP-4 — SR3 and SR4, citation precision (High for a vendor claim, Medium for a specification claim).** A datasheet or TRM claim names its section; a specification claim names the numbered clause.
- **SP-5 — SR5, presence before naming (Medium).** A device or peripheral is named only after its presence is confirmed, and absence is recorded as absence rather than omitted.
- **SP-6 — SR1, source attribution honest (High).** The `Source` column names what was consulted. A row claiming on-device measurement alone, for a claim that rests on an implementation nobody opened, fails it.
- **SP-9 — Structural completeness (blocker).** The sections `~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md` requires are present: §1 Scope, §2 Claims, §3 Source Requirements, §4 Terminology Contract, §5 Verification Procedure. Several absent sections yield **one** blocker naming them all, not a finding per absent section. This criterion is structural only: it grades whether a section is there, never what the section says — a spec with no §2 has no claims for the five criteria above to grade, and without this one the whole set returns nothing. A §2 present but holding no verified claim row leaves exactly that nothing, and joins the same blocker; a row count is structure, not content.

SR6, SR7 and SR8 are not re-graded here — `spec-verify` executes all three and both its call sites block on a non-zero `FAIL:`. No `FAIL` row is cited as a finding on its own either: a `FAIL` is as often a stale corpus as a wrong spec, so it directs attention without settling anything.

## Main-Spec Criteria (MANDATORY — paste whole into every reviewer and every Step G verifier prompt)

Selected when the header carries `**Article:**`.

Three criteria, under the same no-examples rule. A main spec has no §5 Verification Procedure, so entailment is graded against the companion repository **as it stands when the review runs**. A claim that has decayed since the spec was written is itself a finding.

- **SP-7 — Existing-entity assertions (High).** Every entity the spec says already exists resolves in the companion repo. The discriminator is the assertion, not the name: a phrase asserting prior existence is falsifiable, a bare `` `X` `` naming what the spec is about to create is not. Do not widen this to "every named entity must resolve" — that fires on roughly a third of a main spec against zero real defects.
- **SP-8 — Repository-mechanism assertions (High).** A claim about how the repo enforces or configures something today names the mechanism actually in use. The failure is the right property asserted at the wrong mechanism, which reads as true.
- **SP-9 — Structural completeness (blocker).** The sections `~/.claude/skills/workflows/planning/SPEC-TEMPLATE.md` requires are present: §1 Scope, §2 Functional Requirements, §3 Non-Functional Requirements, §4 Public API Contract, §5 Test Requirements. Several absent sections yield **one** blocker naming them all, not a finding per absent section. This criterion is structural only: it does not grade whether an FR lands in §4, and it does not grade an NFR against an FR for contradiction.

## Agent Focus Split

One prompt contract: every reviewer and every verifier receives the selected branch's full criteria set and nothing from the other branch. The table assigns emphasis inside that set. The protocol's rule that a Critical or High outside an agent's focus is still reported applies unchanged.

| Agent | Appendix emphasis | Main emphasis |
|---|---|---|
| 1 | SP-1 and SP-2 over the verified claims | SP-7 over §2 and §3 |
| 2 | SP-4 to SP-6; fetches each cited datasheet, kernel document and specification section | SP-8 over §2 and §3 |
| 3 | SP-9, then §4's Terminology Contract graded by SP-1's discriminator against the claim IDs each entry cites; a definition that outruns its evidence is the same over-reach one section on. An entry citing no claim is ungraded | SP-9 |

**Criteria maintenance.** A change to either criteria block is re-checked by hand, by whoever edits the block: dry runs over a spec with known defects, over one whose equivalent construct is correct, and over each stop condition, with each outcome recorded. No command schedules them and no shell assertion detects a criterion that starts firing where it should not — the dry runs are the only falsifier the blocks have, and skipping them leaves an over-firing criterion undetectable.

## Step G — Spec-Review Verifier Variant

The standard verifier asks whether a finding survives an attempt to refute it, which resolves against an entailment finding every time — an entailment judgment has nothing measurable behind it to survive with. Two questions replace it, selected per finding:

**Entailment findings — SP-1, SP-2, SP-7, SP-8.** The `Location:` form and the reading both branch on spec type, because only an appendix spec has a §5 Verification Procedure to name.

| Spec type | `Location:` names | The verifier reads |
|---|---|---|
| appendix — SP-1, SP-2 | the §2 claim ID plus every §5 row its `Verified by` names | the claim and those rows side by side, asking whether the recorded output plus the cited documents establish the claim **as stated** |
| main — SP-7, SP-8 | the §2 or §3 requirement identifier the assertion sits in, or a distinctive quoted token from it where the spec numbers nothing | that requirement against the **companion repository as it stands now**, at the absolute path Step 1 resolved |

`VERDICT: CONFIRMED` means the evidence falls short. A main-spec finding names no §5 row because there is none to name; refuting one for that reason discards a correct finding and returns an incorrect spec to approval.

**Own-criterion findings — SP-4, SP-5, SP-6, SP-9.** The question is the criterion itself, checked against the text the finding cites. `VERDICT: CONFIRMED` means the criterion is breached. Under the entailment question a true finding here would be refuted for having no entailment to judge, and vanish into a permitted approval.

**Any other finding** — one the criteria sets do not cover, which the focus-split rule still requires reported — keeps the standard survives-refutation question.

**`analysis.md` is context, never evidence.** The protocol supplies it so a verifier can see what the spec means and what was already asked. It never establishes that a claim holds: `~/.claude/skills/workflows/planning/APPENDIX-SPEC-TEMPLATE.md` → `## Rules` puts it plainly — prior research predates the spec it sits beside, and anything carried across is re-verified rather than inherited. A verifier that refutes an entailment finding because `analysis.md` restates the same over-reaching assertion has located where the defect came from, not a reason to discard it.

**Step B direct-inclusion split.** SP-4, SP-5, SP-6 and SP-9 are decidable by reading, so a **single-agent** finding on one of them is included directly per the protocol's direct-inclusion exceptions and never reaches Step G. A **Codex-only** finding on the same criteria still reaches Step G, on the protocol's stated symmetry.

Everything else is inherited from the protocol: default REFUTED, 2-of-2 to include, one REFUTED discards, `READ FAILED:` retried rather than counted as a refutation, and the batched design form — **one verifier pair for the whole set**, emitting one `VERDICT: <ID> CONFIRMED|REFUTED` line per finding.

## Output Format

```markdown
# Spec Review

**Status:** APPROVED  (or CHANGES REQUESTED / REJECTED)

**Subject:** <spec title>
**Spec type:** appendix | main
**Assessment:** ✅ Approve | ⚠️ Request Changes | ❌ Reject
**Codex:** ✓ ran | ✗ not run — <reason if skipped>
**spec-verify:** <PASS/FAIL/SKIP counts, or "not applicable — main spec">
**Step G:** <N> eligible → <C> confirmed, <R> refuted, <U> unparseable

## Findings (<N total — consensus of 3 reviewers>)

### Blocker
- **B1** [SP-9] The sections named here are absent from the spec: <list>   (omit this subsection when there is no blocker)

### Critical
- **C1** [criterion] What falls short, located by spec type — on an appendix spec the §2 claim and the row its `Verified by` names; on a main spec the §2 or §3 requirement and the mechanism actually in use

### High
- **H1** [criterion] Description...

### Medium
- **M1** [criterion] Description...

### Low
- **L1** [criterion] Description...

## Reverified Findings

Single-agent Claude findings and Codex-only findings that survived Step G adversarial reverification — both verifiers returned `VERDICT: CONFIRMED`. These carry the same weight as consensus findings and count toward the assessment. Include even if 0 — write "None."

- **V1** [severity] [Reverified] Description...

## Recommendation
<required actions — each naming what falls short in that spec type's terms: the claim and its row on an appendix spec, the requirement identifier on a main spec>
```

IDs are prefixed by severity in `## Findings` (B = Blocker, C = Critical, H = High, M = Medium, L = Low) and by `V` in `## Reverified Findings`. Number sequentially within each section. IDs are stable within a review session.

**A confirmed SP-9 blocker is filed under `## Findings` → `### Blocker` whatever its provenance** — consensus, single-agent direct inclusion, or a Codex-only finding that survived Step G. Never as a `V` entry in `## Reverified Findings`: a blocker carries no severity in the ladder, so a bar reading Critical, High and Medium counts it as zero of each and returns `APPROVED` for the spec it was raised against.

## Assessment

- ✅ **Approve:** zero Critical, zero High and zero Medium **across `## Findings` and `## Reverified Findings` combined** — reverified findings carry the same weight, so an approval that ignores them is wrong. Sets the spec's `**Status:**` field per Step 2 item 3.
- ⚠️ **Request Changes:** one or more High or Medium findings → fix and re-run.
- ❌ **Reject:** one or more Critical findings → the spec is re-authored.

**An SP-9 blocker forces at least `CHANGES REQUESTED` whatever those counts are, and heads `## Findings`.** It sets a floor, not a ceiling: a Critical finding alongside it still escalates the same review to `REJECTED`. The structural outcome is a blocker rather than a finding, so a bar that counts only Critical/High/Medium findings would report `APPROVED` for a spec with no numbered sections at all.

## Critical Rule

**A spec reaches `Approved` only through this command.** The field records a review, not the author's decision that the document was done.
