"""The three checks and the summary they render.

The field and graph checks read the parsed document alone; the token check's routing is
exercised here without the seam, so no case below reaches a board or the network.
"""

from __future__ import annotations

import re

import pytest

from docgate.specverify import (
    COVERS,
    ClaimRow,
    GraphBreak,
    RowResult,
    SpecDocument,
    SpecReport,
    Verdict,
    field_breaks,
    graph_breaks,
    parse_spec,
    render,
    verify,
)

_HEADER = "# Appendix Spec — A1 Fixture\n\n**Page:** `A1-fixture`\n\n---\n\n"

_FIELDS = {
    "Establishes": "C1",
    "Method": "on-device",
    "Ran on": "fixture board via `ssh fixturehost.invalid`",
    "Run date": "2026-08-11",
    "Side effects": "none",
    "Conclusion": "nothing quoted.",
}


def _row_text(fields: dict[str, str], row_id: str = "V1") -> str:
    # The template's own order: the command and its captured output sit between the
    # declared fields and the Conclusion drawn from them. A fence after the Conclusion is
    # text of the next section, which the parser rejects rather than runs.
    lines = [f"### {row_id} — a row", ""]
    lines += [
        f"**{label}:** {value}"
        for label, value in fields.items()
        if value is not None and label != "Conclusion"
    ]
    lines += ["", "```bash", "probe", "```", "", "    output", ""]
    if fields.get("Conclusion") is not None:
        lines += [f"**Conclusion:** {fields['Conclusion']}", ""]
    return "\n".join(lines) + "\n"


def _document(rows: str, claims: str = "") -> SpecDocument:
    body = f"{_HEADER}## 2. Claims\n\n{claims}\n## 5. Verification Procedure\n\n{rows}"
    return parse_spec(body, "spec.md")


#: A §2 table consistent with the single row below, so no graph break masks a field one.
_CLAIMS = (
    "| ID | Claim | Source | Verified by |\n"
    "|----|-------|--------|-------------|\n"
    "| C1 | the only claim | on-device | V1 |\n\n"
)


def _one_row(**overrides: str | None) -> SpecDocument:
    fields = dict(_FIELDS)
    for label, value in overrides.items():
        key = label.replace("_", " ")
        if value is None:
            fields.pop(key, None)
        else:
            fields[key] = value
    return _document(_row_text(fields), _CLAIMS)


def _breaks(**overrides: str | None) -> tuple[str, ...]:
    return field_breaks(_one_row(**overrides).rows[0])


def test_a_correct_row_reports_no_field_break() -> None:
    assert _breaks() == ()


@pytest.mark.parametrize(
    "label", ["Establishes", "Method", "Ran on", "Run date", "Conclusion", "Side effects"]
)
def test_an_absent_required_field_is_rejected(label: str) -> None:
    problems = _breaks(**{label.replace(" ", "_"): None})

    assert problems == (f"**{label}:** is absent",)


def test_an_absent_conclusion_is_rejected_rather_than_passing_vacuously() -> None:
    # Left to the token check an absent Conclusion yields an empty token set, which is a
    # PASS that measured nothing.
    assert _breaks(Conclusion=None) == ("**Conclusion:** is absent",)


def test_an_empty_ran_on_is_rejected() -> None:
    assert _breaks(Ran_on="") == ("**Ran on:** is empty",)


def test_a_placeholder_run_date_is_rejected() -> None:
    problems = _breaks(Run_date="<YYYY-MM-DD>")

    assert problems == ("**Run date:** is still a placeholder — <YYYY-MM-DD>",)


def test_a_tbd_value_is_rejected() -> None:
    assert _breaks(Run_date="TBD") == ("**Run date:** is still TBD",)


def test_a_run_date_that_is_not_zero_padded_is_rejected() -> None:
    assert _breaks(Run_date="2026-8-1") == ("**Run date:** is not YYYY-MM-DD — 2026-8-1",)


def test_a_run_date_in_the_right_shape_is_accepted() -> None:
    assert _breaks(Run_date="2026-08-11") == ()


def test_side_effects_none_is_accepted() -> None:
    assert _breaks(Side_effects="none") == ()


def test_side_effects_mutating_with_a_tail_is_accepted() -> None:
    assert _breaks(Side_effects="mutating — clears the kernel ring buffer") == ()


def test_bare_mutating_with_no_tail_is_rejected() -> None:
    # The prefix decides whether a row may re-run unattended; the tail is what keeps the
    # reason legible, so a row declaring the class without the change is incomplete.
    problems = _breaks(Side_effects="mutating")

    assert problems == (
        "**Side effects:** reads neither `none` nor `mutating — <what changes>` — mutating",
    )


def test_a_hedged_none_is_rejected_rather_than_read_as_none() -> None:
    # The exact match is the whole distance between a hedged declaration and shell on
    # hardware: read as a substring, this value sends the row's commands to the board.
    def _explode(host: str, script: str) -> str:
        raise AssertionError("a row whose Side effects value is not exactly `none` must not run")

    document = _one_row(Side_effects="none — read-only, nothing changes")

    result = verify(document, runner=_explode).results[0]

    assert result.verdict is Verdict.FAIL
    assert "reads neither" in result.reason


def test_a_side_effects_value_outside_the_closed_set_is_rejected() -> None:
    problems = _breaks(Side_effects="partial")

    assert "reads neither" in problems[0]


def test_ran_on_carries_no_shape_rule_at_the_field_level() -> None:
    # A shape rule here would fail every documentation row, none of which names a host;
    # each resolver decides the shape it needs and falls through to SKIP otherwise.
    assert _breaks(Ran_on="authoring host, `x.rst` from `a/b` branch `c`") == ()


def _claim(claim_id: str, verified: tuple[str, ...], *, column: bool = True) -> ClaimRow:
    return ClaimRow(claim_id, verified, column)


def _graph(claims: list[ClaimRow], establishes: dict[str, str]) -> tuple[GraphBreak, ...]:
    rows = "".join(
        _row_text({**_FIELDS, "Establishes": value}, row_id)
        for row_id, value in establishes.items()
    )
    document = _document(rows)
    return graph_breaks(SpecDocument("spec.md", tuple(claims), document.rows))


def test_a_consistent_graph_reports_no_break() -> None:
    assert _graph([_claim("C1", ("V1",))], {"V1": "C1"}) == ()


def test_a_claim_id_in_two_tables_is_a_break_against_the_second_row() -> None:
    breaks = _graph([_claim("C1", ("V1",)), _claim("C1", ("V1",))], {"V1": "C1"})

    assert [(b.target, b.against_claim) for b in breaks] == [("C1", True)]
    assert "more than one §2 table" in breaks[0].message


def test_a_verified_by_naming_no_section_five_row_is_a_break() -> None:
    breaks = _graph([_claim("C1", ("V9",))], {"V1": "C1"})

    assert [(b.target, b.against_claim) for b in breaks] == [("C1", True)]
    assert "which is no §5 row" in breaks[0].message


def test_a_verified_by_whose_row_omits_the_claim_is_a_break() -> None:
    breaks = _graph([_claim("C1", ("V1",)), _claim("C2", ("V1",))], {"V1": "C1"})

    assert [(b.target, b.against_claim) for b in breaks] == [("C2", True)]
    assert "omits it" in breaks[0].message


def test_an_empty_verified_by_cell_is_a_break_against_the_claim() -> None:
    breaks = _graph([_claim("C1", ())], {"V1": "C1"})

    assert [(b.target, b.against_claim) for b in breaks] == [("C1", True)]
    assert "empty `Verified by`" in breaks[0].message


def test_a_row_in_a_table_without_the_column_is_exempt() -> None:
    # Resolving the carve-out by table ordinal instead hard-codes one document's table
    # order and turns every unverified claim into a break on a correct spec.
    assert _graph([_claim("C1", (), column=False)], {"V1": "C1"}) == ()


def test_an_establishes_naming_no_claim_is_a_break_against_the_section_five_row() -> None:
    breaks = _graph([_claim("C1", ("V1",))], {"V1": "C1, C99"})

    assert [(b.target, b.against_claim) for b in breaks] == [("V1", False)]
    assert "which is no §2 claim" in breaks[0].message


def test_a_claim_verified_by_two_rows_needs_both_to_establish_it() -> None:
    breaks = _graph([_claim("C1", ("V1", "V2"))], {"V1": "C1", "V2": "C2"})

    assert len(breaks) == 2
    assert {b.target for b in breaks} == {"C1", "V2"}


def _verdict(**overrides: str | None) -> RowResult:
    return verify(_one_row(**overrides)).results[0]


def test_a_field_break_fails_the_row_before_anything_runs() -> None:
    result = _verdict(Side_effects=None)

    assert result.verdict is Verdict.FAIL
    assert result.reason == "**Side effects:** is absent"


def test_a_field_break_outranks_a_mutating_skip() -> None:
    result = _verdict(Side_effects="mutating", Run_date="TBD")

    assert result.verdict is Verdict.FAIL


def test_a_mutating_row_skips_with_the_change_it_declares() -> None:
    result = _verdict(Side_effects="mutating — clears the kernel ring buffer")

    assert result.verdict is Verdict.SKIP
    assert result.reason == "declared mutating — clears the kernel ring buffer, never re-run"


@pytest.mark.parametrize(
    ("first", "second"),
    [
        ("none", "mutating — clears the kernel ring buffer"),
        ("mutating — clears the kernel ring buffer", "none"),
    ],
)
def test_a_required_field_declared_twice_fails_before_anything_runs(
    first: str, second: str
) -> None:
    # Whichever copy a first-wins parse keeps, the value it hands the gate is one the
    # author contradicted a line later — so the row is rejected rather than resolved.
    fields = dict(_FIELDS)
    fields["Side effects"] = first
    body = _row_text(fields).replace(
        f"**Side effects:** {first}\n",
        f"**Side effects:** {first}\n**Side effects:** {second}\n",
    )

    def _explode(host: str, script: str) -> str:
        raise AssertionError("a row declaring Side effects twice must not run")

    result = verify(_document(body, _CLAIMS), runner=_explode).results[0]

    assert result.verdict is Verdict.FAIL
    assert result.reason == "**Side effects:** is declared more than once"


def test_a_method_value_no_resolver_claims_skips_naming_the_value() -> None:
    result = _verdict(Method="kernel source")

    assert result.verdict is Verdict.SKIP
    assert "kernel source" in result.reason


def test_a_compound_method_value_skips_naming_the_whole_value() -> None:
    result = _verdict(Method="on-device, kernel source")

    assert result.verdict is Verdict.SKIP
    assert "on-device, kernel source" in result.reason


def test_a_specification_method_value_skips() -> None:
    result = _verdict(Method="specification")

    assert result.verdict is Verdict.SKIP
    assert "specification" in result.reason


def test_an_on_device_row_whose_ran_on_names_no_host_skips() -> None:
    result = _verdict(Ran_on="the board in the header")

    assert result.verdict is Verdict.SKIP
    assert "names no `ssh <host>`" in result.reason


def test_a_documentation_row_citing_a_web_page_skips() -> None:
    result = _verdict(
        Method="documentation lookup",
        Ran_on='authoring host, `https://vendor.example/x.html`, section "Thermal"',
    )

    assert result.verdict is Verdict.SKIP
    assert "web page" in result.reason


def test_a_documentation_row_fitting_neither_shape_skips() -> None:
    result = _verdict(Method="documentation lookup", Ran_on="authoring host, from memory")

    assert result.verdict is Verdict.SKIP
    assert "names no" in result.reason


def test_an_on_device_row_skips_when_the_execution_channel_is_absent() -> None:
    result = _verdict()

    assert result.verdict is Verdict.SKIP
    assert "document-only" in result.reason


def test_a_documentation_row_skips_when_the_fetch_channel_is_absent() -> None:
    result = _verdict(
        Method="documentation lookup",
        Ran_on="authoring host, `x.rst` from `a/b` branch `main`",
    )

    assert result.verdict is Verdict.SKIP
    assert "document-only" in result.reason


def test_an_on_device_row_with_no_command_block_skips_rather_than_passing_vacuously() -> None:
    # An empty script proves transport and nothing else, and its token set is empty
    # because the row recorded no output either — a PASS there measures nothing.
    fields = dict(_FIELDS)
    body = "\n".join(
        ["### V1 — a row", ""]
        + [f"**{label}:** {value}" for label, value in fields.items()]
        + ["", "    output", ""]
    )
    document = _document(body + "\n", _CLAIMS)

    result = verify(document, runner=lambda host, script: "unused").results[0]

    assert result.verdict is Verdict.SKIP
    assert result.reason == "no command block to run"


def test_a_documentation_row_with_no_recorded_output_skips() -> None:
    fields = dict(_FIELDS)
    fields["Method"] = "documentation lookup"
    fields["Ran on"] = "authoring host, `x.rst` from `a/b` branch `main`"
    body = "\n".join(
        ["### V1 — a row", ""]
        + [f"**{label}:** {value}" for label, value in fields.items() if label != "Conclusion"]
        + ["", "```bash", "grep x x.rst", "```", ""]
        + [f"**Conclusion:** {fields['Conclusion']}", ""]
    )
    document = _document(body + "\n", _CLAIMS)

    result = verify(document, fetcher=lambda location: "anything").results[0]

    assert result.verdict is Verdict.SKIP
    assert result.reason == "no recorded output block to match"


def _report(
    *results: RowResult, breaks: tuple[GraphBreak, ...] = (), claims: int = 3
) -> SpecReport:
    return SpecReport("/tmp/spec.md", results, breaks, claims)


def _counter(output: str, key: str) -> str:
    return next(line for line in output.splitlines() if line.startswith(f"{key}: "))


def test_an_all_pass_run_renders_its_counts() -> None:
    output = render(
        _report(
            RowResult("V1", Verdict.PASS, tokens_checked=2),
            RowResult("V2", Verdict.PASS, tokens_checked=3),
        )
    )

    assert _counter(output, "PASS") == "PASS: 2 row(s)"
    assert _counter(output, "FAIL") == "FAIL: 0 row(s) or graph break(s)"
    assert _counter(output, "SKIP") == "SKIP: 0 row(s)"
    assert _counter(output, "TOKENS") == "TOKENS: 5 checked across 2 row(s)"
    assert _counter(output, "COVERS") == f"COVERS: {COVERS}"


def test_an_all_skip_run_reads_zero_tokens_across_zero_rows() -> None:
    # This is what separates an all-skip run from a clean one: both exit 0 with FAIL: 0.
    output = render(
        _report(
            RowResult("V1", Verdict.SKIP, "transport failed"), RowResult("V2", Verdict.SKIP, "x")
        )
    )

    assert _counter(output, "SKIP") == "SKIP: 2 row(s)"
    assert _counter(output, "TOKENS") == "TOKENS: 0 checked across 0 row(s)"


def test_a_one_fail_run_renders_its_reason_on_the_row_line() -> None:
    output = render(_report(RowResult("V1", Verdict.FAIL, "a recorded token is absent")))

    assert "V1\tFAIL\ta recorded token is absent" in output
    assert _counter(output, "FAIL") == "FAIL: 1 row(s) or graph break(s)"


def test_the_path_renders_as_the_house_header() -> None:
    assert render(_report()).startswith("== /tmp/spec.md ==\n")


def test_graph_breaks_add_to_the_fail_total_and_carry_their_own_counter() -> None:
    breaks = (
        GraphBreak("C1", True, "C1 appears in more than one §2 table"),
        GraphBreak("V1", False, "**Establishes:** names C99, which is no §2 claim"),
    )
    output = render(_report(RowResult("V1", Verdict.FAIL, "graph"), breaks=breaks, claims=7))

    assert _counter(output, "FAIL") == "FAIL: 2 row(s) or graph break(s)"
    assert _counter(output, "GRAPH") == "GRAPH: 1 inconsistency across 7 claim(s)"


def test_a_claim_side_break_renders_against_its_claim_id() -> None:
    breaks = (GraphBreak("C1", True, "C1 has an empty `Verified by`"),)
    output = render(_report(breaks=breaks))

    assert "C1\tGRAPH\tC1 has an empty `Verified by`" in output


def test_a_row_echoing_a_line_leading_fail_leaves_the_counter_untouched() -> None:
    # The corpus holds a row whose captured output carries eight line-leading `FAIL:`
    # lines; echoing one unprefixed would add eight to a counter a caller parses.
    captured = "FAIL: cannot open /dev/video0\nFAIL: cannot open /dev/video1"
    output = render(_report(RowResult("V1", Verdict.FAIL, "a token vanished", (captured,))))

    assert _counter(output, "FAIL") == "FAIL: 1 row(s) or graph break(s)"
    assert len([line for line in output.splitlines() if line.startswith("FAIL: ")]) == 1


def test_a_line_leading_key_is_only_ever_a_summary_line() -> None:
    # A caller greps `^FAIL: ` for the count, so a reason or a break message reaching
    # column zero would be read as a second counter.
    output = render(
        _report(
            RowResult("V1", Verdict.FAIL, "FAIL: echoed reason", ("FAIL: echoed detail",)),
            breaks=(GraphBreak("C1", True, "PASS: echoed break"),),
        )
    )

    keyed = [line.split(":")[0] for line in output.splitlines() if re.match(r"^[A-Z]+: ", line)]
    assert keyed == ["PASS", "FAIL", "SKIP", "TOKENS", "GRAPH", "COVERS"]


def test_a_detail_line_is_folded_to_one_indented_line() -> None:
    output = render(_report(RowResult("V1", Verdict.FAIL, "reason", ("first\nsecond",))))

    assert "  first second" in output
