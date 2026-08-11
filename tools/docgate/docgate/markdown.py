"""Markdown structure primitives for the document metrics gate.

Everything here works on one already-decoded line at a time, or on a short-lived
tracker fed those lines in document order. Nothing in this module knows about
targets, counters, or output format — that is :mod:`docgate.metrics`.
"""

from __future__ import annotations

import re

__all__ = [
    "FenceTracker",
    "FrontmatterTracker",
    "PREAMBLE",
    "count_words",
    "field_label",
    "heading_level",
    "heading_text",
    "is_blank",
    "is_bullet",
    "is_setext_underline",
    "is_table_row",
    "opening_words",
    "section_slot",
    "split_words",
    "strip_blockquote",
    "strip_field_prefix",
    "strip_list_marker",
]

#: Name of the synthetic section holding content before the first heading.
PREAMBLE = "(preamble)"

_BLOCKQUOTE_RUN = re.compile(r"^([ \t]*>)+")
_BLOCKQUOTE_PREFIX = re.compile(r"^([ \t]*>)+[ \t]*")
_BLOCKQUOTE_PROSE_PREFIX = re.compile(r"^([ \t]*>)+[ \t]?")
_LIST_MARKER = re.compile(r"^[ \t]*([-*+]|[0-9]+\.)[ \t]+")
_BULLET_LINE = re.compile(r"^[ \t]*([-*+]|[0-9]+\.)[ \t]")
_TABLE_PIPE = re.compile(r"^([ \t]*>)*[ \t]*\|")
_TABLE_CELL_PREFIX = re.compile(r"^[ \t]*\|[ \t]*")
_ATX_HEADING = re.compile(r"^(#+)[ \t]")
_HEADING_MARKER = re.compile(r"^#+[ \t]+")
_HEADING_CLOSER = re.compile(r"[ \t]+#+[ \t]*$")
_SETEXT_UNDERLINE = re.compile(r"^[ \t]*(=+|--+)[ \t]*$")
_FENCE_MARKER = re.compile(r"^ {0,3}(`+|~+)")
_BLANK = re.compile(r"^[ \t]*$")
# The BOM is spelled out: the file is decoded as plain UTF-8, so a byte-order mark
# survives into the first line and would otherwise hide the frontmatter opener.
_FRONTMATTER_OPEN = re.compile("^\ufeff?---[ \t]*$")
_FRONTMATTER_CLOSE = re.compile(r"^---[ \t]*$")
_YAML_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]*[ \t]*:")

# Mirrors FIELD_PATTERN in tools/codex-flow/codex_flow/markdown_parser.py, which is
# matched against line.strip() and whose captured name is stripped again. The awk
# original folded an enumerated set of whitespace codepoints here and missed eleven
# of them; str.strip() is the rule the parser actually applies.
_FIELD_LABEL = re.compile(r"^\*\*(?P<name>[^*]+):\*\*")

# Words are separated by spaces and tabs only, as in the source document — not by
# every Unicode space, so an NBSP-joined pair stays one token.
_WORD_SEPARATOR = re.compile(r"[ \t]+")


def split_words(text: str) -> list[str]:
    """Split a line into space- and tab-delimited tokens, empty pieces included."""
    return _WORD_SEPARATOR.split(text)


def _is_word(token: str) -> bool:
    return any((c.isascii() and c.isalnum()) or (not c.isascii() and c.isalpha()) for c in token)


def count_words(text: str) -> int:
    """Count prose words: tokens carrying an ASCII alphanumeric or a non-ASCII letter.

    Symbols, punctuation, and emoji are not words. Non-Latin letters are, so a CJK or
    Cyrillic token counts like an English one.
    """
    return sum(1 for token in split_words(text) if _is_word(token))


def is_blank(line: str) -> bool:
    """Report whether the line holds nothing but spaces and tabs."""
    return _BLANK.match(line) is not None


def is_table_row(line: str) -> bool:
    """Report whether the line opens a pipe table row, blockquoted or not."""
    return _TABLE_PIPE.match(line) is not None


def is_bullet(line: str) -> bool:
    """Report whether the line opens a list item."""
    return _BULLET_LINE.match(line) is not None


def is_setext_underline(line: str) -> bool:
    """Report whether the line could underline a setext heading."""
    return _SETEXT_UNDERLINE.match(line) is not None


def heading_level(line: str) -> int:
    """Return the ATX heading level, or 0 when the line is not a heading."""
    match = _ATX_HEADING.match(line)
    return len(match.group(1)) if match else 0


def heading_text(line: str) -> str:
    """Normalise a heading to its name: markers and closing hashes off, tabs folded.

    Tabs become spaces so a heading cannot break the tab-delimited output, and
    whitespace runs collapse so two spellings of one heading share a row.
    """
    text = _HEADING_MARKER.sub("", line, count=1)
    text = _HEADING_CLOSER.sub("", text, count=1)
    text = text.replace("\t", " ")
    text = re.sub(r"  +", " ", text).rstrip(" ")
    return text or "(unnamed heading)"


def strip_blockquote(line: str, *, keep_indent: bool = False) -> str:
    """Remove leading blockquote markers.

    With ``keep_indent`` the whitespace run after the markers is preserved beyond one
    character, so an indented quoted list item keeps the indentation its marker needs.
    """
    pattern = _BLOCKQUOTE_PROSE_PREFIX if keep_indent else _BLOCKQUOTE_PREFIX
    return pattern.sub("", line, count=1)


def strip_list_marker(line: str) -> str:
    """Remove a leading ordered or unordered list marker."""
    return _LIST_MARKER.sub("", line, count=1)


def strip_field_prefix(line: str) -> str:
    """Remove one blockquote run, list marker, and table pipe from the head of a line.

    A slot-7 field declared as a list item, a quoted line, or a table cell is still a
    declaration; without this the label never reaches its line-start anchor.
    """
    text = _BLOCKQUOTE_PREFIX.sub("", line, count=1)
    text = _LIST_MARKER.sub("", text, count=1)
    return _TABLE_CELL_PREFIX.sub("", text, count=1)


def field_label(line: str) -> str:
    """Return the ``**Label:**`` a line opens with, or an empty string.

    Padding around the label and at the line edges is folded by ``str.strip()``,
    matching ``markdown_parser.py`` exactly: a spelling this accepts is a spelling the
    parser collects as a live field.
    """
    match = _FIELD_LABEL.match(line.strip())
    if match is None:
        return ""
    return match.group("name").strip()


def opening_words(line: str) -> str:
    """Return the first six words of a line as a locator, list marker removed.

    The code-reference rule forbids a bare line number into a planning document, so a
    detail block points at prose instead.
    """
    return " ".join(strip_list_marker(line).split()[:6])


def section_slot(name: str) -> str:
    """Map a heading to its template slot by content, or an empty string for none.

    Matching is on whole words so "Attestation" is not a Test section, and the
    trade-off rule precedes the test rule so "Trade-offs in Testing" lands in slot 7.
    Matching by content rather than by number keeps the older 7-section numbering
    working.
    """
    text = re.sub(r"[^a-z0-9]+", " ", f" {name} ".lower())
    if " problem " in text:
        return "1"
    if " goal " in text or " goals " in text:
        return "2"
    if " implementation context " in text:
        return "3"
    if " architecture overview " in text:
        return "4"
    if " detailed design " in text:
        return "5"
    if any(
        term in text
        for term in (
            " trade off ",
            " trade offs ",
            " tradeoff ",
            " tradeoffs ",
            " alternative ",
            " alternatives ",
        )
    ):
        return "7"
    if " test " in text or " tests " in text or " testing " in text:
        return "6"
    if any(
        term in text
        for term in (" open question ", " open questions ", " open item ", " open items ")
    ):
        return "8"
    # After the exact template names: the corpus's largest design section is headed
    # "Design Decisions" and was unslotted, so no ceiling could see it.
    if " design " in text:
        return "5"
    return ""


class FrontmatterTracker:
    """Consumes a leading YAML frontmatter block so its keys are not read as prose."""

    def __init__(self) -> None:
        self._open = False

    @property
    def is_open(self) -> bool:
        """Report whether a frontmatter block was opened and never closed."""
        return self._open

    def feed(self, line: str, line_number: int) -> bool:
        """Consume one line; return True when it belongs to frontmatter."""
        if line_number == 1:
            if _FRONTMATTER_OPEN.match(line):
                self._open = True
                return True
            return False
        # A leading --- is frontmatter only when a YAML key follows it. Otherwise it is a
        # horizontal rule, and treating it as an opener discards every line up to the next
        # --- — this line is then measured normally.
        if self._open and line_number == 2 and not _YAML_KEY.match(line):
            self._open = False
            return False
        if self._open:
            if _FRONTMATTER_CLOSE.match(line):
                self._open = False
            return True
        return False


class FenceTracker:
    """Tracks fenced-block state across the lines of one document.

    The opener character and its run length are both recorded: a four-backtick fence
    must not be closed by a three-backtick line, which is the shape a document uses to
    show a fence example.
    """

    def __init__(self) -> None:
        self._open = False
        self._char = ""
        self._length = 0
        self._quoted = False

    @property
    def is_open(self) -> bool:
        """Report whether a fence was opened and never closed."""
        return self._open

    @property
    def opener(self) -> str:
        """Return the marker that opened the currently open fence, for diagnostics."""
        return self._char * 3 if self._char else "```"

    def feed(self, line: str) -> bool:
        """Consume one line; return True when the line is a fence marker, not content."""
        text = line
        in_quote = _BLOCKQUOTE_RUN.match(text) is not None
        # A fence opened inside a blockquote ends when the quoting does. Without this the
        # fence stays open over the rest of the document and every following paragraph is
        # discarded, register and all, at exit 0. Quoting is a flag, not a depth, so this
        # bounds that class rather than closing it: a fence opened at ">>" survives a drop
        # to ">". The awk original does the same, and FR-1 pins its verdicts.
        if self._open and self._quoted and not in_quote:
            self._open = False
            self._quoted = False
        # Stripping the marker unconditionally lets a blockquoted fence line close a plain
        # enclosing block and leak its content; never stripping leaves a blockquoted fence
        # unable to close itself.
        if not self._open or self._quoted:
            text = _BLOCKQUOTE_PREFIX.sub("", text, count=1)
        if _FENCE_MARKER.match(text) is None:
            return False
        run = text.lstrip(" ")
        char = run[0]
        length = len(run) - len(run.lstrip(char))
        # Indent is capped at 3 per CommonMark, and a run under 3 is inline code or
        # strikethrough rather than a fence.
        if length < 3:
            return False
        if not self._open:
            self._open = True
            self._char = char
            self._length = length
            self._quoted = in_quote
        elif char == self._char and length >= self._length and not run[length:].strip(" \t"):
            # A closing fence carries no info string (CommonMark). Without this test a
            # ```yaml line inside an open block reads as its closer and every fence after
            # it is inverted.
            self._open = False
        return True
