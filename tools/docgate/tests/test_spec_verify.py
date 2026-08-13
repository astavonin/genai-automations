"""End-to-end runs over the two frozen fixtures, and the CLI's exit contract.

Every verdict leaf is driven through the outward seam, so nothing here needs a board or
the network. The three cases that do want one skip with a reported reason when it is not
there — never fail, and never pass silently.
"""

from __future__ import annotations

import http.client
import os
import socket
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from conftest import (
    CLEAN_SPEC,
    DEFECT_SPEC,
    load_spec,
    mirror_runner,
    reasons,
    spec_run,
    summary,
    verdicts,
)
from docgate import specverify
from docgate.specverify import (
    SENTINEL,
    Runner,
    SpecDocument,
    Verdict,
    fetch_document,
    normalise,
    parse_spec,
    render,
    run_over_ssh,
    verify,
)

# Overridable so the skip path can be exercised on a machine where the board *is* up:
# pointing this at a blackholed address (192.0.2.1 is reserved for documentation) is the
# only way to prove the guard skips rather than hangs without waiting for a real outage.
_LIVE_HOST = os.environ.get("DOCGATE_LIVE_HOST", "pi")
_LIVE_REPO = "raspberrypi/linux"
_LIVE_BRANCH = "rpi-6.12.y"
_LIVE_PATH = "Documentation/userspace-api/media/v4l/dmabuf.rst"
_ABSENT_PATH = "Documentation/no-such-file-docgate.rst"


#: Sits between the fetched blocks, so a quote formed by concatenating a row's blocks is
#: absent from the body while each block on its own is present.
_BETWEEN_BLOCKS = "\n\nUnrelated prose the fetched file carries between the two blocks.\n\n"


def _mirror_fetcher(document, *, drop: str = ""):
    """Return a fetch seam replying with every documentation row's recorded blocks."""
    body = _BETWEEN_BLOCKS.join(
        block
        for row in document.rows
        if row.value("Method").strip().lower() == "documentation lookup"
        for block in row.outputs
    )
    if drop:
        body = body.replace(drop, "")

    def _fetch(location: str) -> str:
        del location
        return body

    return _fetch


def _recorded(document: SpecDocument, scripts: list[str]) -> Runner:
    """Return the mirror seam, recording every script it is handed."""
    mirror = mirror_runner(document)

    def _run(host: str, script: str) -> str:
        scripts.append(script)
        return mirror(host, script)

    return _run


def test_the_clean_fixture_passes_every_on_device_row_through_the_mirror_seam() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(
        document,
        runner=mirror_runner(document),
        fetcher=_mirror_fetcher(document),
    )

    found = {result.row_id: result.verdict for result in report.results}
    assert found == {
        "V1": Verdict.PASS,
        "V2": Verdict.PASS,
        "V3": Verdict.PASS,
        "V4": Verdict.PASS,
        "V5": Verdict.SKIP,
        "V6": Verdict.PASS,
        "V7": Verdict.PASS,
        "V8": Verdict.SKIP,
        "V9": Verdict.SKIP,
    }
    assert report.failed == 0
    assert report.graph_count == 0


def test_the_mirror_run_counts_the_tokens_it_checked() -> None:
    # The positive half of acceptance: an inverted comparison anywhere in the token check
    # turns this green run red, which no negative case can detect on its own.
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document), fetcher=_mirror_fetcher(document))

    checked = {result.row_id: result.tokens_checked for result in report.results}
    assert checked["V1"] == 2
    assert checked["V4"] == 1
    assert checked["V6"] == 0
    assert report.token_total == 5
    assert report.token_rows == 4


def test_every_skip_in_the_mirror_run_is_enumerated_with_its_reason() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document), fetcher=_mirror_fetcher(document))

    skipped = {result.row_id: result.reason for result in report.results if result.reason}
    assert "clears the kernel ring buffer" in skipped["V5"]
    assert "web page" in skipped["V8"]
    assert "kernel source" in skipped["V9"]


def test_a_documentation_row_counts_no_token() -> None:
    # Documentation rows take a quote match rather than a token check, so counting them
    # would make TOKENS: read as more re-execution than the run performed.
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document), fetcher=_mirror_fetcher(document))

    assert next(r for r in report.results if r.row_id == "V7").tokens_checked == 0


def test_a_run_with_the_seam_absent_spawns_no_subprocess(monkeypatch) -> None:
    def _explode(*args, **kwargs):
        raise AssertionError("a document-only run must not reach a board")

    monkeypatch.setattr(subprocess, "run", _explode)
    monkeypatch.setattr(urllib.request, "urlopen", _explode)
    document = load_spec(CLEAN_SPEC)

    report = verify(document)

    assert report.failed == 0
    assert report.skipped == len(document.rows)


def test_a_mutating_row_is_never_executed(monkeypatch) -> None:
    def _explode(*args, **kwargs):
        raise AssertionError("a mutating row must not re-run")

    monkeypatch.setattr(subprocess, "run", _explode)
    document = load_spec(CLEAN_SPEC)
    mutating = next(row for row in document.rows if row.row_id == "V5")

    def _runner(host: str, script: str) -> str:
        assert "dmesg -C" not in script
        return f"{SENTINEL}\n"

    report = verify(document, runner=_runner)

    assert mutating.value("Side effects").startswith("mutating")
    assert next(r for r in report.results if r.row_id == "V5").verdict is Verdict.SKIP


def test_an_unclosed_command_fence_fails_its_row_rather_than_running_the_next_one() -> None:
    # V5 clears the ring buffer and V4 declares `none`. A fence V4 never closes puts V5's
    # commands into V4's script, and the gate reads only V4's own declaration.
    text = CLEAN_SPEC.read_text(encoding="utf-8")
    head, fence, tail = text.partition("false\n```\n")
    assert fence, "the fixture's V4 no longer ends its command block where this test cuts"
    document = parse_spec(f"{head}false\n{tail}", str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    result = next(r for r in report.results if r.row_id == "V4")
    assert result.verdict is Verdict.FAIL
    assert "fence" in result.reason


def test_a_fence_left_open_at_end_of_file_fails_the_last_row_rather_than_running_it() -> None:
    # §5 is the last section of every spec in the corpus, so no heading follows the last
    # row's Conclusion — the fence stays open to EOF, where the heading guard never fires
    # and the document text after it lands in a script the row declares `none` for.
    body = CLEAN_SPEC.read_text(encoding="utf-8").split("### V7")[0]
    assert body.rstrip().endswith(
        "contributes no token to the count."
    ), "the fixture's V6 no longer ends the section this test truncates"
    trailer = (
        "```bash\n# note to self: re-check the mode after the next kernel bump\nsudo dmesg -C\n"
    )
    document = parse_spec(body + trailer, str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    result = next(r for r in report.results if r.row_id == "V6")
    assert result.verdict is Verdict.FAIL
    assert "fence" in result.reason


def test_a_rows_own_unclosed_fence_is_named_rather_than_the_field_it_swallowed() -> None:
    # The one shape neither other fence guard reaches: V6's own command fence never
    # closes, so it swallows the `**Conclusion:**` line — the after-Conclusion flag cannot
    # fire, and with no `### V7` following, neither can the heading guard. Left to the
    # field check the row still FAILs, but on the swallowed field rather than on the fence
    # that swallowed it, pointing the author at the wrong line.
    body = CLEAN_SPEC.read_text(encoding="utf-8").split("### V7")[0]
    closed = "printf 'nothing quoted here\\n'\n```\n"
    assert closed in body, "the fixture's V6 no longer closes the command block this test opens"
    document = parse_spec(body.replace(closed, closed[: -len("```\n")], 1), str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("nothing quoted here" not in script for script in scripts)
    result = next(r for r in report.results if r.row_id == "V6")
    assert result.verdict is Verdict.FAIL
    assert result.reason.startswith("a command fence is still open where this row ends")
    assert "**Conclusion:** is absent" in result.details


def test_a_closed_fence_after_the_last_conclusion_fails_its_row_rather_than_running_it() -> None:
    # The fence closes, so neither the heading guard nor the unterminated-block guard sees
    # it: `### V7` never arrives and `build()` finds no leftover lines. What reaches the
    # board is still document text the row after the Conclusion never declared.
    body = CLEAN_SPEC.read_text(encoding="utf-8").split("### V7")[0]
    assert body.rstrip().endswith(
        "contributes no token to the count."
    ), "the fixture's V6 no longer ends the section this test truncates"
    trailer = (
        "\n```bash\n# note to self: re-check the mode after the next kernel bump\n"
        "sudo dmesg -C\n```\n"
    )
    document = parse_spec(body + trailer, str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    result = next(r for r in report.results if r.row_id == "V6")
    assert result.verdict is Verdict.FAIL
    assert "fence" in result.reason


def test_a_closed_fence_between_two_rows_fails_the_row_above_it() -> None:
    # V5 clears the ring buffer and V4 declares `none`. A closed fence sitting between
    # V4's Conclusion and `### V5` lands in V4's script, while V5 still reaches its own
    # `mutating` SKIP — so the sequence walk sees nothing and the run reports no FAIL.
    text = CLEAN_SPEC.read_text(encoding="utf-8")
    anchor = "transport problem.\n\n### V5 — "
    assert anchor in text, "the fixture's V4 no longer ends where this test appends a fence"
    trailing = "transport problem.\n\n```bash\nsudo dmesg -C\n```\n\n### V5 — "
    document = parse_spec(text.replace(anchor, trailing, 1), str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    found = {result.row_id: result.verdict for result in report.results}
    assert found["V4"] is Verdict.FAIL
    assert found["V5"] is Verdict.SKIP
    assert "fence" in next(r for r in report.results if r.row_id == "V4").reason


def test_a_fence_under_a_following_section_heading_leaves_the_last_row_passing() -> None:
    # The control for the two above: a level-2 heading ends the row before the fence
    # opens, so a spec carrying a §6 keeps its last row's own script and its PASS.
    body = CLEAN_SPEC.read_text(encoding="utf-8").split("### V7")[0]
    trailer = "\n## 6. Notes\n\n```bash\nsudo dmesg -C\n```\n"
    document = parse_spec(body + trailer, str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    assert next(r for r in report.results if r.row_id == "V6").verdict is Verdict.PASS


def test_an_on_device_row_with_no_recorded_output_skips_rather_than_passing_on_transport() -> None:
    # `token_set` has two operands and an empty haystack drops every token: V1's
    # Conclusion asserts a host and a kernel release, so with its output block gone the
    # row passes against a board reporting neither, having checked nothing.
    text = CLEAN_SPEC.read_text(encoding="utf-8")
    recorded = "    fixturehost\n    6.12.47-fixture\n"
    assert recorded in text, "the fixture's V1 no longer records the output this test drops"
    document = parse_spec(text.replace(recorded, "", 1), str(CLEAN_SPEC))
    scripts: list[str] = []

    def _another_board(host: str, script: str) -> str:
        del host
        scripts.append(script)
        return f"otherhost\n6.12.99-other\n{SENTINEL}\n"

    report = verify(document, runner=_another_board)

    result = next(r for r in report.results if r.row_id == "V1")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "no recorded output block to match"
    assert all("hostname; uname -r" not in script for script in scripts)


def test_a_command_fence_closed_immediately_skips_rather_than_running_the_sentinel_alone() -> None:
    # An empty fence parses to a one-entry command list holding no command, which walks
    # past a truth test: the board is handed the completion line by itself and the row's
    # recorded tokens are still looked for, so it passes on a command it never ran.
    text = CLEAN_SPEC.read_text(encoding="utf-8")
    block = "```bash\nprintf 'probing\\n\\n4 buffers\\n'\n```\n"
    assert block in text, "the fixture's V2 no longer carries the command block this test empties"
    document = parse_spec(text.replace(block, "```bash\n```\n", 1), str(CLEAN_SPEC))
    scripts: list[str] = []

    def _replies_with_the_record(host: str, script: str) -> str:
        del host
        scripts.append(script)
        return f"probing\n\n4 buffers\n{SENTINEL}\n"

    report = verify(document, runner=_replies_with_the_record)

    result = next(r for r in report.results if r.row_id == "V2")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "no command block to run"
    assert all(script.strip() != f"printf '%s\\n' {SENTINEL}" for script in scripts)


def test_a_row_heading_indented_one_space_still_ends_the_row_before_it() -> None:
    # CommonMark renders one to three leading spaces as a heading. A parser reading only
    # column zero merges V5's `sudo dmesg -C` into V4, which declares `none`.
    text = CLEAN_SPEC.read_text(encoding="utf-8")
    assert "\n### V5 — " in text
    document = parse_spec(text.replace("\n### V5 — ", "\n ### V5 — "), str(CLEAN_SPEC))
    scripts: list[str] = []

    report = verify(document, runner=_recorded(document, scripts))

    assert all("dmesg -C" not in script for script in scripts)
    found = {result.row_id: result.verdict for result in report.results}
    assert found["V4"] is Verdict.PASS
    assert found["V5"] is Verdict.SKIP


def test_every_script_handed_to_the_seam_ends_with_the_sentinel_command() -> None:
    # The completion protocol's two halves are otherwise tested against a pre-supplied
    # answer: the mirror appends the sentinel whatever it is handed. With the append gone
    # every row of a healthy board reports SKIP while the run exits 0 with `FAIL: 0`, and
    # FR-13 blocks on FAIL rather than on SKIP.
    document = load_spec(CLEAN_SPEC)
    scripts: list[str] = []

    verify(document, runner=_recorded(document, scripts))

    assert scripts
    assert all(script.splitlines()[-1] == f"printf '%s\\n' {SENTINEL}" for script in scripts)


def test_the_recorded_output_less_one_token_fails_naming_that_token() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document, without_token="6.12.47-fixture"))

    result = next(r for r in report.results if r.row_id == "V1")
    assert result.verdict is Verdict.FAIL
    assert "`6.12.47-fixture`" in result.reason
    assert result.tokens_checked == 2


def test_output_quoting_the_sentinel_ahead_of_more_output_is_no_completed_run() -> None:
    # The script is document text, so a row can print the sentinel itself; only its
    # arrival as the last line says the appended completion command ran.
    document = load_spec(CLEAN_SPEC)

    def _impersonate(host: str, script: str) -> str:
        del host, script
        return f"{SENTINEL}\nfixturehost\n6.12.47-fixture\n"

    report = verify(document, runner=_impersonate)

    result = next(r for r in report.results if r.row_id == "V1")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "transport failed"


def test_a_completed_run_whose_own_output_quotes_the_sentinel_is_still_evaluated() -> None:
    # Only the completion line is scrubbed, so a row that genuinely printed the sentinel
    # keeps that text in the haystack its tokens are looked for in.
    document = load_spec(CLEAN_SPEC)

    def _echoes(host: str, script: str) -> str:
        del host, script
        return f"fixturehost\n{SENTINEL} echoed\n6.12.47-fixture\n{SENTINEL}\n"

    report = verify(document, runner=_echoes)

    result = next(r for r in report.results if r.row_id == "V1")
    assert result.verdict is Verdict.PASS
    assert result.tokens_checked == 2


def _late_stderr_runner(document: SpecDocument, row_id: str) -> Runner:
    """Return a seam that races one row's own late stderr line against the sentinel.

    Real stderr is unbuffered while stdout through a pipe is block-buffered, so an
    unwrapped script can have this line delivered *after* the sentinel that follows it
    in the script — `_completed()` then reports a transport failure for a row that ran
    cleanly. A script folding a row's commands into one redirected block never lets that
    split happen on a real board, so this seam keys the ordering on the script's own
    shape — the one thing the fix changes — falling back to the mirror seam for every
    other row so the run around the targeted one stays healthy.
    """
    row = next(r for r in document.rows if r.row_id == row_id)
    baseline = mirror_runner(document)
    marker = "\n".join(row.commands)
    late_line = "v4l2-ctl: unrecognized option '--try-fmt-video-mplane=...'"

    def _run(host: str, script: str) -> str:
        if marker not in script:
            return baseline(host, script)
        folded = script.startswith("{\n") and f"{marker}\n}} 2>&1\n" in script
        if folded:
            return f"{row.recorded_output}\n{late_line}\n{SENTINEL}\n"
        return f"{row.recorded_output}\n{SENTINEL}\n{late_line}\n"

    return _run


def test_a_late_stderr_line_folded_ahead_of_the_sentinel_is_not_a_transport_skip() -> None:
    # Observed on a real board: `v4l2-ctl`'s unbuffered stderr write landed after the
    # sentinel roughly one run in three, and the row that ran cleanly reported SKIP —
    # transport failed instead of its verdict. Folding the row's commands into one
    # redirected block keeps everything on one channel ahead of the sentinel.
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=_late_stderr_runner(document, "V1"))

    result = next(r for r in report.results if r.row_id == "V1")
    assert result.verdict is Verdict.PASS
    assert result.tokens_checked == 2


def test_output_with_no_sentinel_reports_a_transport_failure() -> None:
    # Exit status cannot carry this: the corpus holds rows whose non-zero exit is the
    # evidence, and ssh returns 255 both for a remote 255 and for its own failure.
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document, without_sentinel=("V2",)))

    result = next(r for r in report.results if r.row_id == "V2")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "transport failed"


def test_an_empty_reply_reports_a_transport_failure() -> None:
    # What a missing ssh binary or a refused connection returns. Read as a completed run
    # it would PASS every row whose Conclusion quotes nothing, on a board never reached.
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=lambda host, script: "")

    result = next(r for r in report.results if r.row_id == "V6")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "transport failed"


def test_a_row_whose_command_failed_still_passes_when_its_tokens_hold() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document))

    assert next(r for r in report.results if r.row_id == "V4").verdict is Verdict.PASS


def test_a_fetched_body_without_the_recorded_quote_fails_naming_the_anchor() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(
        document,
        runner=mirror_runner(document),
        fetcher=_mirror_fetcher(document, drop="one input and one output"),
    )

    result = next(r for r in report.results if r.row_id == "V7")
    assert result.verdict is Verdict.FAIL
    assert "misquoted" in result.reason
    assert "changed under the cited branch" in result.reason
    assert any("FIXTURE_CAP_ALPHA" in detail for detail in result.details)


def test_a_fetch_returning_no_document_reports_a_transport_failure() -> None:
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document), fetcher=lambda location: None)

    result = next(r for r in report.results if r.row_id == "V7")
    assert result.verdict is Verdict.SKIP
    assert result.reason == "transport failed"


def test_each_output_block_is_matched_on_its_own() -> None:
    # A row's blocks are an ordered list, and the corpus holds one command block against
    # two output blocks; concatenating them would demand the two be adjacent in the file.
    document = load_spec(CLEAN_SPEC)

    report = verify(
        document,
        runner=mirror_runner(document),
        fetcher=_mirror_fetcher(document, drop="The rule is stated once and quoted twice."),
    )

    assert next(r for r in report.results if r.row_id == "V7").verdict is Verdict.FAIL


def test_the_defect_fixture_fails_exactly_its_enumeration() -> None:
    document = load_spec(DEFECT_SPEC)

    report = verify(document)

    failing = [result.row_id for result in report.results if result.verdict is Verdict.FAIL]
    assert failing == ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V9", "V9", "V10"]
    assert report.failed_rows == 10


def test_the_defect_fixture_breaks_exactly_its_graph_enumeration() -> None:
    document = load_spec(DEFECT_SPEC)

    report = verify(document)

    claim_side = [issue.target for issue in report.breaks if issue.against_claim]
    assert sorted(claim_side) == ["C1", "C10", "C11", "C9"]
    assert report.graph_count == 4


def test_the_defect_fixture_keeps_fail_minus_graph_equal_to_the_row_count() -> None:
    report = verify(load_spec(DEFECT_SPEC))

    assert report.failed - report.graph_count == report.failed_rows
    assert report.failed == 14


def test_each_defect_row_reports_the_reason_it_was_written_for() -> None:
    report = verify(load_spec(DEFECT_SPEC))

    found = [(result.row_id, result.reason) for result in report.results]
    assert found[0] == ("V1", "**Side effects:** is absent")
    assert found[1][1].startswith("**Side effects:** reads neither")
    assert found[2][1].startswith("**Side effects:** reads neither")
    assert found[3] == ("V4", "**Conclusion:** is absent")
    assert found[4][1].startswith("**Run date:** is still a placeholder")
    assert found[5][1].startswith("**Run date:** is not YYYY-MM-DD")
    assert found[6] == ("V7", "**Ran on:** is empty")
    assert "C99" in found[9][1]


def test_a_gap_and_a_repeat_in_place_each_report_against_their_own_row() -> None:
    # Two rows share the ID V9: the first is the row after the deleted V8, the second is
    # the duplicate. A check keyed on the ID rather than on document order sees one row.
    report = verify(load_spec(DEFECT_SPEC))

    after_gap, repeated = report.results[7], report.results[8]
    assert (after_gap.row_id, repeated.row_id) == ("V9", "V9")
    assert "expected V8, found V9" in after_gap.reason
    assert "expected V10, found V9" in repeated.reason


def test_the_rendered_defect_run_counts_what_the_report_holds() -> None:
    output = render(verify(load_spec(DEFECT_SPEC)))

    assert summary(output, "FAIL") == "14"
    assert summary(output, "GRAPH") == "4"
    assert summary(output, "SKIP") == "1"
    assert summary(output, "PASS") == "0"


def test_the_cli_reports_a_clean_fixture_run_and_exits_zero(spec_folder) -> None:
    folder = spec_folder(CLEAN_SPEC.read_text(encoding="utf-8"))

    result = spec_run(folder)

    assert result.code == 0
    assert summary(result.output, "FAIL") == "0"
    assert verdicts(result.output)["V5"] == "SKIP"


def test_the_cli_wires_both_channels_into_the_run(monkeypatch, spec_folder) -> None:
    # The one composition the program has: with either channel unwired the tool degrades
    # to a document-only linter that prints `FAIL: 0` and exits 0 having run nothing.
    document = load_spec(CLEAN_SPEC)
    monkeypatch.setattr(specverify, "run_over_ssh", mirror_runner(document))
    monkeypatch.setattr(specverify, "fetch_document", _mirror_fetcher(document))
    folder = spec_folder(CLEAN_SPEC.read_text(encoding="utf-8"))

    result = spec_run(folder)

    assert result.code == 0
    assert summary(result.output, "TOKENS") == "5"
    assert summary(result.output, "PASS") == "6"
    assert summary(result.output, "FAIL") == "0"


def test_a_run_holding_several_fail_rows_still_exits_zero(spec_folder) -> None:
    # Exit status never encodes findings, so no caller may wire `&&` to it.
    folder = spec_folder(DEFECT_SPEC.read_text(encoding="utf-8"))

    result = spec_run(folder)

    assert result.code == 0
    assert summary(result.output, "FAIL") == "14"
    assert "expected V8, found V9" in result.output
    assert reasons(result.output)["V10"].endswith("which is no §2 claim")


def test_no_argument_blocks() -> None:
    result = spec_run()

    assert result.code == 1
    assert "no folder given" in result.output


def test_more_than_one_folder_blocks(spec_folder) -> None:
    result = spec_run(spec_folder(), spec_folder())

    assert result.code == 1
    assert "one folder at a time" in result.output


def test_an_unsubstituted_placeholder_blocks() -> None:
    result = spec_run("planning/book/appendix/issues/<issue-folder>")

    assert result.code == 1
    assert "placeholder left in path" in result.output


def test_an_unresolvable_folder_blocks(tmp_path: Path) -> None:
    result = spec_run(tmp_path / "no-such-issue")

    assert result.code == 1
    assert "not a folder" in result.output


def test_a_folder_holding_no_spec_exits_zero_with_its_reason(spec_folder) -> None:
    # 8 of 11 issue folders in the reference tree hold no spec.md, so this is ordinary.
    result = spec_run(spec_folder())

    assert result.code == 0
    assert "nothing to scan" in result.output
    assert summary(result.output, "FAIL") == ""


def test_a_main_spec_exits_zero_with_its_reason(spec_folder) -> None:
    folder = spec_folder("# Spec — 04 Thing\n\n**Article:** `04-thing`\n\n## 1. Scope\n")

    result = spec_run(folder)

    assert result.code == 0
    assert "main spec" in result.output
    assert summary(result.output, "FAIL") == ""


def test_a_spec_carrying_neither_header_field_blocks(spec_folder) -> None:
    folder = spec_folder("# Spec\n\n**Status:** Draft\n\n## 1. Scope\n")

    result = spec_run(folder)

    assert result.code == 1
    assert "neither **Page:** nor **Article:**" in result.output


def test_an_appendix_spec_with_no_parseable_section_five_blocks(spec_folder) -> None:
    body = CLEAN_SPEC.read_text(encoding="utf-8").split("## 5. Verification Procedure")[0]
    folder = spec_folder(body)

    result = spec_run(folder)

    assert result.code == 1
    assert "no parseable §5" in result.output


def test_an_unreadable_spec_blocks(spec_folder) -> None:
    folder = spec_folder("# Spec\n\n**Page:** `A1`\n")
    spec = folder / "spec.md"
    spec.chmod(0o000)
    try:
        result = spec_run(folder)
    finally:
        spec.chmod(0o644)

    assert result.code == 1
    assert "not readable" in result.output


def test_a_spec_that_is_not_valid_utf8_blocks(spec_folder) -> None:
    folder = spec_folder()
    (folder / "spec.md").write_bytes(b"# Spec\n\n**Page:** \xff\xfe\n")

    result = spec_run(folder)

    assert result.code == 1
    assert "not valid UTF-8" in result.output


def test_the_console_script_entry_points_are_distinct() -> None:
    from docgate import cli

    assert cli.main is not cli.spec_main


def _board_answers() -> bool:
    try:
        completed = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", _LIVE_HOST, "true"],
            capture_output=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def _network_answers() -> bool:
    try:
        socket.getaddrinfo("raw.githubusercontent.com", 443)
    except OSError:
        return False
    return True


@pytest.mark.skipif(not _board_answers(), reason=f"ssh {_LIVE_HOST} does not answer")
def test_a_live_run_returns_output_carrying_the_sentinel() -> None:
    text = run_over_ssh(_LIVE_HOST, f"printf 'live\\n'\nfalse\nprintf '%s\\n' {SENTINEL}\n")

    assert "live" in text
    # Completion is read off the last line, so the real channel has to put it there.
    assert [line for line in text.splitlines() if line.strip()][-1].strip() == SENTINEL


def _url_answers(url: str) -> bool:
    """Report whether a raw urlopen returns 200 for one URL, bypassing fetch_document.

    The control is fetched through urllib rather than through the function under test:
    reading its own None as "no network" is what lets a dead channel skip green.
    """
    request = urllib.request.Request(url, headers={"User-Agent": "docgate/spec-verify-test"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return bool(response.status == 200 and response.read())
    except (urllib.error.URLError, OSError, ValueError):
        return False


@pytest.mark.skipif(not _network_answers(), reason="raw.githubusercontent.com does not resolve")
def test_a_live_fetch_separates_a_present_file_from_a_missing_one(tmp_path: Path) -> None:
    present = f"https://raw.githubusercontent.com/{_LIVE_REPO}/{_LIVE_BRANCH}/{_LIVE_PATH}"
    absent = f"https://raw.githubusercontent.com/{_LIVE_REPO}/{_LIVE_BRANCH}/{_ABSENT_PATH}"
    if not _url_answers(present):
        pytest.skip(f"the control fetch did not answer: {present}")

    body = fetch_document(present, timeout=20)

    assert body is not None
    assert "DMABUF" in normalise(body)
    assert fetch_document(absent, timeout=20) is None
    # FR-8: the fetch yields a verdict and writes its text nowhere, so a misquote cannot
    # pass by a later judgment step reading the fetched passage instead of the author's.
    assert list(tmp_path.iterdir()) == []


def test_an_ssh_binary_that_is_absent_yields_text_with_no_sentinel(monkeypatch) -> None:
    def _missing(*args, **kwargs):
        raise FileNotFoundError("ssh")

    monkeypatch.setattr(subprocess, "run", _missing)

    assert run_over_ssh("nowhere", "true") == ""


def test_a_non_utf8_byte_in_remote_output_does_not_abort_the_run(
    tmp_path: Path, monkeypatch
) -> None:
    # Strict decoding would raise past run_over_ssh's except clause, losing every row
    # already measured and exiting with a traceback where callers parse `BLOCKER:`.
    stand_in = tmp_path / "ssh"
    stand_in.write_text(
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.stdin.buffer.read()\n"
        "sys.stdout.buffer.write(b'alpha\\xffomega\\n')\n",
        encoding="utf-8",
    )
    stand_in.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path), prepend=os.pathsep)

    assert run_over_ssh("nowhere", "true") == "alpha�omega\n"


def test_a_hang_reaches_the_transport_skip_rather_than_blocking(monkeypatch) -> None:
    def _hang(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd="ssh", timeout=kwargs.get("timeout", 0))

    monkeypatch.setattr(subprocess, "run", _hang)

    assert run_over_ssh("nowhere", "true", timeout=0.01) == ""


def test_the_ssh_timeout_reaches_the_subprocess_call(monkeypatch) -> None:
    # Raising TimeoutExpired proves the except clause, not that a hang is bounded: with
    # `timeout=None` the call blocks forever and that clause is never reached.
    seen: dict[str, object] = {}

    def _capture(*args, **kwargs):
        seen.update(kwargs)
        raise subprocess.TimeoutExpired(cmd="ssh", timeout=0)

    monkeypatch.setattr(subprocess, "run", _capture)

    assert run_over_ssh("nowhere", "true") == ""
    assert seen["timeout"] == specverify.SSH_TIMEOUT_SECONDS


def test_the_ssh_call_joins_stderr_into_stdout_and_never_prompts(monkeypatch) -> None:
    # §5.6 reads fresh output as stdout and stderr joined — A3's V13 and V21 carry their
    # evidence on stderr, and dropping it changes their verdict silently. `BatchMode` and
    # `ConnectTimeout` bound the call: without them an unreachable host prompts or hangs
    # instead of reaching the transport SKIP.
    seen: dict[str, object] = {}

    def _capture(argv, **kwargs):
        seen["argv"] = argv
        seen.update(kwargs)
        raise subprocess.TimeoutExpired(cmd="ssh", timeout=0)

    monkeypatch.setattr(subprocess, "run", _capture)

    assert run_over_ssh("nowhere", "true") == ""
    assert seen["stderr"] is subprocess.STDOUT
    assert seen["stdout"] is subprocess.PIPE
    assert seen["argv"] == [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=10",
        "nowhere",
        "bash -s",
    ]


def test_the_fetch_timeout_reaches_the_opener(monkeypatch) -> None:
    seen: dict[str, object] = {}

    def _capture(request, **kwargs):
        del request
        seen.update(kwargs)
        raise urllib.error.URLError("captured")

    monkeypatch.setattr(urllib.request, "urlopen", _capture)

    assert fetch_document("https://raw.githubusercontent.com/a/b/c") is None
    assert seen["timeout"] == specverify.FETCH_TIMEOUT_SECONDS


def test_a_location_that_is_not_https_is_never_opened(monkeypatch) -> None:
    # `Ran on:` is document text: an opener handed `file://` would read a local path as a
    # fetched document and a recorded quote could be satisfied off the authoring host.
    def _explode(*args, **kwargs):
        raise AssertionError("a non-https location must not be opened")

    monkeypatch.setattr(urllib.request, "urlopen", _explode)

    assert fetch_document("file:///etc/passwd") is None


def test_a_dns_failure_yields_no_document(monkeypatch) -> None:
    def _fail(*args, **kwargs):
        raise urllib.error.URLError("name resolution failed")

    monkeypatch.setattr(urllib.request, "urlopen", _fail)

    assert fetch_document("https://raw.githubusercontent.com/a/b/c") is None


def test_a_truncated_response_skips_its_row_and_leaves_the_others_measured(monkeypatch) -> None:
    # `IncompleteRead` is an `http.client.HTTPException`, which is neither an `OSError`
    # nor a `ValueError`: escaping the fetch it would propagate out of the whole run and
    # discard every row already measured on the board.
    class _Truncated:
        status = 200

        def read(self) -> bytes:
            raise http.client.IncompleteRead(b"partial")

        def __enter__(self):
            return self

        def __exit__(self, *args) -> bool:
            return False

    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: _Truncated())
    document = load_spec(CLEAN_SPEC)

    report = verify(document, runner=mirror_runner(document), fetcher=fetch_document)

    found = {result.row_id: result.verdict for result in report.results}
    assert found["V7"] is Verdict.SKIP
    assert next(r for r in report.results if r.row_id == "V7").reason == "transport failed"
    assert found["V1"] is Verdict.PASS
    assert found["V6"] is Verdict.PASS


def test_a_non_200_response_yields_no_document(monkeypatch) -> None:
    class _Response:
        status = 404

        def read(self) -> bytes:
            return b""

        def __enter__(self):
            return self

        def __exit__(self, *args) -> bool:
            return False

    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: _Response())

    assert fetch_document("https://raw.githubusercontent.com/a/b/c") is None
