"""Parsing one appendix spec: its §5 rows, their output blocks, and their fields.

The parser is the part the rest of the verifier trusts. Every case here is a shape the
reference corpus actually holds, so a rule tuned to a tidier document fails loudly.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from conftest import CLEAN_SPEC, load_spec
from docgate.specverify import (
    backtick_spans,
    cites_web_page,
    normalise,
    parse_spec,
    raw_url,
    sequence_breaks,
    source_location,
    spec_kind,
    ssh_host,
    token_set,
)

_HEADER = "# Appendix Spec — A1 Fixture\n\n**Page:** `A1-fixture`\n\n---\n\n"


def _spec(section_five: str, claims: str = "") -> str:
    return f"{_HEADER}## 2. Claims\n\n{claims}\n## 5. Verification Procedure\n\n{section_five}"


def _row(row_id: str, *, body: str = "", establishes: str = "C1") -> str:
    return (
        f"### {row_id} — a row\n\n"
        f"**Establishes:** {establishes}\n"
        "**Method:** on-device\n"
        "**Ran on:** fixture board via `ssh fixturehost.invalid`\n"
        "**Run date:** 2026-08-11\n"
        "**Side effects:** none\n\n"
        f"{body}"
        "**Conclusion:** nothing quoted.\n\n"
    )


def test_a_spec_with_a_page_field_is_an_appendix_spec() -> None:
    assert spec_kind("# Spec\n\n**Page:** `A3-thing`\n") == "appendix"


def test_a_spec_with_an_article_field_is_a_main_spec() -> None:
    assert spec_kind("# Spec\n\n**Article:** `04-thing`\n") == "main"


def test_a_spec_with_neither_header_field_has_no_kind() -> None:
    assert spec_kind("# Spec\n\n**Status:** Draft\n") == ""


def test_a_header_field_inside_a_fenced_block_is_not_the_header() -> None:
    # A template quoted in the preamble carries both spellings; reading one would make
    # the spec type depend on which example the author pasted first.
    body = "# Spec\n\n```\n**Article:** <NNN-slug>\n```\n\n**Page:** `A3-thing`\n"

    assert spec_kind(body) == "appendix"


def test_a_page_field_after_the_first_section_is_not_the_header() -> None:
    # Keying on the header field is what stops a spec that lost its §5 reading as a main
    # spec, so the discriminator must not pick a `**Page:**` out of §5's body.
    body = "# Spec\n\n**Status:** Draft\n\n## 1. Scope\n\n**Page:** `A3-thing`\n"

    assert spec_kind(body) == ""


def test_contiguous_row_ids_report_no_break() -> None:
    document = parse_spec(_spec(_row("V1") + _row("V2") + _row("V3")), "spec.md")

    assert sequence_breaks(document.rows) == ["", "", ""]


def test_a_gap_in_the_row_ids_reports_against_the_row_after_it() -> None:
    document = parse_spec(_spec(_row("V1") + _row("V3")), "spec.md")

    breaks = sequence_breaks(document.rows)

    assert breaks[0] == ""
    assert "expected V2, found V3" in breaks[1]


def test_an_id_repeated_in_place_reports_against_the_second_copy() -> None:
    # A set check reads V1, V2, V2 as complete; the walk is what sees the duplicate.
    document = parse_spec(_spec(_row("V1") + _row("V2") + _row("V2")), "spec.md")

    breaks = sequence_breaks(document.rows)

    assert breaks[:2] == ["", ""]
    assert "expected V3, found V2" in breaks[2]


def test_a_sequence_break_names_all_three_causes() -> None:
    document = parse_spec(_spec(_row("V1") + _row("V3")), "spec.md")

    message = sequence_breaks(document.rows)[1]

    assert "deleted without renumbering" in message
    assert "unclosed command fence" in message
    assert "duplicated in place" in message


def test_an_indented_heading_inside_captured_output_does_not_end_the_row() -> None:
    # A fourth column makes the line captured output rather than a heading, and the corpus
    # holds a row whose output carries four indented `### imx…` lines; ending the row there
    # splits one row into five.
    body = "```bash\nprobe\n```\n\n    ### imx477 mode 0\n    width 4056\n    ### imx708 mode 0\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert [row.row_id for row in document.rows] == ["V1"]
    assert document.rows[0].outputs == (
        "    ### imx477 mode 0\n    width 4056\n    ### imx708 mode 0",
    )


def test_interior_blank_lines_keep_one_block_and_are_preserved() -> None:
    body = "    first\n\n    second\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ("    first\n\n    second",)


def test_three_blocks_separated_by_prose_return_in_document_order() -> None:
    body = "    one\n\nprose between\n\n    two\n\nmore prose\n\n    three\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ("    one", "    two", "    three")


def test_trailing_blanks_before_the_closing_line_are_discarded() -> None:
    body = "    only line\n\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ("    only line",)


def test_a_four_space_indented_line_inside_a_fence_is_not_an_output_block() -> None:
    body = "```bash\nfor d in /dev/video*; do\n    probe $d\ndone\n```\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ()
    assert document.rows[0].commands == ("for d in /dev/video*; do\n    probe $d\ndone",)


def test_a_row_with_no_output_block_returns_an_empty_list() -> None:
    document = parse_spec(_spec(_row("V1")), "spec.md")

    assert document.rows[0].outputs == ()


def test_four_spaces_then_a_tab_opens_a_block() -> None:
    # The corpus's V6 output opens with four spaces and a tab, so the rule is "at least
    # four columns" rather than "exactly four spaces".
    body = "    \t[0]: 'S265' (HEVC Parsed Slice Data, compressed)\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ("    \t[0]: 'S265' (HEVC Parsed Slice Data, compressed)",)


def test_a_tab_alone_reaches_four_columns_and_opens_a_block() -> None:
    document = parse_spec(_spec(_row("V1", body="\ttabbed output\n\n")), "spec.md")

    assert document.rows[0].outputs == ("\ttabbed output",)


def test_several_command_blocks_are_collected_in_document_order() -> None:
    body = "```bash\nfirst\n```\n\nprose\n\n```bash\nsecond\n```\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].commands == ("first", "second")


def test_the_block_counts_need_not_agree_row_for_row() -> None:
    # The corpus holds a row with one command block against two output blocks; pairing
    # them by position would index past the end of one list.
    body = "```bash\nonly command\n```\n\n    first block\n\nprose\n\n    second block\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert len(document.rows[0].commands) == 1
    assert len(document.rows[0].outputs) == 2


def test_two_output_blocks_separated_by_a_command_fence_stay_two_blocks() -> None:
    # A command block separates them where the rest of the suite uses prose. Merged into
    # one block the two would have to be adjacent in the fetched file, which is the
    # concatenation each block being matched on its own exists to avoid.
    body = "    first block\n\n```bash\nprobe\n```\n\n    second block\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].outputs == ("    first block", "    second block")


def test_a_field_label_inside_captured_output_is_not_read_as_a_field() -> None:
    # The captured label sits ahead of the row's own Conclusion, which is the order that
    # makes the indent test the only thing rejecting it: first-wins alone would let a
    # command's output replace the field the row declares below it.
    body = "    **Conclusion:** printed by the command\n\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert document.rows[0].value("Conclusion") == "nothing quoted."
    assert document.rows[0].parse_breaks == ()


def test_the_claim_table_yields_ids_and_verified_by() -> None:
    claims = (
        "| ID | Claim | Source | Verified by |\n"
        "|----|-------|--------|-------------|\n"
        "| C1 | the first claim | on-device | V1, V2 |\n\n"
    )
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    claim = document.claims[0]
    assert (claim.claim_id, claim.verified_by) == ("C1", ("V1", "V2"))
    assert claim.has_verified_column is True


def test_a_table_carrying_no_verified_by_column_is_read_as_unverified() -> None:
    claims = (
        "| ID | Claim | What is missing |\n"
        "|----|-------|-----------------|\n"
        "| C9 | an unverified claim | `[UNVERIFIED: no device]` |\n\n"
    )
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    assert document.claims[0].has_verified_column is False
    assert document.claims[0].verified_by == ()


def test_two_claim_tables_are_read_with_their_own_column_shapes() -> None:
    claims = (
        "| ID | Claim | Source | Verified by |\n"
        "|----|-------|--------|-------------|\n"
        "| C1 | verified | on-device | V1 |\n\n"
        "Prose between the tables.\n\n"
        "| ID | Claim | What is missing |\n"
        "|----|-------|-----------------|\n"
        "| C2 | unverified | no device |\n\n"
    )
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    assert [(c.claim_id, c.has_verified_column) for c in document.claims] == [
        ("C1", True),
        ("C2", False),
    ]


def test_a_table_row_missing_its_trailing_cells_still_yields_the_claim() -> None:
    claims = "| ID | Claim | Source | Verified by |\n|----|---|---|---|\n| C1 |\n\n"
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    assert document.claims[0].verified_by == ()
    assert document.claims[0].claim_id == "C1"


def test_a_row_too_short_to_reach_the_id_column_is_not_a_claim() -> None:
    # The ID column is read from the table's own header rather than assumed first, so a
    # row that stops before it holds no claim at all.
    claims = "| Claim | ID | Verified by |\n|---|----|---|\n| just one cell |\n\n"
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    assert document.claims == ()


def test_a_row_whose_command_fence_is_never_closed_still_yields_its_command() -> None:
    # An unclosed fence swallows the following row, which is one of the three causes a
    # sequence break names; the swallowed text still has to reach the surviving row.
    body = "```bash\nprobe --forever\n"
    document = parse_spec(_spec(_row("V1", body=body)), "spec.md")

    assert len(document.rows) == 1
    assert "probe --forever" in document.rows[0].commands[0]


def test_a_table_row_whose_first_cell_is_not_a_claim_id_is_not_a_claim() -> None:
    claims = (
        "| `analysis.md` states | Established here |\n"
        "|---|---|\n"
        "| something wrong | something right |\n\n"
    )
    document = parse_spec(_spec(_row("V1"), claims), "spec.md")

    assert document.claims == ()


def test_a_v_heading_outside_section_five_is_not_a_row() -> None:
    body = f"{_HEADER}## 4. Terminology Contract\n\n### V1 — not a verification row\n\ntext\n"

    assert parse_spec(body, "spec.md").rows == ()


def test_a_level_three_heading_that_is_not_a_row_id_ends_the_previous_row() -> None:
    body = _spec(_row("V1") + "### Notes on the above\n\n**Method:** ignored\n")
    document = parse_spec(body, "spec.md")

    assert [row.row_id for row in document.rows] == ["V1"]


def test_an_ssh_span_yields_the_host() -> None:
    assert ssh_host("target board via `ssh pi`") == "pi"


def test_an_ssh_span_with_a_trailing_clause_still_yields_the_host() -> None:
    assert ssh_host("target board via `ssh pi`, with no libcamera process running") == "pi"


def test_an_ssh_span_after_another_span_still_yields_the_host() -> None:
    # The non-ssh span comes first, so the skip-and-keep-looking path is the one under
    # test; with the ssh span leading, the first span answers and the loop never runs.
    value = "sources at `raspberrypi/linux`, board via `ssh pi`"

    assert ssh_host(value) == "pi"


def test_a_ran_on_naming_no_ssh_host_yields_nothing() -> None:
    assert ssh_host("authoring host, `Documentation/thing.rst` from `a/b` branch `c`") == ""


def test_a_host_that_could_be_read_as_an_ssh_option_is_rejected() -> None:
    # The host reaches ssh as an argv element, so no shell metacharacter can act — but a
    # leading dash would still be parsed as an option rather than as a target.
    assert ssh_host("board via `ssh -oProxyCommand=touch/pwned`") == ""


def test_the_documentation_form_yields_path_repo_and_branch() -> None:
    value = (
        "authoring host, `Documentation/userspace-api/media/v4l/mmap.rst` "
        "from `raspberrypi/linux` branch `rpi-6.12.y`"
    )

    assert source_location(value) == (
        "Documentation/userspace-api/media/v4l/mmap.rst",
        "raspberrypi/linux",
        "rpi-6.12.y",
    )


@pytest.mark.parametrize(
    "value",
    [
        "authoring host, `Documentation/v4l/vidioc-querycap.rst` from `raspberrypi/linux` "
        'branch `rpi-6.12.y`, table "Device Capabilities Flags"',
        # The corpus's V32: the trailing clause is itself backticked, so the value carries
        # a fourth span and a rule reading exactly three spans would SKIP a live row.
        "authoring host, `Documentation/userspace-api/media/v4l/pixfmt-v4l2.rst` from "
        "`raspberrypi/linux` branch `rpi-6.12.y`, `struct v4l2_pix_format` field table",
    ],
)
def test_a_trailing_clause_after_the_branch_is_ignored(value: str) -> None:
    path, repo, branch = source_location(value)

    assert path.startswith("Documentation/")
    assert (repo, branch) == ("raspberrypi/linux", "rpi-6.12.y")


def test_a_ran_on_fitting_neither_shape_yields_nothing() -> None:
    assert source_location("authoring host, from memory") == ("", "", "")


def test_a_span_that_is_not_a_repo_slug_yields_nothing() -> None:
    assert source_location("`a.rst` from `not a repo` branch `main`") == ("", "", "")


def test_an_http_url_is_recognised_as_a_web_page() -> None:
    value = 'authoring host, `https://www.raspberrypi.com/documentation/x.html`, section "Thermal"'

    assert cites_web_page(value) is True


def test_a_repository_path_is_not_a_web_page() -> None:
    assert cites_web_page("authoring host, `Documentation/x.rst` from `a/b` branch `c`") is False


def test_the_raw_url_is_built_from_repo_branch_and_path() -> None:
    assert (
        raw_url("Documentation/x.rst", "raspberrypi/linux", "rpi-6.12.y")
        == "https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.12.y/Documentation/x.rst"
    )


def test_a_conclusion_token_present_in_the_recorded_output_is_kept() -> None:
    assert token_set("the value `0x20000000` rules it in", "flag 0x20000000 set") == ("0x20000000",)


def test_a_conclusion_token_absent_from_the_recorded_output_is_dropped() -> None:
    # A token the author never had in the output was never SR6-supported, so flagging it
    # would fire on authoring style rather than on evidence.
    assert token_set("`ENOTTY` is what `Inappropriate ioctl` means", "Inappropriate ioctl") == (
        "Inappropriate ioctl",
    )


def test_a_conclusion_with_no_backticks_yields_an_empty_set() -> None:
    assert token_set("nothing is quoted here", "plenty of output") == ()


def test_a_token_spanning_a_line_break_in_the_output_is_kept() -> None:
    assert token_set("`only one input and output`", "only one input\nand output") == (
        "only one input and output",
    )


def test_the_same_token_quoted_twice_is_one_member() -> None:
    assert token_set("`alpha` and again `alpha`", "alpha") == ("alpha",)


def test_normalisation_collapses_every_whitespace_run() -> None:
    assert normalise("  a\t\tb\n\n c  ") == "a b c"


def test_backtick_spans_come_back_in_order() -> None:
    assert backtick_spans("`one` then `two`") == ("one", "two")


def test_the_clean_fixture_parses_to_its_stated_shape() -> None:
    document = load_spec(CLEAN_SPEC)

    assert [row.row_id for row in document.rows] == [f"V{n}" for n in range(1, 10)]
    assert sequence_breaks(document.rows) == [""] * 9
    assert len(document.claims) == 12


def test_the_clean_fixture_carries_a_row_with_two_output_blocks() -> None:
    document = load_spec(CLEAN_SPEC)

    row = next(row for row in document.rows if row.row_id == "V7")
    assert len(row.commands) == 1
    assert len(row.outputs) == 2


@pytest.mark.parametrize("label", ["Establishes", "Method", "Ran on", "Run date", "Side effects"])
def test_every_clean_fixture_row_carries_every_required_field(label: str) -> None:
    document = load_spec(CLEAN_SPEC)

    assert all(row.value(label) for row in document.rows)


_A3_SPEC = Path(
    "/home/astavonin/projects/glass-to-glass/planning/book/appendix/issues/"
    "A3-linux-camera-stack/spec.md"
)


@pytest.mark.skipif(not _A3_SPEC.is_file(), reason=f"reference corpus absent: {_A3_SPEC}")
def test_the_reference_corpus_parses_without_raising() -> None:
    # No count is asserted: that spec is being rewritten, which is why the acceptance
    # corpus is a frozen fixture rather than this file.
    document = load_spec(_A3_SPEC)

    assert document.rows
    assert spec_kind(_A3_SPEC.read_text(encoding="utf-8")) == "appendix"
    assert all(row.value("Conclusion") for row in document.rows)
