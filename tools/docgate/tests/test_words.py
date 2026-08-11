"""What counts as a prose word, and what is excluded from the count."""

from __future__ import annotations

import pytest

from conftest import WORDS, field, run

COUNTING_CASES = [
    ("plain words are counted", "one two three", "3"),
    ("punctuation-only tokens do not count", "one — two", "2"),
    ("bold markup does not add words", "**one** two", "2"),
    ("inline code without spaces is one word", "call `process_frame()` now", "3"),
    ("list marker is not a word", "- one two", "2"),
    ("ordered list marker is not a word", "1. one two", "2"),
    ("blank lines contribute nothing", "one\n\ntwo", "2"),
    ("CJK words are counted", "日本語 のテキスト", "2"),
    ("Cyrillic words are counted", "Привет мир", "2"),
    ("check marks are not words", "alpha ✓ beta", "2"),
    ("warning signs are not words", "alpha ⚠ beta", "2"),
    ("math operators are not words", "alpha ≥ beta", "2"),
    ("multiplication sign is not a word", "alpha × beta", "2"),
    # The Latin-1 punctuation block holds three letters; a block-wide strip loses them.
    ("the micro sign is a word", "alpha µ beta", "3"),
    ("ordinal indicators are words", "alpha ª º beta", "4"),
    ("copyright and guillemet are not words", "alpha © « beta", "2"),
    ("emoji are not words", "alpha 😀 beta", "2"),
    # An ATX heading needs a space after its hashes. Without that requirement a line
    # opening on an issue reference becomes a section heading and its own words vanish.
    ("a hash run with no space is prose, not a heading", "#464 is the ticket\nalpha beta", "6"),
]


@pytest.mark.parametrize("name,body,want", COUNTING_CASES, ids=[c[0] for c in COUNTING_CASES])
def test_word_counting(totals, name: str, body: str, want: str) -> None:
    words, register = totals(body)
    assert (words, register) == (want, "0")


EXCLUSION_CASES = [
    ("fenced content is excluded", "one\n```\nalpha beta gamma\n```\ntwo", "2"),
    ("tilde fence is excluded", "one\n~~~\nalpha beta\n~~~\ntwo", "2"),
    ("nested fence stays excluded", "one\n~~~markdown\n## x\n```\na b\n```\n~~~\ntwo", "2"),
    (
        "four-backtick fence is not closed by three",
        "one\n````\nalpha ```beta``` gamma\n```\ndelta epsilon\n````\ntwo",
        "2",
    ),
    ("info-string line does not close a fence", "one\n```\nalpha\n```yaml\nbeta\n```\ntwo", "2"),
    ("fence inside a blockquote is a fence", "one\n> ```\n> alpha beta\n> ```\ntwo", "2"),
    ("table cells count at half weight", "one\n| a | b |\n| - | - |\ntwo", "3"),
    ("indented table cells count at half weight", "one\n  | a | b |\ntwo", "3"),
    # The evasion this weight exists to stop: wrapping prose in pipes must not zero a
    # section.
    ("pipe-wrapped prose still counts", "| alpha beta gamma delta | x |", "2"),
    ("heading text is excluded from words", "## 1. Problem Statement\none two", "2"),
    ("deep heading text is excluded from words", "### Goals\none two", "2"),
    ("a blockquoted fence closes itself", "one\n> ```\n> alpha beta\n> ```\ntwo", "2"),
    (
        "a blockquoted fence does not close a plain one",
        "intro\n```\n> ```\n> deliberately unbounded by design\n> ```\n```\noutro",
        "2",
    ),
    (
        "a four-space-indented fence marker is content",
        "one\n```\ncat <<EOF\n    ```\nEOF\n```\ntwo",
        "2",
    ),
    # The run-length floor: without it a line opening with an inline code span or
    # ~~strike~~ would open a fence and swallow the rest of the document.
    ("a one-backtick line does not open a fence", "`path` is the file\nalpha beta", "6"),
    ("a strikethrough line does not open a fence", "~~gone~~ now\nalpha beta", "4"),
    (
        "YAML frontmatter is skipped, not read as a setext underline",
        "---\nname: thing\nmodel: opus\n---\n\nalpha beta gamma",
        "3",
    ),
]


@pytest.mark.parametrize("name,body,want", EXCLUSION_CASES, ids=[c[0] for c in EXCLUSION_CASES])
def test_exclusions(totals, name: str, body: str, want: str) -> None:
    words, register = totals(body)
    assert (words, register) == (want, "0")


def test_a_leading_rule_is_not_frontmatter(totals) -> None:
    # Reading a bare leading --- as a frontmatter opener discarded every line up to the
    # next ---.
    body = (
        "---\n# Design\n\n## 5. Detailed Design\n\nplease note that the path is hot\n\n---\n\nalpha"
    )
    assert totals(body) == ("8", "1")


def test_a_blockquoted_fence_ends_with_the_blockquote(totals) -> None:
    # Without this the fence stayed open over the rest of the document and every
    # following paragraph was discarded, register and all, at exit 0.
    body = (
        "> ```sh\n> make build\n\nplease note that this paragraph is prose\n\n"
        "```sh\nfenced\n```\n\ntail words here"
    )
    assert totals(body) == ("10", "1")


def test_file_without_trailing_newline_is_counted(write_doc) -> None:
    path = write_doc("one two three")
    assert field(run(path).output, "TOTAL", WORDS) == "3"


def test_crlf_input_yields_clean_section_names_and_counts(write_doc) -> None:
    path = write_doc("## 1. Problem Statement\r\none deliberately two\r\n")

    output = run(path).output

    assert field(output, "1. Problem Statement", WORDS) == "3"
    assert "\r" not in output


def test_empty_file_reports_zero_rather_than_an_error(write_doc) -> None:
    path = write_doc("")

    result = run(path)

    assert result.code == 0
    assert field(result.output, "TOTAL", WORDS) == "0"
