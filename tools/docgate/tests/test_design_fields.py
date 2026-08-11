"""The four design-field counters: COST, MISSES, FROM, and UNTAGGED.

Case identifiers in the test names match the entries in the observed-failure ledger at
planning/genai-automations/mechanism-proportionality/step-1-cost-column, so each
ledger entry's Test line still resolves.
"""

from __future__ import annotations

import random
import string

import pytest

from conftest import WORDS, detail_rows, field, summary
from docgate.metrics import (
    FROM_VALUE_KINDS,
    REGISTER_DETECTOR_LIST,
    REGISTER_DETECTORS,
    _from_value_is_valid,
)

SLOT7_CASES = [
    (
        "U1 two complete option blocks",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** none\n\n"
        "### Option B\n**Cost:** ~20 LOC\n**Misses:** FR-1\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U2 option block with Pros/Cons only",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** x\n**Cons:** y\n",
        ("1", "0", "0", "0"),
    ),
    (
        "U3 option block with Cost and no Misses",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n",
        ("0", "1", "0", "0"),
    ),
    (
        "U4 option block with Misses and no Cost",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Misses:** none\n",
        ("1", "0", "0", "0"),
    ),
    (
        "U5 Misses label with no value",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:**\n",
        ("0", "1", "0", "0"),
    ),
    (
        "U6 two blocks, second Cost-only",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n\n"
        "### Option B\n**Cost:** ~20\n",
        ("0", "1", "0", "0"),
    ),
    (
        "U7 H4 inside a complete option block",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n"
        "#### Sub-heading\nmore text\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U8 H3 with no Cost outside slot 7",
        "## 5. Detailed Design\n\n### Sub heading\nsome text\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U9 the only Cost line sits inside a fence",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n```\n**Cost:** ~10 LOC\n```\n"
        "**Misses:** none\n",
        ("1", "0", "0", "0"),
    ),
    (
        "U10 section 7 omitted from the document entirely",
        "## 5. Detailed Design\n\nno trade-offs here\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U11 section 7 present, options as bold lines and H4s",
        "## 7. Trade-offs and Alternatives\n\n**Option A**\n**Cost:** ~10\n**Misses:** none\n\n"
        "#### Option B\n**Cost:** ~10\n**Misses:** none\n\n## 8. Open Questions\n\n*(None)*\n",
        ("1", "0", "0", "0"),
    ),
    (
        "U26 a clean document prints all four counters as zero",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10\n**Misses:** none\n",
        ("0", "0", "0", "0"),
    ),
    # A bold MENTION in Pros/Cons prose must not satisfy or spoof the gate.
    (
        "H1a a Misses: mention in Cons prose does not satisfy a missing Misses: field",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n"
        "**Cons:** this **Misses:** nothing critical\n",
        ("0", "1", "0", "0"),
    ),
    (
        "H1b a Cost: mention in Pros prose does not satisfy a missing Cost: field",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "**Pros:** reuses the existing **Cost:** tracking mechanism\n**Cons:** slower\n",
        ("1", "0", "0", "0"),
    ),
    # H1a and H1b in table form. Labels are anchored at CELL start, so the same bold
    # mention that must not satisfy the gate on a plain line must not satisfy it in a cell
    # either — and a table is where Pros/Cons prose most often lives.
    (
        "H1c a Cost: mention mid-cell does not satisfy a missing Cost: field",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| fast | reuses the existing **Cost:** tracking mechanism |\n",
        ("1", "0", "0", "0"),
    ),
    (
        "H1d a Misses: mention mid-cell does not satisfy a missing Misses: value",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| **Cost:** ~10 LOC | this option **Misses:** nothing critical |\n",
        ("0", "1", "0", "0"),
    ),
    # The same cell-start anchoring on the OTHER side of the test: the adjacent cell is
    # rejected as a value only when it IS a label, so a mid-cell mention inside it must
    # leave it usable. Testing the label cells alone cannot tell those two apart.
    (
        "H1e a Cost: mention inside the adjacent cell does not disqualify it as the value",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| **Cost:** ~1 LOC | **Misses:** | tracked in the **Cost:** column |\n",
        ("0", "0", "0", "0"),
    ),
    # Anchoring the two fields at line start regressed every form that puts something
    # before the label: a list marker, a blockquote marker, or a table pipe.
    (
        "M1a Cost and Misses written as list items are still recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n- **Cost:** ~10 LOC\n"
        "- **Misses:** none\n",
        ("0", "0", "0", "0"),
    ),
    (
        "M1b a list-item Cost paired with a plain-line Misses are both recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n- **Cost:** ~10 LOC\n"
        "**Misses:** none\n",
        ("0", "0", "0", "0"),
    ),
    (
        "M1c Cost and Misses inside a blockquote are still recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n> **Cost:** ~10 LOC\n"
        "> **Misses:** none\n",
        ("0", "0", "0", "0"),
    ),
    (
        "M1d Cost and Misses written as table cells are still recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** ~10 LOC | prod |\n"
        "|---|---|\n| **Misses:** none | - |\n",
        ("0", "0", "0", "0"),
    ),
    (
        "M5 Cost and Misses indented with plain whitespace are recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n  **Cost:** ~10 LOC\n"
        "  **Misses:** none\n",
        ("0", "0", "0", "0"),
    ),
    # The table analogue of U5: the label is present as a cell, the value cell empty.
    (
        "H2 a Misses table cell with an empty value blocks",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | ~10 LOC |\n"
        "| **Misses:** | |\n",
        ("0", "1", "0", "0"),
    ),
    # D1 is H2's positive counterpart: the same two-column shape with the value cell
    # populated. H2 alone cannot tell a truncation bug from a working blocker.
    (
        "D1 a Misses table cell with the value in a separate populated cell reads clean",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | ~10 LOC |\n"
        "| **Misses:** | none |\n",
        ("0", "0", "0", "0"),
    ),
    # A pipe on a plain line is document content, never a cell boundary.
    (
        "D2 a plain-line Misses: value containing a pipe is not cut at it",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n"
        "**Misses:** | FR-1\n",
        ("0", "0", "0", "0"),
    ),
    # D2b discriminates where D2 cannot: read as a table cell "|" strips to empty, read
    # as plain content it is non-empty. Only the untreated reading is clean.
    (
        "D2b a plain-line Misses: value that is only a pipe is not read as an empty cell",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** |\n",
        ("0", "0", "0", "0"),
    ),
    # A single leading-pipe strip could only ever see the field opening the FIRST cell.
    (
        "D6a Cost and Misses sharing one table row with inline values are both recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| **Cost:** ~1 LOC | **Misses:** none |\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D6b the label-row/value-row table form is recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n"
        "| ~1 LOC | none |\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D6c Misses before Cost in one row is still recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| **Misses:** none | **Cost:** ~1 LOC |\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D6d a three-cell row with both labels past cell 1 is still recognised",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n"
        "| Option | **Cost:** ~1 LOC | **Misses:** none |\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D6e an empty Misses value in a non-first cell still blocks",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** ~1 LOC | **Misses:** |\n",
        ("0", "1", "0", "0"),
    ),
    # Two label-only cells side by side are not a label/value pair.
    (
        "D6f a bare Misses label immediately followed by a bare Cost label still blocks",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Misses:** | **Cost:** ~5 LOC |\n",
        ("0", "1", "0", "0"),
    ),
    (
        "D6g a pending column resolved against another bare label still blocks",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n"
        "| ~1 LOC | **Misses:** |\n",
        ("0", "1", "0", "0"),
    ),
    # The cross-row lookahead is bounded to exactly one row, consumed whether it resolves
    # or not: unbounded lookahead risks a later, unrelated row supplying the value.
    (
        "D6h an intervening row breaks the one-row cross-row lookahead",
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n"
        "| a | |\n| ~1 LOC | none |\n",
        ("0", "1", "0", "0"),
    ),
]

SLOT3_CASES = [
    (
        "U12 one bullet per accepted From value",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** ticket 464\n- item two — **From:** incident 2026-08-06\n"
        "- item three — **From:** decision 2026-08-06\n- item four — **From:** spec RFC 7230\n"
        "- item five — **From:** analysis\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U13 unrecognised first token",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n- item — **From:** hunch\n",
        ("0", "0", "1", "0"),
    ),
    (
        "U14 incident with a non-ISO date",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** incident yesterday\n",
        ("0", "0", "1", "0"),
    ),
    (
        "U15 spec and ticket each with no name",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** spec\n- item two — **From:** ticket\n",
        ("0", "0", "2", "0"),
    ),
    (
        "U16 decision date followed by free prose",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** decision 2026-08-06 — the user chose this\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U17 bold label twice on one bullet, first invalid",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** hunch **From:** analysis\n",
        ("0", "0", "1", "0"),
    ),
    # U17 pairs one invalid label with one valid, so a first-match, last-match, or
    # any-single-match rule all report the same 1. Two invalid labels distinguish them.
    (
        "M1 two invalid From labels on one bullet are both counted",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** hunch **From:** nonsense\n",
        ("0", "0", "2", "0"),
    ),
    (
        "M7 a From: label with no value after it is invalid, not merely absent",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n- item — **From:**\n",
        ("0", "0", "1", "0"),
    ),
    (
        "U18 From tag and untagged bullets outside slot 3",
        "## 5. Detailed Design\n\n**From:** hunch\n\n**Functional Requirements:**\n"
        "- untagged one\n- untagged two\n",
        ("0", "0", "0", "0"),
    ),
    (
        "U19 From tag inside a table row in slot 3",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n\n"
        "| col | **From:** hunch |\n|---|---|\n",
        ("0", "0", "1", "0"),
    ),
    (
        "U20 untagged Constraint bullet plus Context Files and Verification bullets",
        "## 3. Implementation Context\n\n**Constraints:**\n- untagged constraint\n\n"
        "**Context Files:**\n- path/to/file\n\n**Verification:**\n- some verification bullet\n",
        ("0", "0", "0", "1"),
    ),
    (
        "U21 line-start From plus From on a Context Files bullet",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n**From:** analysis\n\n"
        "**Context Files:**\n- path/to/file **From:** ticket 464\n",
        ("0", "0", "2", "0"),
    ),
    (
        "U22 inline bold span mid-bullet is not a group opener",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1: declares `**Cost:**` and `**Misses:**` fields — **From:** decision 2026-08-06\n"
        "- FR-2: untagged requirement text\n",
        ("0", "0", "0", "1"),
    ),
    (
        "U27 untagged bullets under both Functional and Non-Functional Requirements",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n- untagged FR\n\n"
        "**Non-Functional Requirements:**\n- untagged NFR one\n- untagged NFR two\n",
        ("0", "0", "0", "3"),
    ),
    # Three malformed opener shapes never open a scanned group, so the untagged bullets
    # beneath each would otherwise be invisible and the section read as fully tagged.
    (
        "U28a a heading-level Functional Requirements opener warns once",
        "## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n",
        ("0", "0", "0", "1"),
    ),
    (
        "U28b a bulleted Functional Requirements opener warns once",
        "## 3. Implementation Context\n\n- **Functional Requirements:**\n- untagged two\n",
        ("0", "0", "0", "1"),
    ),
    (
        "H1 a tagged spaced-colon group yields exactly one warning and FROM zero",
        "## 3. Implementation Context\n\n**Functional Requirements :**\n"
        "- FR-1: something — **From:** analysis\n",
        ("0", "0", "0", "1"),
    ),
    # markdown_parser.py strips both ends of a captured label, so padding on either side
    # is collected as a genuine requirement group in production.
    (
        "D5a a leading-space opener alone with an untagged bullet warns once",
        "## 3. Implementation Context\n\n** Functional Requirements:**\n- untagged one\n",
        ("0", "0", "0", "1"),
    ),
    (
        "D5b a leading-space opener after a valid group still warns once",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1 — **From:** analysis\n\n"
        "** Non-Functional Requirements:**\n- untagged nfr\n",
        ("0", "0", "0", "1"),
    ),
    (
        "D5d a both-sides-padded opener warns once",
        "## 3. Implementation Context\n\n** Functional Requirements :**\n- untagged one\n",
        ("0", "0", "0", "1"),
    ),
    # The widened near-miss test also matches zero padding, so this pins that the exact
    # form still takes the valid path.
    (
        "D5e the exact valid form still takes the valid path with no opener warning",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1 — **From:** analysis\n",
        ("0", "0", "0", "0"),
    ),
    (
        "M2 a spaced-colon group after a valid one is still reported",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** ticket 464\n\n**Non-Functional Requirements :**\n- untagged nfr\n",
        ("0", "0", "0", "1"),
    ),
    # A malformed opener must report even when a valid group opened earlier in the same
    # section; the correctly tagged bullet beneath it proves the hit is for the opener
    # shape itself, not a smuggled-in missing tag.
    (
        "D3a a heading-level opener after a valid group is still reported",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1: ok — **From:** analysis\n\n#### Non-Functional Requirements\n"
        "- NFR-1: tagged fine — **From:** analysis\n",
        ("0", "0", "0", "1"),
    ),
    (
        "D3b a section carrying only Context Files and a bullet reports zero",
        "## 3. Implementation Context\n\n**Context Files:**\n- path/to/file\n",
        ("0", "0", "0", "0"),
    ),
    # Detection fires the instant the malformed heading is seen, so it does not matter
    # whether a bullet follows at all.
    (
        "D3c a heading-level opener is reported even when its requirements are table rows",
        "## 3. Implementation Context\n\n#### Functional Requirements\n\n| req | tag |\n|---|---|\n"
        "| FR-1 | analysis |\n",
        ("0", "0", "0", "1"),
    ),
    # A bulleted opener is itself a list item, so without excluding it from the
    # per-bullet sweep it would be counted twice under a still-open earlier group.
    (
        "D3d a bulleted opener under a still-open earlier group is counted once",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1 — **From:** ticket 464\n- **Non-Functional Requirements:**\n"
        "- FR-2 — **From:** analysis\n",
        ("0", "0", "0", "1"),
    ),
    (
        "D3e an unrelated H3+ sub-heading in a fully-tagged section 3 is not flagged",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** ticket 464\n\n### Background\n\nsome prose explaining context.\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D3f a bulleted Context Files label is not a bulleted requirement opener",
        "## 3. Implementation Context\n\n- **Context Files:**\n- path/to/file\n",
        ("0", "0", "0", "0"),
    ),
    (
        "D3g a heading matching a requirement label outside section 3 is not flagged",
        "## 5. Detailed Design\n\nsome prose\n\n### Functional Requirements\n\nmore prose\n",
        ("0", "0", "0", "0"),
    ),
    (
        "H6b an indented Context Files heading still closes the group",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** decision 2026-08-06\n\n  **Context Files:**\n"
        "- path/to/file **From:** ticket 464\n",
        ("0", "0", "1", "0"),
    ),
    # A section with no requirement bullets at all must report zero, not a false warning:
    # nothing was examined, so nothing can be missing a tag.
    (
        "a section 3 with no requirement bullets at all reports zero",
        "## 3. Implementation Context\n\nSome prose describing the module, no bullets anywhere.\n",
        ("0", "0", "0", "0"),
    ),
    # Per-section state must not leak across a heading transition.
    (
        "the bullet sweep does not leak from an unclosed group into the next slot-3 section",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** ticket 464\n\n## More Implementation Context\n\n- untagged bullet\n\n"
        "## 4. Architecture Overview\n\nmore text\n",
        ("0", "0", "0", "0"),
    ),
    (
        "a malformed opener in one slot-3 section does not silence the next",
        "## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n\n"
        "## Extra Implementation Context\n\nJust prose here, no bullets at all.\n\n"
        "## 4. Architecture Overview\n\nmore text\n",
        ("0", "0", "0", "1"),
    ),
    # Every real design.md has §3 followed by §4, so a closer exercised only at EOF is a
    # silent hole for the shape that actually occurs.
    (
        "H1 a slot-3 section closed by a following heading is still closed",
        "## 3. Implementation Context\n\n#### Functional Requirements\n- untagged one\n\n"
        "## 4. Architecture Overview\n\nsome text here\n",
        ("0", "0", "0", "1"),
    ),
    # All four padded From: spellings open a FIELD_PATTERN line and break the parser
    # identically; recognising only the exact one downgrades a value that needs fixing
    # to a bullet that predates the field.
    (
        "D8f an inline padded From: tag is recognised as a tag with an unrecognised value",
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1: alpha — **From :** hunch\n",
        ("0", "0", "1", "0"),
    ),
    (
        "D8g an NBSP-padded group-opener label is still the near-miss opener",
        "## 3. Implementation Context\n\n** Functional Requirements:**\n- untagged one\n",
        ("0", "0", "0", "1"),
    ),
]


@pytest.mark.parametrize("name,body,want", SLOT7_CASES, ids=[c[0] for c in SLOT7_CASES])
def test_slot7_counters(fields, name: str, body: str, want: tuple[str, str, str, str]) -> None:
    assert fields(body) == want


@pytest.mark.parametrize("name,body,want", SLOT3_CASES, ids=[c[0] for c in SLOT3_CASES])
def test_slot3_counters(fields, name: str, body: str, want: tuple[str, str, str, str]) -> None:
    assert fields(body) == want


def test_D6i_a_pending_column_does_not_leak_into_the_next_option_block(measure) -> None:
    # Block B has no Misses: label at all, so it must warn on its own account rather than
    # read as accidentally satisfied by block A's unresolved column.
    body = (
        "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n\n"
        "### Option B\n| **Cost:** ~2 LOC | foo |\n"
    )

    output = measure(body).output

    assert summary(output, "COST") == "0"
    assert summary(output, "MISSES") == "2"


def test_H4_a_slot7_close_at_a_section_boundary_attributes_the_closed_section(measure) -> None:
    # A close that fires at the right count but with the section already overwritten is
    # invisible to a bare counter check.
    body = (
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Misses:** none\n\n"
        "## 8. Open Questions\n\n*(None)*\n"
    )

    output = measure(body).output

    assert summary(output, "COST") == "1"
    assert summary(output, "MISSES") == "0"
    assert detail_rows(output)[0][0] == "7. Trade-offs and Alternatives"


def test_H2_a_slot7_section_ending_the_document_is_still_closed(measure) -> None:
    # commands/design.md permits omitting §8, so §7-at-EOF is a real production shape.
    body = "## 7. Trade-offs and Alternatives\n\n**Option A**\n**Cost:** ~10\n**Misses:** none\n"

    output = measure(body).output

    assert summary(output, "COST") == "1"
    assert summary(output, "MISSES") == "0"


def test_H3_the_slot7_block_flag_does_not_leak_across_two_slot7_sections(measure) -> None:
    # If the reset leaks, section 2 inherits section 1's opened block and its own close
    # finds a block that was never opened here at all.
    body = (
        "## 7. Trade-offs Analysis\n\n### Option A\n**Cost:** ~10 LOC\n**Misses:** none\n\n"
        "## Alternative Approaches Considered\n\n**Option B**\n**Cost:** ~5 LOC\n"
        "**Misses:** none\n\n## 8. Open Questions\n\n*(None)*\n"
    )

    output = measure(body).output

    assert summary(output, "COST") == "1"
    assert summary(output, "MISSES") == "0"
    assert detail_rows(output)[0][0] == "Alternative Approaches Considered"


def test_M3_an_orphaned_tag_is_attributed_to_the_closing_label(measure) -> None:
    # Pointing at the tagged bullet instead reads as "strip this tag", the wrong fix.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** ticket 464\n\n**Notes:**\n- item two — **From:** ticket 465\n"
    )

    output = measure(body).output

    assert summary(output, "FROM") == "1"
    assert detail_rows(output)[0][1:] == [
        "**Notes:**",
        "requirement group closed by this label; a From: tag below it is outside the group",
    ]


def test_H6a_an_indented_From_label_opening_its_line_is_caught_as_misplaced(measure) -> None:
    # markdown_parser.py strips leading whitespace before matching, so an indented label
    # still breaks the parser while escaping an unindented-only anchor.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n  **From:** analysis\n"
        "- untagged one\n- untagged two\n"
    )

    output = measure(body).output

    assert summary(output, "FROM") == "1"
    assert summary(output, "UNTAGGED") == "2"
    assert any("must be inline" in row[2] for row in detail_rows(output))


def test_H6c_an_indented_group_opener_is_recognised_not_papered_over(measure) -> None:
    # The count alone cannot tell "the opener is recognised and its bullet swept" from a
    # section-level fallback firing instead; the locator and reason can.
    body = (
        "## 3. Implementation Context\n\n  **Functional Requirements:**\n- untagged bullet here\n"
    )

    output = measure(body).output

    assert summary(output, "UNTAGGED") == "1"
    assert detail_rows(output)[0][1:] == [
        "untagged bullet here",
        "requirement bullet with no From: tag",
    ]


def test_U28c_a_spaced_colon_opener_warns_exactly_once(measure) -> None:
    body = "## 3. Implementation Context\n\n**Functional Requirements :**\n- untagged three\n"

    output = measure(body).output

    reasons = [row[2] for row in detail_rows(output)]
    assert summary(output, "UNTAGGED") == "1"
    assert summary(output, "FROM") == "0"
    assert any("whitespace around the label" in reason for reason in reasons)
    assert not any("no requirement group opened" in reason for reason in reasons)


def test_D5c_a_padded_opener_after_a_valid_group_does_not_misattribute_a_valid_tag(measure) -> None:
    # A subtly wrong fix could land on FROM: 0 by accident while leaving the wrong
    # attribution mechanism in place, so the reason's absence is asserted too.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- FR-1 — **From:** analysis\n\n"
        "** Non-Functional Requirements:**\n- NFR-1 — **From:** analysis\n"
    )

    output = measure(body).output

    assert summary(output, "UNTAGGED") == "1"
    assert summary(output, "FROM") == "0"
    assert "closed by this label" not in output


def test_D5f_a_generic_label_with_no_group_open_attributes_to_absence(measure) -> None:
    # Context Files closed nothing here because nothing was open; "analysis" is a valid
    # value deliberately, so only PLACEMENT is under test.
    body = (
        "## 3. Implementation Context\n\n**Context Files:**\n- path/to/file — **From:** analysis\n"
    )

    output = measure(body).output

    assert summary(output, "FROM") == "1"
    assert summary(output, "UNTAGGED") == "0"
    assert detail_rows(output)[0][2] == "From: label outside a requirement group"


def test_the_group_closer_does_not_leak_from_one_slot3_section_into_the_next(measure) -> None:
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** ticket 464\n\n**Context Files:**\n- path/to/file\n\n"
        "## Extra Implementation Context\n\n- bullet text **From:** hunch\n"
    )

    output = measure(body).output

    assert summary(output, "FROM") == "1"
    assert detail_rows(output)[0][1:] == [
        "bullet text **From:** hunch",
        "From: label outside a requirement group",
    ]


def test_H3_a_malformed_opener_in_a_second_slot3_section_is_attributed_there(measure) -> None:
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item — **From:** ticket 464\n\n## More Implementation Context Details\n\n"
        "#### Functional Requirements\n- untagged one\n\n## 4. Architecture Overview\n\n"
        "some text here\n"
    )

    output = measure(body).output

    assert summary(output, "UNTAGGED") == "1"
    assert detail_rows(output)[0][0] == "More Implementation Context Details"


PADDED_FROM_OPENERS = [
    ("D8a leading space inside the label", "** From:** analysis"),
    ("D8b trailing space inside the label", "**From :** analysis"),
    ("D8c both sides padded", "** From :** analysis"),
    ("D8d indentation crossed with internal padding", "  ** From:** analysis"),
]


@pytest.mark.parametrize(
    "name,label_line", PADDED_FROM_OPENERS, ids=[c[0] for c in PADDED_FROM_OPENERS]
)
def test_a_padded_From_opener_is_caught_as_misplaced(measure, name: str, label_line: str) -> None:
    body = (
        f"## 3. Implementation Context\n\n**Functional Requirements:**\n{label_line}\n"
        "- untagged one\n- untagged two\n"
    )

    output = measure(body).output

    assert summary(output, "FROM") == "1"
    assert summary(output, "UNTAGGED") == "2"
    assert any("must be inline" in row[2] for row in detail_rows(output))


def test_D8e_every_padded_From_opener_reports_the_identical_reason(measure) -> None:
    # Both go through the identical branch now, so their reason text must be byte-equal
    # to the exact form's, not merely also contain "must be inline".
    def reason(label_line: str) -> str:
        body = (
            f"## 3. Implementation Context\n\n**Functional Requirements:**\n{label_line}\n"
            "- untagged one\n"
        )
        rows = detail_rows(measure(body).output)
        return next(row[2] for row in rows if "must be inline" in row[2])

    exact = reason("**From:** analysis")
    assert exact
    for padded in ("** From:** analysis", "**From :** analysis", "** From :** analysis"):
        assert reason(padded) == exact


def test_H5_the_untagged_summary_line_carries_its_exact_wording(measure) -> None:
    # Reverting the widened wording to the old bullet-only text left every numeric
    # assertion green; a non-bullet hit is used so the line provably describes THIS hit.
    body = "## 3. Implementation Context\n\n**Functional Requirements :**\n- untagged bullet\n"

    output = measure(body).output

    assert (
        "UNTAGGED: 1 requirement bullet(s) with no From tag, "
        "or malformed requirement-group opener(s)" in output
    )


def test_U24_the_detail_block_carries_one_line_per_hit_with_distinct_reasons(measure) -> None:
    # The detail block is the entire operator-facing output of the feature: emitting it
    # with an empty field, or the same reason for every hit, would still pass a shape
    # check alone.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** ticket 464\n- item two untagged\n\n**From:** hunch\n\n"
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** x\n**Cons:** y\n\n"
        "### Option B\n**Cost:** ~10 LOC\n"
    )

    rows = detail_rows(measure(body).output)

    assert len(rows) == 4
    assert all(len(row) == 3 for row in rows)
    assert all(all(cell for cell in row) for row in rows)
    assert not any(row[1].isdigit() for row in rows)
    assert len({row[2] for row in rows}) == 4


def test_U25_the_field_scan_does_not_consume_its_line(measure) -> None:
    # Every pinned target and ceiling stays valid only while the field scans leave the
    # word count alone; the counts below are hand-computed.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** ticket 464\n\n## 7. Trade-offs and Alternatives\n\n"
        "### Option A\n**Cost:** ~10 LOC production\n**Misses:** none\n"
    )

    output = measure(body).output

    assert field(output, "3. Implementation Context", WORDS) == "7"
    assert field(output, "7. Trade-offs and Alternatives", WORDS) == "6"


def _rejected_token_sample(count: int = 400) -> list[str]:
    """Return deterministic identifiers of varied length, none an accepted kind.

    Generated rather than listed: an enumerated probe set can only ever miss the one token
    a stray acceptance path was spelled with, which is how a `tolower(first) ~` bypass
    reached production past the enumerated version of these two tests.
    """
    generator = random.Random(20260810)
    tokens: set[str] = set()
    while len(tokens) < count:
        length = generator.randint(1, 12)
        token = "".join(generator.choice(string.ascii_lowercase) for _ in range(length))
        if token not in FROM_VALUE_KINDS:
            tokens.add(token)
    return sorted(tokens)


# Shapes a stray acceptance path is most likely to be spelled with. The hand-written half
# is the accepted kinds recased plus words an author would plausibly write in their place.
# The derived half exists because the random sample above is drawn from the whole lowercase
# alphabet and so never lands within one edit of a declared key: a lookup rewritten as a
# prefix, suffix, or case-folded match is accepted by the tokens below and by nothing else
# in the probe set.
NEAR_MISS_TOKENS = [
    "Analysis",
    "ANALYSIS",
    "Ticket",
    "INCIDENT",
    "analyses",
    "analysing",
    "rumour",
    "postmortem",
    "assumption",
    "guess",
    "memo",
    "",
] + [
    spelling
    for kind in FROM_VALUE_KINDS
    for spelling in (kind + "x", kind[:-1], kind.upper(), kind.title(), kind + "s")
]


def test_I6_the_accepted_From_values_come_only_from_the_declared_mapping() -> None:
    # The validator reads FROM_VALUE_KINDS and nothing else, so a sixth accepted value
    # cannot be smuggled in through a comparison spelled some other way. Both directions
    # are asserted: every declared kind accepts, and nothing outside the mapping does.
    probes = list(FROM_VALUE_KINDS) + _rejected_token_sample() + NEAR_MISS_TOKENS

    accepted = {token for token in probes if _from_value_is_valid(f"{token} 2026-08-06")}

    assert accepted == set(FROM_VALUE_KINDS)


def test_M9_no_first_token_outside_the_declared_mapping_is_accepted() -> None:
    # The probes are a random lowercase sample plus tokens derived from the declared keys,
    # so what this establishes is bounded: an acceptance path spelled as a prefix, suffix,
    # or case-folded match of a declared key is caught, and so is one keying off the tag's
    # length or word count, since free trailing prose is appended. A path keyed on some
    # other property of the value can still escape it.
    probes = _rejected_token_sample() + NEAR_MISS_TOKENS

    accepted = [token for token in probes if _from_value_is_valid(f"{token} 2026-08-06 extra")]

    assert accepted == []
    assert not _from_value_is_valid("")


def test_the_register_detector_list_is_published_as_one_joined_string() -> None:
    # Two prose copies publish the joined form; a consistency suite compares them against
    # this constant rather than re-deriving the list.
    assert REGISTER_DETECTOR_LIST == "|".join(REGISTER_DETECTORS)
    assert REGISTER_DETECTOR_LIST.startswith("deliberately|intentionally|by design|")


def test_a_pending_column_past_the_next_rows_cells_still_blocks(measure) -> None:
    # The remembered column may not exist in the following row at all; a shorter row
    # must break the chain rather than index past its end.
    body = "## 7. Trade-offs and Alternatives\n\n### Option A\n| **Cost:** | **Misses:** |\n| a\n"

    output = measure(body).output

    assert summary(output, "COST") == "0"
    assert summary(output, "MISSES") == "1"
