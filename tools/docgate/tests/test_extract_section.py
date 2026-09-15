"""extract-section: one anchor heading's body, printed verbatim or a loud failure.

Fence tracking is FenceTracker's own, reused rather than reimplemented — these tests
cover the boundary logic this module adds on top of it (where a section starts and
ends), not fence detection itself, which docgate.markdown's own suite already exercises.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from conftest import extract_run
from docgate.extract import (
    AmbiguousAnchorError,
    SectionNotFoundError,
    UnclosedFenceError,
    extract_section,
)


def test_a_plain_section_body_is_printed_between_its_heading_and_the_next(write_doc) -> None:
    body = "# Title\n\n## Output\n\nalpha beta\ngamma\n\n## Next\n\ndelta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert result.code == 0
    assert result.stdout == "\nalpha beta\ngamma\n"
    assert "delta" not in result.stdout


def test_a_column_zero_hash_inside_a_fence_does_not_end_the_section(write_doc) -> None:
    body = (
        "## Output\n\n"
        "```\n# not a heading, just fenced text\n```\n\n"
        "still inside\n\n## Next\n\nafter\n"
    )
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert result.code == 0
    assert "not a heading, just fenced text" in result.stdout
    assert "still inside" in result.stdout
    assert "after" not in result.stdout


def test_the_section_ends_at_the_next_heading_of_the_same_level(write_doc) -> None:
    body = "## Output\n\nalpha\n\n## Output Two\n\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert "alpha" in result.stdout
    assert "beta" not in result.stdout


def test_the_section_ends_at_a_shallower_heading(write_doc) -> None:
    body = "## Output\n\nalpha\n\n# Top Level\n\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert "alpha" in result.stdout
    assert "beta" not in result.stdout


def test_a_deeper_heading_stays_inside_the_section(write_doc) -> None:
    body = "## Output\n\nalpha\n\n### Sub-heading\n\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert "alpha" in result.stdout
    assert "Sub-heading" in result.stdout
    assert "beta" in result.stdout


def test_the_last_section_in_a_file_runs_to_end_of_file(write_doc) -> None:
    body = "# Title\n\n## Output\n\nalpha\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert result.code == 0
    assert result.stdout == "\nalpha\nbeta\n"


def test_an_absent_anchor_heading_exits_non_zero_and_says_so(write_doc) -> None:
    body = "## Something Else\n\nalpha\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert result.code != 0
    assert result.stdout == ""
    assert "Output" in result.stderr


def test_extract_section_raises_directly_for_an_absent_anchor() -> None:
    with pytest.raises(SectionNotFoundError):
        extract_section("## Something Else\n\nalpha\n", "## Output")


def test_an_anchor_matches_a_labelled_heading_by_its_prefix_before_the_colon(write_doc) -> None:
    # review-mr.md's real headings are "Label: Description" ("Step 2b: Resolve Epic and
    # Instantiate Epic Folder"), so an anchor naming just the label must still resolve.
    body = (
        "### Step 2b: Resolve Epic and Instantiate Epic Folder\n\nalpha\n\n"
        "### Step 3: Gather Diff\n\nbeta\n"
    )
    path = write_doc(body)

    result = extract_run(path, "### Step 2b")

    assert result.code == 0
    assert "alpha" in result.stdout
    assert "beta" not in result.stdout


def test_a_labelled_anchor_does_not_match_a_longer_numbered_heading(write_doc) -> None:
    # "Step 2" must not match "Step 20: ..." — the label match is colon-anchored, not a
    # bare string prefix. "Step 20" is placed FIRST: a bare-prefix match would resolve
    # there before ever reaching the real "Step 2" heading, so a fixture with the longer
    # heading second could pass even without the colon anchor.
    body = "### Step 20: Something Else\n\nbeta\n\n### Step 2: Load MR Context\n\nalpha\n"
    path = write_doc(body)

    result = extract_run(path, "### Step 2")

    assert result.code == 0
    assert "alpha" in result.stdout
    assert "beta" not in result.stdout


def test_a_malformed_anchor_is_rejected_rather_than_silently_matching_nothing() -> None:
    with pytest.raises(ValueError):
        extract_section("## Output\n\nalpha\n", "Output")


def test_an_anchor_heading_inside_a_fence_does_not_open_the_section(write_doc) -> None:
    # A `#`-prefixed line inside a fenced example must not be mistaken for the anchor
    # opening the section — only a real, unfenced heading may start collection.
    body = "```\n### Output\n\nalpha\n```\n\n### Output\n\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "### Output")

    assert result.code == 0
    assert "alpha" not in result.stdout
    assert "beta" in result.stdout


def test_an_unclosed_fence_inside_the_section_blocks_rather_than_running_to_eof(
    write_doc,
) -> None:
    # Reproduces the real review-mr.md defect: an unclosed fence inside the anchored
    # section hides every later heading from the boundary scan, so the section would
    # otherwise run to end of file and swallow a later section's content instead of
    # reporting a bounded, trustworthy extent.
    body = "### Step 2b\n\nalpha\n\n```\nunterminated fence\n\n### Step 3\n\nthe assertion token\n"
    path = write_doc(body)

    result = extract_run(path, "### Step 2b")

    assert result.code != 0
    assert "fence" in result.stderr


def test_extract_section_raises_directly_for_an_unclosed_fence() -> None:
    body = "### Step 2b\n\nalpha\n\n```\nunterminated\n"
    with pytest.raises(UnclosedFenceError):
        extract_section(body, "### Step 2b")


def test_a_duplicate_anchor_heading_is_rejected_rather_than_silently_matching_the_first(
    write_doc,
) -> None:
    body = "## Output\n\nalpha\n\n## Output\n\nbeta\n"
    path = write_doc(body)

    result = extract_run(path, "## Output")

    assert result.code != 0
    assert "Output" in result.stderr


def test_extract_section_raises_directly_for_a_duplicate_anchor() -> None:
    body = "## Output\n\nalpha\n\n## Output\n\nbeta\n"
    with pytest.raises(AmbiguousAnchorError):
        extract_section(body, "## Output")


def test_extract_main_with_the_wrong_argument_count_blocks() -> None:
    result = extract_run("one-argument-only")

    assert result.code == 1
    assert "usage: extract-section" in result.stderr


def test_extract_main_with_a_placeholder_path_blocks() -> None:
    result = extract_run("planning/<NNN>/design.md", "## Output")

    assert result.code == 1
    assert "placeholder left in path" in result.stderr


def test_extract_main_with_a_missing_path_blocks(tmp_path: Path) -> None:
    result = extract_run(tmp_path / "missing.md", "## Output")

    assert result.code == 1
    assert "not a file" in result.stderr


def test_extract_main_with_a_non_utf8_file_blocks(tmp_path: Path) -> None:
    path = tmp_path / "latin1.md"
    path.write_bytes(b"## Output\n\nalpha \xff\xfe beta\n")

    result = extract_run(path, "## Output")

    assert result.code == 1
    assert "not readable" in result.stderr
