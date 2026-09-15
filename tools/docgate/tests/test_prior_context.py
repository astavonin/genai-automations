"""The `## Prior Context` skip: `/research`'s machine-pasted locator table in analysis.md.

Fixtures come from two sources, matching the design's own split. REDUCED bodies are
what `/research` actually pastes — the table's header, alignment, and data rows, with
the producer's own headings and footer stripped. RAW bodies are unreduced `search docs`
output, headings and footer included, and are needed only where the hazard lives in the
blocks the reduction drops.
"""

from __future__ import annotations

from conftest import REGISTER, WORDS, field, run

_LOCATOR_TABLE = (
    "| score | tier | repo | path | heading |\n"
    "| --- | --- | --- | --- | --- |\n"
    "| 0.42 | primary | genai-automations | tools/docgate/metrics.py | Detailed Design |\n"
)


def test_prior_context_leaves_the_document_total_unchanged_and_reads_zero(write_doc) -> None:
    # (reduced)
    with_section = (
        f"## Prior Context\n\nQuery: `docs search` — related: false — 1 of 1 shown\n\n"
        f"{_LOCATOR_TABLE}\n## 5. Detailed Design\n\nalpha beta gamma\n"
    )
    without_section = "## 5. Detailed Design\n\nalpha beta gamma\n"

    with_output = run(write_doc(with_section, name="analysis.md")).output
    without_output = run(write_doc(without_section, name="analysis.md")).output

    assert field(with_output, "TOTAL", WORDS) == field(without_output, "TOTAL", WORDS)
    assert field(with_output, "Prior Context", WORDS) == "0"


def test_a_register_phrase_in_a_prior_context_row_raises_no_hit(write_doc) -> None:
    # (reduced) — the same phrase above the section, outside it, still counts.
    body = (
        "the constraint is deliberately narrow here for readers\n\n"
        "## Prior Context\n\nQuery: `deliberately` — related: false — 1 of 1 shown\n\n"
        "| score | tier | repo | path | heading |\n"
        "| --- | --- | --- | --- | --- |\n"
        "| 0.42 | primary | repo | path/to/file.md | Deliberately Named Section |\n"
    )

    output = run(write_doc(body, name="analysis.md")).output

    assert field(output, "(preamble)", REGISTER) == "1"
    assert field(output, "Prior Context", REGISTER) == "0"


def test_a_differently_headed_section_with_the_same_rows_counts_and_scans_as_today(
    write_doc,
) -> None:
    # (reduced) — same shape as the register test above, minus the Prior Context heading.
    body = (
        "## Search Results\n\nQuery: `deliberately` — related: false — 1 of 1 shown\n\n"
        "| score | tier | repo | path | heading |\n"
        "| --- | --- | --- | --- | --- |\n"
        "| 0.42 | primary | repo | path/to/file.md | Deliberately Named Section |\n"
    )

    output = run(write_doc(body, name="analysis.md")).output

    assert field(output, "Search Results", REGISTER) == "1"
    assert field(output, "Search Results", WORDS) != "0"


def test_prior_context_in_a_file_not_named_analysis_counts_and_scans_as_today(
    write_doc,
) -> None:
    # (reduced) — the filename is half the key.
    body = (
        "## Prior Context\n\nQuery: `deliberately` — related: false — 1 of 1 shown\n\n"
        "| score | tier | repo | path | heading |\n"
        "| --- | --- | --- | --- | --- |\n"
        "| 0.42 | primary | repo | path/to/file.md | Deliberately Named Section |\n"
    )

    output = run(write_doc(body, name="design.md")).output

    assert field(output, "Prior Context", REGISTER) == "1"
    assert field(output, "Prior Context", WORDS) != "0"


def test_a_second_prior_context_section_is_also_skipped(write_doc) -> None:
    # (reduced) — _open_section() registers the repeat as "Prior Context (2)"; the skip
    # is keyed on the raw heading text taken before that suffix, not the registered name.
    body = (
        "## Prior Context\n\nalpha beta gamma\n\n"
        "## Somewhere Else\n\ndelta\n\n"
        "## Prior Context\n\nepsilon zeta eta theta\n"
    )

    output = run(write_doc(body, name="analysis.md")).output

    assert field(output, "Prior Context", WORDS) == "0"
    assert field(output, "Prior Context (2)", WORDS) == "0"
    assert field(output, "Somewhere Else", WORDS) == "1"


def test_a_producer_heading_pasted_raw_ends_the_skip_where_the_reduced_paste_does_not(
    write_doc,
) -> None:
    # (raw) — the load-bearing hazard: `/research`'s reduction step drops these two
    # headings and the footer precisely because leaving them in re-opens the register
    # gate on content the author never wrote.
    raw_body = (
        "## Prior Context\n\nQuery: `docs search` — related: false — 1 of 1 shown\n\n"
        "## Roadmap\n\nroadmap entry one two three\n\n"
        f"## Prior decisions\n\n{_LOCATOR_TABLE}\n"
        "---\n\nfooter corpus summary text here\n"
    )
    reduced_body = (
        f"## Prior Context\n\nQuery: `docs search` — related: false — 1 of 1 shown\n\n"
        f"{_LOCATOR_TABLE}"
    )

    raw_output = run(write_doc(raw_body, name="analysis.md")).output
    reduced_output = run(write_doc(reduced_body, name="analysis.md")).output

    assert field(raw_output, "Prior Context", WORDS) == "0"
    assert field(raw_output, "Roadmap", WORDS) != "0"
    assert field(raw_output, "Prior decisions", WORDS) != "0"
    assert field(reduced_output, "TOTAL", WORDS) == "0"


def test_prior_context_appears_as_a_zero_row_rather_than_vanishing(write_doc) -> None:
    # (reduced)
    body = (
        "## Prior Context\n\nQuery: `x` — related: false — 0 of 0 shown\n\n"
        "## 5. Detailed Design\n\nalpha\n"
    )

    output = run(write_doc(body, name="analysis.md")).output
    rows = [line for line in output.splitlines() if line.split("\t")[0].rstrip() == "Prior Context"]

    assert len(rows) == 1
    assert field(output, "Prior Context", WORDS) == "0"
    assert field(output, "Prior Context", REGISTER) == "0"


def test_an_h1_prior_context_heading_is_counted_and_register_scanned_normally(write_doc) -> None:
    # The documented skip key is `## Prior Context` specifically — an H1 with the same
    # words is an ordinary authored section and must not opt out of the register gate.
    body = "# Prior Context\n\nthis paragraph is deliberately authored prose, not a paste\n"

    output = run(write_doc(body, name="analysis.md")).output

    assert field(output, "Prior Context", WORDS) != "0"
    assert field(output, "Prior Context", REGISTER) == "1"


def test_a_fence_like_line_inside_prior_context_does_not_leak_an_open_fence(write_doc) -> None:
    # Proves the placement decision in _Analyzer.feed(): the skip return sits ahead of
    # FenceTracker.feed(), so a line that only looks like a fence opener because it was
    # pasted verbatim into the section never reaches the tracker. Placed after it
    # instead, `is_open` would survive the section boundary and the whole document would
    # fail with an unclosed-fence MeasurementError at a heading the author did write.
    body = (
        "## Prior Context\n\n``` not a real fence, just pasted text\n\n"
        "## 5. Detailed Design\n\nalpha beta\n"
    )

    result = run(write_doc(body, name="analysis.md"))

    assert result.code == 0
    assert field(result.output, "5. Detailed Design", WORDS) == "2"
