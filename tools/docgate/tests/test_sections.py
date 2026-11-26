"""Section slotting, targets and ceilings, verdicts, share, and output shape."""

from __future__ import annotations

import pytest

from conftest import CEILING, REGISTER, SHARE, TARGET, VERDICT, WORDS, detail_rows, field, summary


def test_words_and_register_attribute_to_the_enclosing_section(measure) -> None:
    body = (
        "**Goal:** g\n\n## 1. Problem Statement\n\nalpha beta\n\n"
        "## 5. Detailed Design\n\ngamma delta epsilon deliberately\n"
    )

    output = measure(body).output

    assert field(output, "(preamble)", WORDS) == "2"
    assert field(output, "1. Problem Statement", WORDS) == "2"
    assert field(output, "5. Detailed Design", WORDS) == "4"
    assert field(output, "5. Detailed Design", REGISTER) == "1"
    assert field(output, "1. Problem Statement", REGISTER) == "0"


def test_a_mid_document_h1_opens_its_own_section(measure) -> None:
    # Without this, prose under a mid-document H1 was attributed to the previous ## and
    # real config files reported one section holding four.
    body = "## Section A\nalpha beta\n# Top Level Two\ngamma delta epsilon\n## Section B\nzeta\n"

    output = measure(body).output

    assert field(output, "Section A", WORDS) == "2"
    assert field(output, "Top Level Two", WORDS) == "3"
    assert field(output, "Section B", WORDS) == "1"


def test_a_level_three_heading_rolls_up_into_its_parent(measure) -> None:
    body = "## 5. Detailed Design\nalpha beta\n### Sub-heading\ngamma delta\n"

    output = measure(body).output

    assert field(output, "5. Detailed Design", WORDS) == "4"
    assert field(output, "Sub-heading", WORDS) == ""


def test_a_declared_section_with_no_prose_reports_zero(measure) -> None:
    # For an Architecture Overview that is mostly a diagram, a missing row and a zero row
    # mean different things.
    output = measure("## 2. Goals and Non-Goals\n\n## 5. Detailed Design\n\nalpha\n").output

    assert field(output, "2. Goals and Non-Goals", WORDS) == "0"


def test_an_absent_preamble_adds_no_row(measure) -> None:
    output = measure("## 5. Detailed Design\n\nalpha\n").output

    assert field(output, "(preamble)", WORDS) == ""


def test_section_rows_follow_document_order(measure) -> None:
    output = measure("## Alpha\na\n## Beta\nb\n## Gamma\nc\n").output

    names = [
        line.split("\t")[0].rstrip()
        for line in output.splitlines()
        if len(line.split("\t")) == 7 and line.split("\t")[0].rstrip() in {"Alpha", "Beta", "Gamma"}
    ]
    assert names == ["Alpha", "Beta", "Gamma"]


def test_a_repeated_heading_gets_its_own_row(measure) -> None:
    body = "## Notes\nalpha\n## 5. Detailed Design\nbeta\n## Notes\ngamma delta\n"

    output = measure(body).output

    assert field(output, "Notes", WORDS) == "1"
    assert field(output, "Notes (2)", WORDS) == "2"


def test_closing_hash_headings_normalise_to_the_same_name(measure) -> None:
    output = measure("## 5. Detailed Design ##\nalpha\n").output

    assert field(output, "5. Detailed Design", WORDS) == "1"


def test_an_uncapped_section_shows_its_target_and_a_dash_ceiling(measure) -> None:
    output = measure("## 1. Problem Statement\nalpha beta\n").output

    assert field(output, "1. Problem Statement", TARGET) == "184"
    assert field(output, "1. Problem Statement", CEILING) == "-"
    assert field(output, "1. Problem Statement", VERDICT) == "ok"
    assert summary(output, "CEILING") == "0"


def test_over_target_but_under_ceiling_is_not_counted_by_ceiling(measure) -> None:
    output = measure("## 1. Problem Statement\n" + "word " * 190 + "\n").output

    assert field(output, "1. Problem Statement", VERDICT) == "over-target"
    assert summary(output, "CEILING") == "0"


def test_an_uncapped_section_never_blocks_however_large(measure) -> None:
    output = measure("## 1. Problem Statement\n" + "word " * 400 + "\n").output

    assert field(output, "1. Problem Statement", VERDICT) == "over-target"
    assert summary(output, "CEILING") == "0"


def test_a_capped_section_over_its_ceiling_blocks(measure) -> None:
    output = measure("## 6. Test Requirements\n" + "word " * 1800 + "\n").output

    assert field(output, "6. Test Requirements", CEILING) == "1754"
    assert field(output, "6. Test Requirements", VERDICT) == "OVER-CEILING"
    assert summary(output, "CEILING") == "1"


def test_a_multi_row_slot_shows_its_accumulated_total_beside_the_ceiling(measure) -> None:
    # Otherwise a small row reads OVER-CEILING with nothing on the line to explain it.
    body = (
        "## 6. Test Requirements\nalpha beta\n\n## 1. Problem Statement\ngamma\n\n"
        "## 6. Tests again\ndelta\n"
    )

    output = measure(body).output

    assert field(output, "6. Test Requirements", CEILING) == "3/1754"
    assert field(output, "1. Problem Statement", CEILING) == "-"


def test_splitting_a_capped_section_does_not_multiply_its_budget(measure) -> None:
    body = (
        "## 6. Test Requirements\n"
        + "word " * 1000
        + "\n\n## 6. Test Requirements — Part B\n"
        + "word " * 1000
        + "\n"
    )

    output = measure(body).output

    assert summary(output, "CEILING") == "1"
    # Every row of the slot reads the slot's accumulated verdict, not its own words. Each
    # row alone is under the 1754 ceiling, so a per-row reading would print over-target on
    # both and leave the author with no row saying the budget is blown.
    assert field(output, "6. Test Requirements", VERDICT) == "OVER-CEILING"
    assert field(output, "6. Test Requirements — Part B", VERDICT) == "OVER-CEILING"


def test_the_slot_five_section_over_its_ceiling_blocks(measure) -> None:
    # Slot 5 is the other capped slot and the one the corpus actually strains against, so
    # its ceiling needs its own pin — a suite pinning only slot 6's leaves this one free.
    output = measure("## 5. Detailed Design\n" + "word " * 5500 + "\n").output

    assert field(output, "5. Detailed Design", CEILING) == "5463"
    assert field(output, "5. Detailed Design", VERDICT) == "OVER-CEILING"
    assert summary(output, "CEILING") == "1"


def test_a_capped_section_exactly_at_its_ceiling_is_not_over_it(measure) -> None:
    # The ceiling is the largest acceptable size, not the smallest rejected one.
    output = measure("## 6. Test Requirements\n" + "word " * 1754 + "\n").output

    assert field(output, "6. Test Requirements", WORDS) == "1754"
    assert field(output, "6. Test Requirements", VERDICT) == "over-target"
    assert summary(output, "CEILING") == "0"


def test_the_document_ceiling_blocks_and_is_reported_on_the_total_row(measure) -> None:
    output = measure("word " * 8400 + "\n").output

    assert field(output, "TOTAL", TARGET) == "5800"
    assert field(output, "TOTAL", CEILING) == "8322"
    assert field(output, "TOTAL", VERDICT) == "OVER-CEILING"
    assert summary(output, "CEILING") == "1"


# Summary-line labels every seven-field-row check below skips — each opens a counter line,
# not a section row, so it is exempt from the seven-field shape the row assertion pins.
SUMMARY_LABELS = (
    "REGISTER",
    "CEILING",
    "TESTNAMES",
    "NOROW",
    "UNSLOTTED",
    "COST",
    "MISSES",
    "FROM",
    "UNTAGGED",
)


def assert_seven_field_rows(output: str) -> None:
    """Assert every section-row line of ``output`` splits into seven tab-separated fields.

    A label missing from either skip list below collapses a row to fewer fields for any
    caller reading columns.
    """
    for line in output.splitlines():
        if not line or line.startswith(
            ("==", " ", "register hits", "design-field hits", "test-identifier hits")
        ):
            continue
        if line.split(":")[0] in SUMMARY_LABELS:
            continue
        assert len(line.split("\t")) == 7, line


SLOT_CASES = [
    ("slot 1 target", "1. Problem Statement", "184"),
    ("slot 2 target", "2. Goals and Non-Goals", "283"),
    ("slot 3 target", "3. Implementation Context", "441"),
    ("slot 4 target", "4. Architecture Overview", "129"),
    ("slot 5 target", "5. Detailed Design", "4232"),
    ("slot 6 target", "6. Test Requirements", "877"),
    ("slot 7 target", "7. Trade-offs and Alternatives", "580"),
    ("slot 8 target", "8. Open Questions", "45"),
    # Older documents number Trade-offs §6 and Open Questions §7; the target must match
    # on content, not on the number.
    ("a 7-section-template heading matches by content", "6. Trade-offs and Alternatives", "580"),
    ("a section with no target reads a dash", "Appendix B", "-"),
    # A substring test put "Attestation" and "Contest Rules" in the Test slot.
    ("Attestation is not a Test section", "Appendix C. Attestation Log", "-"),
    ("Contest is not a Test section", "Contest Rules", "-"),
    ("Latest Design Decisions is a design section", "Latest Design Decisions", "4232"),
    ("Goalkeeper is not a Goals section", "Goalkeeper Metrics", "-"),
    ("Trade-offs outranks Testing", "7. Trade-offs and Alternatives for Testing", "580"),
    ("Testing matches the Test slot", "Testing Strategy", "877"),
    ("Design Decisions is a design section", "4. Design Decisions", "4232"),
    ("Open Items is an Open Questions section", "8. Open Items", "45"),
    # Slot terms are matched after punctuation folds to spaces. Every other slot-7 case
    # here spells "Alternatives", which matches without the fold, so these two carry it:
    # unfolded, the first slots nowhere and the second lands in slot 5 on the word Design.
    ("a hyphenated Trade-offs heading is slot 7", "Trade-offs & Considerations", "580"),
    ("Design Trade-offs is slot 7, not slot 5", "Design Trade-offs", "580"),
]


@pytest.mark.parametrize("name,heading,want", SLOT_CASES, ids=[c[0] for c in SLOT_CASES])
def test_section_slot_matching(measure, name: str, heading: str, want: str) -> None:
    output = measure(f"## {heading}\nalpha\n").output

    assert field(output, heading, TARGET) == want


NORMALISED_HEADING_CASES = [
    ("a double space still canonises", "5. Detailed  Design", "5. Detailed Design"),
    ("a tab in a heading still canonises", "5. Detailed\tDesign", "5. Detailed Design"),
]


@pytest.mark.parametrize(
    "name,heading,row", NORMALISED_HEADING_CASES, ids=[c[0] for c in NORMALISED_HEADING_CASES]
)
def test_a_normalised_heading_keeps_its_slot(measure, name: str, heading: str, row: str) -> None:
    output = measure(f"## {heading}\nalpha\n").output

    assert field(output, row, TARGET) == "4232"


def test_the_document_title_claims_no_slot(measure) -> None:
    # Five corpus titles matched the Test rule, two of them in documents with no test
    # section at all, dragging that slot down.
    body = "# Design — Smoke Test Baseline\n\n## 5. Detailed Design\n\nalpha\n"

    output = measure(body).output

    assert field(output, "Design — Smoke Test Baseline", TARGET) == "-"


def test_a_section_with_no_target_reads_a_dash_verdict(measure) -> None:
    output = measure("## Appendix B\nalpha\n").output

    assert field(output, "Appendix B", VERDICT) == "-"


def test_share_is_a_percentage_of_the_prose_total(measure) -> None:
    output = measure("## A\n\nalpha\n\n## B\n\nbeta gamma delta\n").output

    assert field(output, "A", SHARE) == "25.0%"
    assert field(output, "B", SHARE) == "75.0%"


def test_a_zero_total_document_keeps_its_columns_readable(measure) -> None:
    output = measure("## 2. Goals and Non-Goals\n").output

    assert field(output, "2. Goals and Non-Goals", WORDS) == "0"
    assert field(output, "2. Goals and Non-Goals", SHARE) == "-"
    assert field(output, "TOTAL", WORDS) == "0"


def test_an_unslotted_section_is_reported(measure) -> None:
    # A heading that matches no slot has no ceiling, so a large unslotted section is
    # invisible to the length gate. It must at least be reported.
    output = measure("## Feature-specific Section\n\nalpha beta gamma delta\n").output

    assert "UNSLOTTED: 1 section(s) holding 4 word(s)" in output


def test_an_unslotted_section_carrying_no_prose_is_not_reported(measure) -> None:
    # UNSLOTTED counts unbudgeted PROSE. A heading whose whole body is a fenced block
    # carries none, so it must read the same as a document with no unslotted heading at
    # all — otherwise the count reports headings rather than the words nothing caps.
    body = "## 1. Problem Statement\n\nalpha beta\n\n## Appendix A\n\n```\nsample code here\n```\n"

    output = measure(body).output

    assert "UNSLOTTED: 0 section(s) holding 0 word(s)" in output


def test_a_tab_in_a_heading_does_not_shift_the_columns(measure) -> None:
    output = measure("## 5. Detailed\tDesign\nalpha beta\n").output

    row = next(line for line in output.splitlines() if line.startswith("5. Detailed"))
    assert len(row.split("\t")) == 7


def test_a_section_named_total_does_not_collide_with_the_summary_row(measure) -> None:
    body = "## TOTAL\nalpha\n## 5. Detailed Design\nbeta gamma delta\n"

    output = measure(body).output

    rows = [line for line in output.splitlines() if line.split("\t")[0].rstrip() == "TOTAL"]
    assert len(rows) == 1
    assert field(output, "TOTAL", WORDS) == "4"
    assert field(output, "TOTAL (2)", WORDS) == "1"


def test_every_table_row_carries_seven_tab_separated_fields(measure) -> None:
    # A missing cell collapses the row for any caller reading columns.
    output = measure("## 5. Detailed Design\nalpha beta\n").output

    assert_seven_field_rows(output)


def test_a_third_repeat_of_a_heading_gets_its_own_suffix(measure) -> None:
    output = measure("## Notes\na\n## Notes\nb c\n## Notes\nd e f\n").output

    assert field(output, "Notes", WORDS) == "1"
    assert field(output, "Notes (2)", WORDS) == "2"
    assert field(output, "Notes (3)", WORDS) == "3"


def test_the_document_exactly_at_its_ceiling_is_not_over_it(measure) -> None:
    # The same boundary as the section ceiling, on the document total.
    output = measure("word " * 8322 + "\n").output

    assert field(output, "TOTAL", WORDS) == "8322"
    assert field(output, "TOTAL", VERDICT) == "over-target"
    assert summary(output, "CEILING") == "0"


def test_the_document_over_target_but_under_ceiling_reads_over_target(measure) -> None:
    output = measure("word " * 6000 + "\n").output

    assert field(output, "TOTAL", VERDICT) == "over-target"
    assert summary(output, "CEILING") == "0"


def test_a_document_with_no_unslotted_section_reports_an_explicit_zero(measure) -> None:
    # The shell implementation left the field empty here — an uninitialised awk variable
    # — so a caller parsing the count read nothing at all rather than zero.
    output = measure("## 1. Problem Statement\n\nalpha beta\n").output

    assert "UNSLOTTED: 0 section(s) holding 0 word(s)" in output


def test_a_prose_test_identifier_in_test_requirements_is_counted(measure) -> None:
    body = (
        "## 6. Test Requirements\n\n### Unit Tests\n\n"
        "Covers test_login_flow failing without credentials.\n"
    )

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "1"
    hits = [row for row in detail_rows(output) if row[1] == "test_login_flow"]
    assert len(hits) == 1
    assert hits[0][0] == "6. Test Requirements"
    assert "name the behaviour it covers instead" in hits[0][2]


def test_a_table_cell_test_identifier_in_test_requirements_is_counted(measure) -> None:
    # The incident's own §6 content was two tables; a scan wired only into the prose call
    # site would pass every other case here and still miss this one.
    body = (
        "## 6. Test Requirements\n\n### Unit Tests\n\n"
        "| Case | Covers |\n|---|---|\n| test_login_flow | auth |\n"
    )

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "1"
    assert summary(output, "NOROW") == "0"
    hits = [row for row in detail_rows(output) if row[1] == "test_login_flow"]
    assert len(hits) == 1
    assert hits[0][0] == "6. Test Requirements"
    assert "name the behaviour it covers instead" in hits[0][2]


def test_two_test_identifiers_on_one_line_each_count(measure) -> None:
    # finditer() counts every match on a line; replacing it with search() stops at one and
    # survives every single-identifier fixture above.
    body = "## 6. Test Requirements\n\nCovers test_login_flow and test_logout_flow together.\n"

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "2"
    hits = [row for row in detail_rows(output) if row[0] == "6. Test Requirements"]
    assert sorted(row[1] for row in hits) == ["test_login_flow", "test_logout_flow"]


TESTNAMES_ZERO_CASES = [
    ("a single-character identifier", "test_x"),
    ("a two-character identifier", "test_ab"),
    ("an uppercase test-head form", "Test_login_flow"),
    ("a match beginning mid-word", "protest_value"),
]


@pytest.mark.parametrize(
    "name,identifier", TESTNAMES_ZERO_CASES, ids=[c[0] for c in TESTNAMES_ZERO_CASES]
)
def test_testnames_reports_zero_for_an_excluded_shape(measure, name: str, identifier: str) -> None:
    output = measure(f"## 6. Test Requirements\n\nSee {identifier} for details.\n").output

    assert summary(output, "TESTNAMES") == "0"


def test_a_three_character_identifier_tail_is_the_floor(measure) -> None:
    # Pins the {3,} boundary from the counted side; the zero-case above pins it from the
    # excluded side.
    output = measure("## 6. Test Requirements\n\nSee test_abc for details.\n").output

    assert summary(output, "TESTNAMES") == "1"


def test_an_uppercase_character_after_the_prefix_is_still_counted(measure) -> None:
    # The head's case sensitivity already excludes TestX/TEST_F/#[test]; the suffix must
    # not also drop an acronym-cased Python identifier.
    output = measure("## 6. Test Requirements\n\nSee test_HTTPClient_retries for details.\n").output

    assert summary(output, "TESTNAMES") == "1"


def test_a_test_identifier_outside_test_requirements_is_not_counted(measure) -> None:
    # A document-wide counter would misfire on this file's own prose — Detailed Design,
    # Implementation Context and Trade-offs all name real test functions as examples.
    body = (
        "## 3. Implementation Context\n\ntest_example_three mentioned here.\n\n"
        "## 5. Detailed Design\n\ntest_example_five mentioned here.\n\n"
        "## 7. Trade-offs and Alternatives\n\ntest_example_seven mentioned here.\n"
    )

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "0"
    assert "test-identifier hits" not in output


def test_a_fenced_test_identifier_in_test_requirements_is_not_counted(measure) -> None:
    body = "## 6. Test Requirements\n\n```\ntest_login_flow\n```\n"

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "0"


def test_a_backticked_test_identifier_in_test_requirements_is_counted(measure) -> None:
    # No mention exemption is inherited here: every measured corpus hit is backticked.
    body = "## 6. Test Requirements\n\nSee `test_login_flow` for details.\n"

    output = measure(body).output

    assert summary(output, "TESTNAMES") == "1"


def test_testnames_and_norow_print_between_ceiling_and_unslotted_on_a_clean_document(
    measure,
) -> None:
    body = "## 1. Problem Statement\n\nalpha\n\n## 6. Test Requirements\n\nno identifiers here.\n"

    output = measure(body).output
    lines = output.splitlines()
    ceiling_index = next(i for i, line in enumerate(lines) if line.startswith("CEILING:"))
    testnames_index = next(i for i, line in enumerate(lines) if line.startswith("TESTNAMES:"))
    norow_index = next(i for i, line in enumerate(lines) if line.startswith("NOROW:"))
    unslotted_index = next(i for i, line in enumerate(lines) if line.startswith("UNSLOTTED:"))

    assert summary(output, "TESTNAMES") == "0"
    assert summary(output, "NOROW") == "0"
    assert ceiling_index < testnames_index < norow_index < unslotted_index


def test_a_test_requirements_heading_the_resolver_cannot_slot_reports_norow_and_names_slot_six(
    measure,
) -> None:
    # The remedy here is the opposite of the next case's: write the heading back to a
    # spelling the resolver recognises.
    output = measure("## Quality Verification\n\nalpha\n").output

    assert summary(output, "NOROW") == "1"
    assert "NOROW: 1 — slot 6: 0 row(s), 0 prose word(s)" in output


def test_a_prose_free_slot_six_heading_reports_norow_one(measure) -> None:
    # "Test Harness Changes" resolves to slot 6 by the bare word "Test" but carries no
    # prose of its own; the real content sits under "Quality Verification", which the
    # resolver cannot slot at all, so neither counter may read as a clean scan.
    body = "## Test Harness Changes\n\n## Quality Verification\n\ngamma test_login_flow delta\n"

    output = measure(body).output

    assert summary(output, "NOROW") == "1"
    assert "NOROW: 1 — slot 6: 1 row(s), 0 prose word(s)" in output
    assert summary(output, "TESTNAMES") == "0"


def test_a_prose_carrying_slot_six_decoy_covers_for_a_renamed_real_section(measure) -> None:
    # Declared limit (metrics.py's fourth known limit, design.md Sec6 -> Tests Not
    # Written): a second, unrelated section resolving to slot 6 with prose of its own
    # makes NOROW read clean over a renamed real section instead of catching it.
    body = (
        "## Test Harness Changes\n\nunrelated prose here.\n\n"
        "## Quality Verification\n\ngamma test_login_flow delta\n"
    )

    output = measure(body).output

    assert summary(output, "NOROW") == "0"
    assert summary(output, "TESTNAMES") == "0"


def test_a_single_table_cell_word_in_test_requirements_reports_norow_zero(measure) -> None:
    # One cell word is one halfword, which the word-count floor (// 2) rounds to zero —
    # reading that floored count here reported NOROW: 1 on a section that has content.
    output = measure("## 6. Test Requirements\n\n| alpha |\n").output

    assert summary(output, "NOROW") == "0"


def test_a_wholly_fenced_test_requirements_section_reports_norow_one(measure) -> None:
    # Declared limit (metrics.py's fifth known limit, design.md Sec6 -> Tests Not
    # Written): fenced content is never prose anywhere in this tool, so a section whose
    # entire body is a code example has no prose to report, by design.
    body = "## 6. Test Requirements\n\n```\nalpha\n```\n"

    output = measure(body).output

    assert summary(output, "NOROW") == "1"


def test_a_test_requirements_heading_under_an_alternate_spelling_reports_norow_zero(
    measure,
) -> None:
    output = measure("## Testing Strategy\n\nalpha\n").output

    assert summary(output, "NOROW") == "0"


def test_an_alternate_section_six_spelling_still_scans_for_identifiers(measure) -> None:
    # The corpus resolves slot 6 under other spellings too; a scan keyed on heading text
    # rather than on the resolved slot would leave these unscanned.
    output = measure("## Testing Strategy\n\nCovers test_login_flow end to end.\n").output

    assert summary(output, "TESTNAMES") == "1"


def test_two_test_requirements_headings_each_scan_independently_for_identifiers(
    measure,
) -> None:
    # A scan that stops at the first slot-6 section, or reads only the last one, would
    # still report NOROW: 0 here — the fixture needs an identifier in each section to
    # tell "both scanned" from "one scanned, one merely registered".
    body = (
        "## 6. Test Requirements\n\nSee test_alpha_flow here.\n\n"
        "## 6. Test Requirements\n\nSee test_beta_flow here.\n"
    )

    output = measure(body).output

    assert summary(output, "NOROW") == "0"
    assert summary(output, "TESTNAMES") == "2"


def test_norow_ignores_whether_slot_five_is_present(measure) -> None:
    # Slot 5 is outside this count: only an absent or unresolvable slot 6 blocks it.
    body = "## 5. Detailed Design\n\nsome design words.\n\n## 6. Test Requirements\n\nalpha\n"

    output = measure(body).output

    assert summary(output, "NOROW") == "0"


def test_a_document_with_a_test_identifier_hit_still_has_seven_field_rows(measure) -> None:
    # A label missing from either skip list collapses a summary or detail line to one field.
    body = (
        "## 5. Detailed Design\nalpha beta\n\n## 6. Test Requirements\n\n"
        "| Case | Covers |\n|---|---|\n| test_login_flow | auth |\n"
    )

    output = measure(body).output

    assert_seven_field_rows(output)
    assert summary(output, "TESTNAMES") == "1"
