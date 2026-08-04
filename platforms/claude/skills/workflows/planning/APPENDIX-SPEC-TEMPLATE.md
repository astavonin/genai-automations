# Appendix Spec — A<N> <Page Title>

**Page:** `A<N>-<slug>`
**Dependent articles:** <from the Blocks column in planning/book/appendix/status.md>
**Evidence sources:** <kernel docs / datasheets / specs actually consulted>
**Device reachable:** yes | no — <access method, or what blocked it>
**Status:** Draft | Approved

---

## 1. Scope

### Concepts carried

- ...

### Deferred

Named so a reader is not left hunting. Say where each goes.

- ...

### Depth required by dependents

Depth is set by what the dependent articles need, not by what is interesting. One row per article in the Blocks column.

| Article | Needs from this page | Depth |
|---------|---------------------|-------|
| 1/04 | ... | walking-tour / full reference |

---

## 2. Claims

Every assertion the page will make, each with the authoritative source behind it. Numbers, alignments, device names, register widths, format layouts, and behavioural guarantees are all claims. Prose that asserts nothing checkable does not belong here.

Each row's **Verified by** is a §5 row ID. A claim with no §5 row is unverified no matter how confident it reads.

| ID | Claim | Source | Verified by |
|----|-------|--------|-------------|
| C1 | ... | <doc + section, or "on-device measurement"> | V1 |

**Unverified claims.** Carry them; never drop them and never soften them into something that sounds checked. `/write` propagates these into `brief.md` §9 and Web-Claude must mark them in the draft.

| ID | Claim | What is missing |
|----|-------|-----------------|
| C7 | ... | `[UNVERIFIED: no device access]` |

---

## 3. Source Requirements

Pass/fail rules for this page. Phrased so a reviewer can fail a row, not aspire to it.

- **SR1:** No claim from memory. Every row in the **verified** §2 claims table cites a document section, a source path, or a §5 measurement. Does not apply to the unverified claims table below — its `What is missing` cell is the reason the row is unverified, not a gap this rule requires filling.
- **SR2:** Hardware claims are verified against the target device. A claim about what a SoC block does is not established by reasoning about the SoC.
- **SR3:** Vendor claims cite datasheet or TRM plus section number. "The datasheet says" without a section is not a citation.
- **SR4:** Specification claims cite the numbered section (RFC §N, ITU-T §N, ISO clause N).
- **SR5:** A device or peripheral is named only after its presence is confirmed. Absence of evidence is recorded as absence, not omitted.
- **SR6:** The claimed value or token appears literally in the §5 captured output, or the Conclusion names the line that rules the claim in or out. `ls /dev/video*` returning node numbers does not establish which blocks those nodes are — that needs `v4l2-ctl --list-devices`.
- **SR7:** Every §5 row records where and when it ran. An unattributed paste cannot be told from a recollection.
- **SR8:** Every claim ID appears in exactly one §2 table, and every `Verified by` names a §5 row whose `Establishes` lists that ID.

---

## 4. Terminology Contract

Terms this page defines that dependent articles then use. These bind: a main article citing this page for a definition must find the same definition here, and a later edit that changes one changes the other.

### `<term>`

**Definition:** ...
**Used by:** <articles>
**Invariants:**
- ...

---

## 5. Verification Procedure

The command or lookup that established each §2 claim, with its **actual captured output**. This is the section only a session with the hardware, the kernel tree, and the datasheets can produce — Web-Claude writes the prose and can verify none of it.

Indent captured output four spaces rather than fencing it, so a stray fence in the output cannot swallow the rest of the section.

### V1 — <what this establishes>

**Establishes:** C1, C2
**Method:** on-device | kernel source | documentation lookup | specification
**Ran on:** <target device and how reached, or "authoring host", or the document consulted>
**Run date:** <YYYY-MM-DD>

```bash
<exact command>
```

Output — mandatory for every method. For a documentation lookup, quote the passage and give its section or anchor; a bare file path establishes nothing.

    <captured output, indented four spaces>

**Conclusion:** <what the output rules in or out — name the line it turns on>

---

## Rules

- **Claims before sources.** Decide what must be true for the dependents, then find out whether it is. Writing down what the sources happen to say produces a page that is accurate and useless.
- **Run the check; do not recall the answer.** The failure this contract exists to stop is a confident, plausible, fabricated fact — a device that does not exist, an alignment that was never measured. Recall reproduces those perfectly.
- **A negative result is a result.** "No such device is present" is a claim worth recording, with the command that showed it. Absence found once and not written down gets re-fabricated later.
- **Prior research is not evidence.** An `analysis.md` in the same folder predates this contract. Re-verify anything carried across, and check the Known-defects table in `planning/book/appendix/status.md` first.
- **Numbered sections are load-bearing.** `/write` reads §2 and §5 as verified facts and §4 as binding definitions. Do not rename or renumber them.
- **The header's `**Status:** Draft | Approved` is a spec-authoring marker, not the review-gate marker `CLAUDE.md` §4 defines (`APPROVED | CHANGES REQUESTED | REJECTED`).** The two share the `**Status:**` prefix by convention with `SPEC-TEMPLATE.md`, which uses the identical field. `tests/verify-workflow-safety.sh` scopes its gate to review files by explicit path, not by scanning every `**Status:**` occurrence, so this field is inert to it today — do not repurpose it to carry a review-gate value, and do not assume a future gate expanding its file set would leave it alone.

## When to use

`/spec`, for an output path under `planning/book/appendix/issues/A<N>-<slug>/` — the `appendix` page type per `~/.claude/skills/workflows/page-type/SKILL.md`. For main articles with a companion implementation, use `SPEC-TEMPLATE.md` instead.
