"""What blocks, what does not, and what the exit code means.

A non-zero exit means "this number is not a measurement", never "hits found". Message
wording is not a contract — nothing parses it — but each guard asserts its own message
so deleting one guard cannot be masked by a different guard also returning 1.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

import docgate.__main__ as module_entry
import docgate.cli as cli
from conftest import WORDS, field, run, summary


def test_no_argument_blocks() -> None:
    result = run()

    assert result.code == 1
    assert "no file given" in result.output


def test_a_placeholder_left_in_a_path_blocks() -> None:
    # An unsubstituted template would otherwise report "not a file" and read as a
    # missing document rather than as a caller that never filled its template in.
    result = run("planning/<NNN>/design.md")

    assert result.code == 1
    assert "placeholder left in path" in result.output


def test_a_missing_path_blocks(tmp_path: Path) -> None:
    result = run(tmp_path / "missing.md")

    assert result.code == 1
    assert "not a file" in result.output


def test_a_directory_argument_blocks(tmp_path: Path) -> None:
    result = run(tmp_path)

    assert result.code == 1
    assert "not a file" in result.output


@pytest.mark.skipif(os.geteuid() == 0, reason="root can read a chmod 000 file")
def test_an_unreadable_file_blocks(write_doc) -> None:
    path = write_doc("alpha\n")
    path.chmod(0o000)
    try:
        result = run(path)
    finally:
        path.chmod(0o644)

    assert result.code == 1
    assert "not readable" in result.output


def test_nul_bytes_block(write_doc) -> None:
    path = write_doc("alpha beta deliberately\x00gamma by design\n")

    result = run(path)

    assert result.code == 1
    assert "NUL bytes" in result.output


def test_an_unclosed_fence_blocks_rather_than_reporting_zero(measure) -> None:
    # A document with violations after an unclosed fence previously reported zero hits
    # and exit 0, so the count was a lie rather than a measurement.
    body = (
        "## 5. Detailed Design\n\nalpha\n\n```bash\necho hi\n\n"
        "the queue is deliberately unbounded and by design\n"
    )

    result = measure(body)

    assert result.code == 1
    assert "unclosed ``` fence" in result.output


def test_an_unclosed_frontmatter_block_blocks(measure) -> None:
    # Unclosed frontmatter swallowed the entire document and reported TOTAL 0 at exit 0.
    body = "---\nname: thing\nmodel: opus\n\n## 5. Detailed Design\n\nNote that this is prose.\n"

    result = measure(body)

    assert result.code == 1
    assert "unclosed YAML frontmatter" in result.output


def test_a_frontmatter_opener_alone_blocks(measure) -> None:
    # The terminating newline is a terminator, not an empty final line. Counting it as one
    # gives this document a second line, which reads as "no YAML key follows" and cancels
    # the unclosed-frontmatter blocker.
    result = measure("---\n")

    assert result.code == 1
    assert "unclosed YAML frontmatter" in result.output


def test_a_setext_heading_blocks(measure) -> None:
    # A setext heading merges two sections into one budget, which would zero the ceiling
    # gate on a document that is over it.
    result = measure("Problem Statement\n-----\nalpha beta\n")

    assert result.code == 1
    assert "1 setext heading(s)" in result.output


def test_a_horizontal_rule_is_not_mistaken_for_a_setext_heading(measure) -> None:
    result = measure("alpha beta\n\n---\n\ngamma\n")

    assert result.code == 0
    assert "setext" not in result.output
    assert field(result.output, "TOTAL", WORDS) == "3"


def test_each_file_gets_its_own_block_with_its_own_numbers(write_doc) -> None:
    first = write_doc("alpha beta", "multi_a.md")
    second = write_doc("gamma", "multi_b.md")

    output = run(first, second).output

    blocks = output.split("== ")
    assert len(blocks) == 3
    assert field(blocks[1], "TOTAL", WORDS) == "2"
    assert field(blocks[2], "TOTAL", WORDS) == "1"


def test_one_blocking_file_makes_the_whole_run_block(write_doc) -> None:
    # The caller must not read a clean REGISTER line from a sibling and conclude the set
    # is clean.
    good = write_doc("alpha beta", "ok1.md")
    bad = write_doc("one\n```\nunterminated\n", "bad.md")
    other = write_doc("gamma", "ok2.md")

    result = run(good, bad, other)

    assert result.code == 1
    assert "unclosed ``` fence" in result.output


def test_a_document_with_every_counter_non_zero_still_exits_zero(measure) -> None:
    # A counter above zero never changes the exit code; callers read the summary lines.
    body = (
        "## 3. Implementation Context\n\n**Functional Requirements:**\n"
        "- item one — **From:** ticket 464\n- item two untagged\n\n**From:** hunch\n\n"
        "## 7. Trade-offs and Alternatives\n\n### Option A\n**Pros:** x\n**Cons:** y\n\n"
        "### Option B\n**Cost:** ~10 LOC\n"
    )

    result = measure(body)

    assert result.code == 0
    assert summary(result.output, "COST") == "1"
    assert summary(result.output, "MISSES") == "1"
    assert summary(result.output, "FROM") == "1"
    assert summary(result.output, "UNTAGGED") == "1"


def test_the_module_entry_point_is_the_console_script_entry_point() -> None:
    # No behaviour may exist in one invocation path and not the other.
    assert module_entry.main is cli.main


def _big_untagged_document() -> str:
    bullets = "".join(f"- untagged bullet number {index}\n" for index in range(7500))
    return f"## 3. Implementation Context\n\n**Functional Requirements:**\n{bullets}"


def test_a_detail_block_measurably_clears_the_pipe_buffer(measure) -> None:
    # The precondition for the closed-stdout case below: asserting the byte count rather
    # than trusting the bullet count means a later shortening of a reason string cannot
    # silently disarm the guard.
    result = measure(_big_untagged_document())

    assert summary(result.output, "UNTAGGED") == "7500"
    lines = result.output.splitlines()
    total_row = next(i for i, line in enumerate(lines) if line.split("\t")[0].rstrip() == "TOTAL")
    after_total = "\n".join(lines[total_row + 1 :])
    assert len(after_total.encode("utf-8")) > 655360


def test_stdout_closed_mid_output_exits_zero_M3(write_doc) -> None:
    # A caller piping into `head -1` closes the pipe once the detail block passes the
    # buffer. The measurement completed, so this is not a failed run — the shell
    # implementation exited 141 here and printed a false BLOCKER.
    path = write_doc(_big_untagged_document())

    reader = subprocess.Popen(["head", "-1"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    assert reader.stdin is not None
    tool = subprocess.Popen(
        [sys.executable, "-m", "docgate", str(path)],
        stdout=reader.stdin,
        stderr=subprocess.PIPE,
    )
    reader.stdin.close()
    _, stderr = tool.communicate()
    reader.wait()

    assert tool.returncode == 0
    assert b"BrokenPipe" not in stderr


def test_a_closed_reader_does_not_hide_an_unmeasurable_later_document(write_doc) -> None:
    # Exit 0 means everything was measured. A reader going away changes nothing about what
    # was measured, so the remaining documents are still analysed and the unmeasurable one
    # still decides the exit status — otherwise `doc-metrics *.md | head -1` reports success
    # for a set holding a document that blocked.
    big = write_doc(_big_untagged_document(), "closed_reader_big.md")
    bad = write_doc("one\n```\nunterminated\n", "closed_reader_bad.md")

    reader = subprocess.Popen(["head", "-1"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    assert reader.stdin is not None
    tool = subprocess.Popen(
        [sys.executable, "-m", "docgate", str(big), str(bad)],
        stdout=reader.stdin,
        stderr=subprocess.PIPE,
    )
    reader.stdin.close()
    _, stderr = tool.communicate()
    reader.wait()

    assert tool.returncode == 1
    assert b"unclosed ``` fence" in stderr


def test_a_document_measured_after_the_reader_went_away_is_still_written(write_doc) -> None:
    # The sibling cases above never write again after the pipe dies — one passes a single
    # document, the other an unmeasurable second — so neither needs the closed fd pointed
    # anywhere. Here the second document measures and is written, and without the
    # /dev/null redirect the interpreter's shutdown flush raises BrokenPipeError and the
    # run exits 120 for a set every document of which measured correctly.
    big = write_doc(_big_untagged_document(), "later_write_big.md")
    small = write_doc("## 1. Problem Statement\nalpha beta\n", "later_write_small.md")

    reader = subprocess.Popen(["head", "-1"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
    assert reader.stdin is not None
    tool = subprocess.Popen(
        [sys.executable, "-m", "docgate", str(big), str(small)],
        stdout=reader.stdin,
        stderr=subprocess.PIPE,
    )
    reader.stdin.close()
    _, stderr = tool.communicate()
    reader.wait()

    assert tool.returncode == 0
    assert b"BrokenPipe" not in stderr


def test_the_console_script_measures_a_document(write_doc) -> None:
    path = write_doc("## 1. Problem Statement\nalpha beta\n")

    completed = subprocess.run(
        [sys.executable, "-m", "docgate", str(path)], capture_output=True, text=True
    )

    assert completed.returncode == 0
    assert field(completed.stdout, "1. Problem Statement", WORDS) == "2"


def test_a_file_that_is_not_valid_utf8_blocks(tmp_path: Path) -> None:
    # Measuring bytes that are not text would report a number for something that was
    # never prose.
    path = tmp_path / "latin1.md"
    path.write_bytes(b"alpha \xff\xfe beta\n")

    result = run(path)

    assert result.code == 1
    assert "not valid UTF-8" in result.output


def test_reading_a_directory_raises_a_measurement_error(tmp_path: Path) -> None:
    from docgate.metrics import MeasurementError, analyze_file

    with pytest.raises(MeasurementError, match="not readable"):
        analyze_file(tmp_path)
