"""Defensive-register detection: whole-word matching, mention exemptions, detail block."""

from __future__ import annotations

import pytest

from conftest import REGISTER, detail_rows, field

DETECTION_CASES = [
    ("single-word register token counts", "the queue is deliberately unbounded", "5", "1"),
    ("register match is case-insensitive", "Deliberately unbounded", "2", "1"),
    ("multi-word register token counts", "this is by design here", "5", "1"),
    ("four-word register token counts", "which is what makes it safe", "6", "1"),
    ("two hits on one line both count", "deliberately and intentionally so", "4", "2"),
    ("repeated token counts each time", "deliberately here and deliberately there", "5", "2"),
    ("substring is not a hit", "the design is sound", "4", "0"),
    ("important is not importantly", "an important constraint", "3", "0"),
    # Reducing the multi-word comparison to its first word leaves every positive case
    # above green, so these carry the whole contract.
    ("by the design is not by design", "by the design here", "4", "0"),
    ("which is not what makes is not a hit", "which is not what makes it", "6", "0"),
    ("that was said is not that said", "that was said clearly", "4", "0"),
    ("in a few other words is not a hit", "in a few other words", "5", "0"),
    ("of the course is not of course", "of the course", "3", "0"),
    # Fences exempt, everything else counted.
    ("register inside a fence is exempt", "a\n```\ndeliberately\n```\nb", "2", "0"),
    ("register in a table cell counts", "| deliberately | x |", "1", "1"),
    ("register in a blockquote counts", "> the ticket says deliberately", "4", "1"),
    (
        "register in a heading counts",
        "## 5. Detailed Design deliberately so\nalpha",
        "1",
        "1",
    ),
    (
        "a level-3 heading register hit counts",
        "## 5. Detailed Design\n### Deliberately unbounded\nalpha",
        "1",
        "1",
    ),
    # A phrase cannot span a sentence break or a cell boundary.
    ("a phrase cannot span a full stop", "Take note. That is the constraint.", "6", "0"),
    ("a phrase cannot span a colon", "One note: that path is hot.", "6", "0"),
    (
        "a phrase cannot span a cell boundary",
        "| adds a note | that the caller reads |",
        "3",
        "0",
    ),
    ("the same phrase still counts intact", "please note that the path is hot", "7", "1"),
]


@pytest.mark.parametrize(
    "name,body,want_words,want_register", DETECTION_CASES, ids=[c[0] for c in DETECTION_CASES]
)
def test_register_detection(
    totals, name: str, body: str, want_words: str, want_register: str
) -> None:
    assert totals(body) == (want_words, want_register)


MENTION_CASES = [
    ("backticked token is a mention", "the word `deliberately` is banned", "5", "0"),
    ("quoted token is a mention", 'sixteen uses of "deliberately".', "4", "0"),
    ("bold-quoted token is a mention", "see **`by design`** below", "4", "0"),
    ("backticked multi-word is a mention", "the phrase `which is what makes` here", "7", "0"),
    ("single-quoted token is a mention", "use 'deliberately' there", "3", "0"),
    ("token in a wider code span is a mention", "run `grep -x 'deliberately|.*'` now", "5", "0"),
    # The span opens on an earlier word, so the token only CLOSES it and its first
    # character is an ordinary letter — the symmetric quote test alone cannot see this.
    ("a token closing a code span is a mention", "see `the queue is deliberately` here", "6", "0"),
    # Head and tail must be stripped symmetrically. Stripping only markup from the head
    # made a parenthesised mention a violation while the same token before a `)` was
    # exempt.
    ("parenthesised mention is exempt", 'see ("deliberately") above', "3", "0"),
    ("two parenthesised mentions both exempt", 'tokens ("note that", "of course") here', "6", "0"),
    ("bracketed mention is exempt", '["deliberately"] in brackets', "3", "0"),
    ("em-dash-glued mention is exempt", '—"deliberately" em dash', "3", "0"),
    ("curly double quotes are a mention", "the term “deliberately” here", "4", "0"),
    ("curly single quotes are a mention", "the term ‘deliberately’ here", "4", "0"),
    ("guillemets are a mention", "«deliberately» guillemets", "2", "0"),
    ("german quotes are a mention", "„deliberately“ german", "2", "0"),
    # One-sided quotes are uses, and a token inside a longer quoted sentence is a use.
    ("token inside a quoted sentence is a use", '"the queue is deliberately unbounded"', "5", "1"),
    ("an opening quote alone is a use", 'he said "deliberately and stopped', "5", "1"),
    ("a closing quote alone is a use", 'it was deliberately" he said', "5", "1"),
    ("one code-formatted word does not exempt a phrase", "This is on by `design` here", "6", "1"),
    ("a phrase inside a code span is exempt", "see `in other words` here", "5", "0"),
    ("a stray trailing backtick does not exempt", "the flag is set deliberately`", "5", "1"),
    # A span often opens on a token carrying no alphanumeric at all; tracking span state
    # only for real words left the span closed for everything inside it.
    (
        "a span opening on a markup-only token still exempts",
        "a hit in `## 5. Design deliberately` was recorded",
        "8",
        "0",
    ),
]


@pytest.mark.parametrize(
    "name,body,want_words,want_register", MENTION_CASES, ids=[c[0] for c in MENTION_CASES]
)
def test_mention_exemption(
    totals, name: str, body: str, want_words: str, want_register: str
) -> None:
    assert totals(body) == (want_words, want_register)


def test_detail_row_names_section_token_and_window_in_separate_fields(measure) -> None:
    body = (
        "## 5. Detailed Design\n\n"
        "the backing queue is deliberately unbounded so writers never block\n"
    )

    rows = detail_rows(measure(body).output)

    assert len(rows) == 1
    section, token, window = rows[0]
    assert section == "5. Detailed Design"
    assert token == "deliberately"
    assert "unbounded so writers" in window


def test_detail_emits_no_file_line_locator(measure) -> None:
    # The code-reference rule forbids a bare line-number locator into a planning doc.
    output = measure("alpha\nbeta\ngamma deliberately delta\n").output

    assert ".md:" not in output


def test_the_window_spans_five_words_back_and_seven_forward_with_markers(measure) -> None:
    body = (
        "## 5. Detailed Design\n"
        "w1 w2 w3 w4 w5 w6 w7 deliberately w8 w9 w10 w11 w12 w13 w14 w15 w16\n"
    )

    rows = detail_rows(measure(body).output)

    assert rows[0][2] == "...w3 w4 w5 w6 w7 deliberately w8 w9 w10 w11 w12 w13 w14..."


def test_an_untruncated_window_carries_no_markers(measure) -> None:
    rows = detail_rows(measure("deliberately w1 w2\n").output)

    assert rows[0][2] == "deliberately w1 w2"


def test_hits_on_one_line_are_emitted_in_document_order(measure) -> None:
    rows = detail_rows(measure("of course this is deliberately fine\n").output)

    assert [row[1] for row in rows] == ["of course", "deliberately"]


def test_a_register_hit_in_a_heading_belongs_to_the_section_it_opens(measure) -> None:
    body = "## 1. Problem Statement\nalpha\n## 5. Detailed Design deliberately\nbeta\n"

    output = measure(body).output

    assert field(output, "1. Problem Statement", REGISTER) == "0"
    assert field(output, "5. Detailed Design deliberately", REGISTER) == "1"
