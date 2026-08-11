"""Per-section prose-word, defensive-register, and design-field counts for Markdown.

The unit is PROSE WORDS: words outside fenced blocks and headings, plus table cell
text at half weight. ``wc -l`` misleads on these documents because the repo bans
manual line wrapping, so one paragraph is one line and a 1,741-character paragraph
counts as 1. Table cells count at half because tabulating is genuine compression and
should be rewarded — but excluding them outright let a section go from 5,022 words to
0 by wrapping every line in pipes, with the text unchanged. Register is counted at
full weight everywhere outside a fence: a defensive sentence is defensive wherever it
sits.

This module owns the per-section targets and ceilings. Nothing else publishes them.

A :class:`MeasurementError` means "this number is not a measurement", never "hits
found" or "over ceiling". Callers read the REGISTER and CEILING summary lines for
those.

Known limits, none of which affect a document following DESIGN-TEMPLATE.md:
  - A pipe table without leading pipes counts as prose.
  - Inline code containing spaces counts one word per space-separated token.
  - Overlapping register phrases both count ("note that said" is two hits).
  - A register phrase split across a line break is not seen; scanning is per line, and
    the repo bans manual wrapping inside a paragraph, so this needs an authored break.
  - An escaped pipe inside a table cell splits the cell into two words.
  - Section rows are addressed by exact name, not by prefix: a section called TOTAL is
    renamed to "TOTAL (2)", but a caller matching /^TOTAL/ still sees both it and the
    summary row. Match the whole first field.
  - A bare Misses: label in a table remembers its column until the next TABLE ROW, not
    the next line, so a later unrelated table in the same option block can supply the
    value across intervening blank and prose lines.
  - Blockquote nesting depth is not tracked, only whether the fence was quoted at all, so
    a fence opened at ">>" stays open at ">" and a line visible at the outer depth reads
    as fenced content.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from types import MappingProxyType
from typing import Mapping, Sequence

from .markdown import (
    PREAMBLE,
    FenceTracker,
    FrontmatterTracker,
    count_words,
    field_label,
    heading_level,
    heading_text,
    is_blank,
    is_bullet,
    is_setext_underline,
    is_table_row,
    opening_words,
    section_slot,
    split_words,
    strip_blockquote,
    strip_field_prefix,
    strip_list_marker,
)

__all__ = [
    "DOCUMENT_CEILING",
    "DOCUMENT_TARGET",
    "FROM_VALUE_KINDS",
    "Hit",
    "MeasurementError",
    "REGISTER_DETECTORS",
    "REGISTER_DETECTOR_LIST",
    "Report",
    "SECTION_CEILINGS",
    "SECTION_TARGETS",
    "SectionRow",
    "analyze",
    "analyze_file",
    "render",
]

# Defensive-register detector list. NON-EXHAUSTIVE by construction: banning one token
# yields substitutes, so the rule outranks this list and a zero count is not proof the
# rule is met. Matching is whole-word and case-insensitive; multi-word entries must
# appear as consecutive words with no sentence break between them.
#
# Byte-identical to its two prose copies, in platforms/claude/agents/
# architecture-research-planner.md and platforms/codex/skills/
# architecture-research-planner/SKILL.md. REGISTER_DETECTOR_LIST is the joined form
# those documents publish; a consistency test reads it directly.
REGISTER_DETECTORS: tuple[str, ...] = (
    "deliberately",
    "intentionally",
    "by design",
    "which is what makes",
    "worth noting",
    "it should be noted",
    "note that",
    "importantly",
    "crucially",
    "essentially",
    "fundamentally",
    "in other words",
    "that said",
    "of course",
)

REGISTER_DETECTOR_LIST: str = "|".join(REGISTER_DETECTORS)

# The From: value first-tokens that validate, declared exactly once so a consistency
# test can read this table instead of re-deriving the accepted set from the validator.
# "bare": the token alone is sufficient (analysis). "value": a second token, any text
# (ticket, spec). "date": a second token in strict YYYY-MM-DD form (incident,
# decision). Widening the accepted set means editing this one mapping.
FROM_VALUE_KINDS: Mapping[str, str] = MappingProxyType(
    {
        "analysis": "bare",
        "ticket": "value",
        "spec": "value",
        "incident": "date",
        "decision": "date",
    }
)

# Per-section targets: the canonicalised median across all 39 corpus documents.
# CEILINGS EXIST ONLY FOR SLOTS 5 AND 6 AND THE DOCUMENT. A p75 ceiling on all eight
# slots blocked 20 of 39 existing documents, most of them on a small section carrying
# no bloat; slots without a ceiling report an advisory verdict only. Slot 5's ceiling
# is the measured p75. Slot 6's is 2x its target rather than the measured p75: slot 6
# has the smallest sample and a bimodal pool, so its p75 moves 10% with one more
# document (bootstrap 90% CI 877-2334) and would not be a stable gate.
SECTION_TARGETS: Mapping[str, int] = MappingProxyType(
    {"1": 184, "2": 283, "3": 441, "4": 129, "5": 4232, "6": 877, "7": 580, "8": 45}
)
SECTION_CEILINGS: Mapping[str, int] = MappingProxyType({"5": 5463, "6": 1754})
DOCUMENT_TARGET = 5800
DOCUMENT_CEILING = 8322

_SUMMARY_ROW = "TOTAL"
_TABLE_HEADER = ("section", "words", "share", "reg", "target", "ceiling", "verdict")

_DETECTOR_WORDS: tuple[tuple[str, tuple[str, ...]], ...] = tuple(
    (phrase, tuple(phrase.split(" "))) for phrase in REGISTER_DETECTORS
)

# Quote characters marking a mention rather than a use: backtick, double quote,
# apostrophe, and the curly and guillemet forms a prose document actually uses.
_QUOTE_CHARS = frozenset("`\"'‘’“”«»„")

# The awk original tested the FIRST BYTE of the boundary token against a byte string
# holding those quotes, so any character sharing a UTF-8 byte with one of them — the
# em dash in `—"deliberately"` most visibly — also opened a mention. Reproducing the
# byte test keeps that verdict: dropping it would turn documented mentions into
# register hits, which is a decision change, not a formatting one.
_QUOTE_BYTES = frozenset(b"".join(c.encode("utf-8") for c in sorted(_QUOTE_CHARS)))

_SENTENCE_BREAK = re.compile(r'[.:;!?|]["\)]*$')
_BOUNDARY_PUNCTUATION = frozenset(".:;!?|")

_EXACT_REQUIREMENT_OPENER = re.compile(
    r"^\*\*(Functional Requirements|Non-Functional Requirements|Constraints):\*\*"
)
_REQUIREMENT_HEADING = re.compile(
    r"^(Functional Requirements|Non-Functional Requirements|Constraints):?$"
)
_BULLETED_BOLD = re.compile(r"^[ \t]*([-*+]|[0-9]+\.)[ \t]+\*\*")
# Padding inside **...** is folded the way str.strip() folds it, so every spelling
# markdown_parser.py collects as a From: field is found here too.
_FROM_LABEL = re.compile(r"\*\*\s*From\s*:\*\*")
_SLOT7_FIELD_CELL = re.compile(r"^\*\*(Cost|Misses):\*\*")
_COST_ANCHOR = re.compile(r"^[ \t]*\*\*Cost:\*\*")
_MISSES_ANCHOR = re.compile(r"^[ \t]*\*\*Misses:\*\*")
_MISSES_VALUE = re.compile(r"^.*\*\*Misses:\*\*")
_ISO_DATE = re.compile(r"^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$")

_REQUIREMENT_LABELS = frozenset(
    {"Functional Requirements", "Non-Functional Requirements", "Constraints"}
)

_NO_COST_LINE = "no Cost: line in this option block"
_NO_MISSES_VALUE = "no Misses: value in this option block"
_NO_OPTION_BLOCK = "no ### option block opened in this section"
_HEADING_OPENER = "requirement group opener written as a heading, not inline bold text"
_BULLETED_OPENER = (
    "requirement group opener is a bulleted label, not inline bold text; the "
    "FIELD_PATTERN in markdown_parser.py does not match a list marker before it"
)
_PADDED_OPENER = (
    "requirement group opener has whitespace around the label inside **...**; "
    "markdown_parser.py accepts it but this scanner does not check bullets beneath it "
    "for a missing From: tag"
)
_FROM_OPENS_LINE = "From: label opens the line — must be inline (C3)"
_FROM_AFTER_CLOSER = (
    "requirement group closed by this label; a From: tag below it is outside the group"
)
_FROM_OUTSIDE_GROUP = "From: label outside a requirement group"
_FROM_UNRECOGNISED = "unrecognised or incomplete From: value"
_BULLET_UNTAGGED = "requirement bullet with no From: tag"


class MeasurementError(Exception):
    """A document or path that cannot be measured, so no number may be reported."""

    def __init__(self, message: str, detail: str = "") -> None:
        super().__init__(message)
        self.message = message
        self.detail = detail


@dataclass(frozen=True)
class Hit:
    """One reported occurrence: where it is, what to look at, and why it counts."""

    section: str
    locator: str
    reason: str


@dataclass(frozen=True)
class SectionRow:
    """One section's measured row in the per-section table."""

    name: str
    words: int
    register: int
    slot: str


@dataclass
class Report:
    """A complete measurement of one document."""

    path: str
    rows: list[SectionRow] = field(default_factory=list)
    register_hits: list[Hit] = field(default_factory=list)
    field_hits: list[Hit] = field(default_factory=list)
    slot_words: dict[str, int] = field(default_factory=dict)
    slot_rows: dict[str, int] = field(default_factory=dict)
    cost: int = 0
    misses: int = 0
    from_tags: int = 0
    untagged: int = 0

    @property
    def total_words(self) -> int:
        """Prose words across every section."""
        return sum(row.words for row in self.rows)

    @property
    def total_register(self) -> int:
        """Register hits across every section."""
        return sum(row.register for row in self.rows)

    @property
    def unslotted_sections(self) -> int:
        """Sections matching no template slot that still carry prose."""
        return sum(1 for row in self.rows if not row.slot and row.words > 0)

    @property
    def unslotted_words(self) -> int:
        """Prose words held by sections matching no template slot."""
        return sum(row.words for row in self.rows if not row.slot and row.words > 0)

    @property
    def over_ceiling(self) -> int:
        """Slots over their ceiling, plus the document itself when it is over.

        Counted per SLOT, not per row: splitting one section into two headings, or
        repeating a heading, would otherwise multiply the budget.
        """
        over = 1 if self.total_words > DOCUMENT_CEILING else 0
        over += sum(
            1
            for slot, ceiling in SECTION_CEILINGS.items()
            if self.slot_words.get(slot, 0) > ceiling
        )
        return over

    def verdict(self, slot: str) -> str:
        """Return a slot's verdict from its accumulated total, not from one row."""
        if not slot:
            return "-"
        words = self.slot_words.get(slot, 0)
        ceiling = SECTION_CEILINGS.get(slot)
        if ceiling is not None and words > ceiling:
            return "OVER-CEILING"
        if words > SECTION_TARGETS[slot]:
            return "over-target"
        return "ok"


def _register_key(token: str) -> str:
    """Reduce a token to its ASCII alphanumerics, lowercased, for whole-word matching."""
    return "".join(c for c in token if c.isascii() and c.isalnum()).lower()


class _Tokens:
    """The words of one line, with the state each register comparison needs."""

    __slots__ = ("keys", "originals", "in_span", "breaks")

    def __init__(self, text: str) -> None:
        self.keys: list[str] = []
        self.originals: list[str] = []
        self.in_span: list[bool] = []
        self.breaks: list[bool] = []
        span = False
        pending_break = False
        for token in split_words(text):
            key = _register_key(token)
            # Span state is tracked for EVERY token, including ones that normalise away:
            # a span often opens on a token like `## that carries no alphanumeric at all,
            # and skipping it leaves the span closed for the words inside it.
            was_in_span = span
            if token.count("`") % 2:
                span = not span
            if not key:
                # A token that normalises away can still be a boundary — a bare "|"
                # between two table cells is the common case — so remember it for the
                # next real word.
                if any(c in _BOUNDARY_PUNCTUATION for c in token):
                    pending_break = True
                continue
            self.keys.append(key)
            self.originals.append(token)
            self.in_span.append(was_in_span)
            if pending_break and len(self.keys) > 1:
                self.breaks[-1] = True
            pending_break = False
            # A phrase cannot span a sentence break or a cell boundary: "Take note. That
            # is" otherwise matched "note that".
            self.breaks.append(_SENTENCE_BREAK.search(token) is not None)

    def __len__(self) -> int:
        return len(self.keys)


def _trim_head(token: str) -> str:
    """Drop leading markup so the mention test sees the token's first real character."""
    index = 0
    while index < len(token):
        char = token[index]
        if not char.isascii() or char.isalnum() or char in _QUOTE_CHARS:
            break
        index += 1
    return token[index:]


def _trim_tail(token: str) -> str:
    """Drop trailing markup so the mention test sees the token's last real character."""
    end = len(token)
    while end > 0:
        char = token[end - 1]
        if not char.isascii() or char.isalnum() or char in _QUOTE_CHARS:
            break
        end -= 1
    return token[:end]


def _is_mention(tokens: _Tokens, first: int, last: int) -> bool:
    """Report whether a matched run names the token rather than using it.

    The run opens and closes with a quote character, allowing markup before the opener
    and punctuation after the closer. Both ends are stripped symmetrically — stripping
    only markup from the head made ("deliberately") a violation while "of course") was
    exempt. A token merely inside a longer quoted sentence matches neither end and
    still counts.

    Both trims return a non-empty string: a matched token carries an ASCII alphanumeric
    by construction, and that character stops the trim.
    """
    # Inside an inline code span that opened on an EARLIER word: the token then only
    # closes the span and its own first character is an ordinary letter, which the
    # symmetric test below cannot see.
    if tokens.in_span[first] and tokens.in_span[last]:
        return True
    head = _trim_head(tokens.originals[first])
    tail = _trim_tail(tokens.originals[last])
    return head.encode("utf-8")[0] in _QUOTE_BYTES and tail.encode("utf-8")[-1] in _QUOTE_BYTES


def _window(tokens: _Tokens, index: int) -> str:
    """Return whole words around a match, locating the hit without a line number.

    Punctuation-only tokens are kept so the window can be grepped against the source.
    """
    count = len(tokens)
    low = max(0, index - 5)
    high = min(count - 1, index + 7)
    text = " ".join(tokens.originals[low : high + 1])
    if low > 0:
        text = f"...{text}"
    if high < count - 1:
        text = f"{text}..."
    return text


def _from_value_is_valid(value: str) -> bool:
    """Validate a From: tag value: its first token, and its second where one is due.

    Text beyond that is free prose — a tag may carry a ticket link or an explanatory
    clause — so only the first two tokens are tested.
    """
    words = value.split()
    if not words:
        return False
    kind = FROM_VALUE_KINDS.get(words[0])
    if kind == "bare":
        return True
    if kind == "value":
        return len(words) >= 2
    if kind == "date":
        return len(words) >= 2 and _ISO_DATE.match(words[1]) is not None
    return False


class _Analyzer:
    """Accumulates one document's measurement, one line at a time."""

    def __init__(self, path: str) -> None:
        self._path = path
        self._fence = FenceTracker()
        self._frontmatter = FrontmatterTracker()
        self._setext = 0
        self._prev_prose = False
        self._section = PREAMBLE
        # A section literally named TOTAL would collide with the summary row for a caller
        # matching the whole first field, so the name is reserved.
        self._seen: set[str] = {_SUMMARY_ROW}
        self._order: list[str] = []
        self._halfwords: dict[str, int] = {}
        self._register: dict[str, int] = {}
        self._titles: set[str] = set()
        self._seen_title = False
        self._register_hits: list[Hit] = []
        self._field_hits: list[Hit] = []
        self._slots: dict[str, str] = {}

        # Design-field state: slot 7 tracks one open ### option block at a time, slot 3
        # the current requirement-group state. Both reset per section change, mirroring
        # how word and register accumulation is already section-scoped.
        self._option_open = False
        self._option_cost = False
        self._option_misses = False
        self._option_locator = ""
        # The column a bare Misses: label was seen in, in a table row whose own cells
        # never supplied a value — a label-row/value-row layout puts the value in the
        # SAME column of the NEXT row.
        self._misses_pending_column = 0
        self._option_block_seen = False
        self._group = ""
        # A third axis, independent of the group state: a spaced-colon near-miss opener
        # is collected as a live group by markdown_parser.py, so an inline From: tag
        # beneath it is valid — but its bullets are not swept for a missing tag, because
        # the malformed opener already reports once and scoring every bullet beneath it
        # would scale one defect by bullet count.
        self._scan_bullets = False
        self._group_closer = ""
        self.cost = 0
        self.misses = 0
        self.from_tags = 0
        self.untagged = 0

    # --- section bookkeeping -------------------------------------------------

    def _slot_of(self, name: str) -> str:
        if name in self._titles:
            return ""
        slot = self._slots.get(name)
        if slot is None:
            slot = section_slot(name)
            self._slots[name] = slot
        return slot

    def _register_section(self, name: str) -> None:
        """Record a section on first use, preserving document order.

        A heading registers eagerly, so a section the author declared but left without
        prose reports 0 rather than vanishing — for an Architecture Overview that is
        mostly a diagram, a missing row and a zero row mean different things.
        """
        if name not in self._register:
            self._order.append(name)
            self._halfwords[name] = 0
            self._register[name] = 0
            self._seen.add(name)

    def _unique(self, name: str) -> str:
        """Suffix a repeated heading so two sections cannot merge into one row."""
        if name not in self._seen:
            return name
        index = 2
        candidate = f"{name} ({index})"
        while candidate in self._seen:
            index += 1
            candidate = f"{name} ({index})"
        return candidate

    # --- register ------------------------------------------------------------

    def _scan_register(self, text: str, section: str) -> None:
        """Count register phrases in one line and record each hit against ``section``.

        Emission is in document order — position outer, detector inner — so two hits on
        a line can be told apart by their windows.
        """
        tokens = _Tokens(text)
        count = len(tokens)
        if count == 0:
            return
        for index in range(count):
            for phrase, words in _DETECTOR_WORDS:
                span = len(words)
                if index + span > count:
                    continue
                matched = True
                for offset, word in enumerate(words):
                    if tokens.keys[index + offset] != word:
                        matched = False
                        break
                    if offset < span - 1 and tokens.breaks[index + offset]:
                        matched = False
                        break
                if not matched or _is_mention(tokens, index, index + span - 1):
                    continue
                self._register_section(section)
                self._register[section] += 1
                self._register_hits.append(Hit(section, phrase, _window(tokens, index)))

    # --- design fields -------------------------------------------------------

    def _record_field_hit(self, section: str, locator: str, reason: str) -> None:
        self._field_hits.append(Hit(section, locator, reason))

    def _close_option_block(self) -> None:
        """Score the open option block: no Cost warns, Cost without Misses blocks.

        A block carrying Misses and no Cost warns on the same branch as one carrying
        neither — the missing half is the declared price, so Cost absence is checked
        first and short-circuits the Misses check.
        """
        if not self._option_open:
            return
        if not self._option_cost:
            self.cost += 1
            self._record_field_hit(self._section, self._option_locator, _NO_COST_LINE)
        elif not self._option_misses:
            self.misses += 1
            self._record_field_hit(self._section, self._option_locator, _NO_MISSES_VALUE)
        self._option_open = False

    def _close_slot7_section(self) -> None:
        """Warn once for a slot-7 section that closes having opened no option block.

        This is the silent-pass hole for a section whose options are bold lines or H4s,
        or omit the word "Option" in their heading.
        """
        if self._slot_of(self._section) == "7" and not self._option_block_seen:
            self.cost += 1
            self._record_field_hit(self._section, self._section, _NO_OPTION_BLOCK)
        self._option_block_seen = False

    def _close_slot3_section(self) -> None:
        """Clear slot-3 state that must not outlive its section.

        Slot 3 has no section-level "no group opened" counterpart to
        :meth:`_close_slot7_section`: an earlier version fired one, and it went silent
        the instant any valid group appeared earlier in the same section while firing on
        any bullet at all. Each malformed shape now reports for itself the instant it is
        seen.
        """
        self._group_closer = ""

    def _scan_slot7_fields(self, raw: str) -> None:
        if not self._option_open:
            return
        if is_table_row(raw):
            # A table row is scanned PER CELL. Anchoring one label at line start could
            # only ever see whichever field opens the FIRST cell, so a Cost: and Misses:
            # sharing one row, or a label-row/value-row layout, left the other invisible.
            cells = raw.split("|")
            # Resolved FIRST, against this row's cell at the remembered column, before
            # this row's own labels are scanned, and cleared whether it resolves or not.
            # The wait is for the next TABLE ROW rather than the next line: blank and
            # prose lines never reach here, so a later unrelated table in the same option
            # block can still supply the value. Left as the awk original had it — the
            # narrower window is a different verdict, and FR-1 pins the verdicts.
            if self._misses_pending_column > 0:
                if self._misses_pending_column <= len(cells):
                    pending = cells[self._misses_pending_column - 1].strip()
                    if pending and not _SLOT7_FIELD_CELL.match(pending):
                        self._option_misses = True
                self._misses_pending_column = 0
            for position, cell in enumerate(cells, start=1):
                value = cell.strip()
                # Anchored at CELL start — matching anywhere in the cell lets a bold
                # MENTION in Pros/Cons prose satisfy or spoof the gate.
                if value.startswith("**Cost:**"):
                    self._option_cost = True
                if value.startswith("**Misses:**"):
                    self._read_misses_cell(value, cells, position)
            return
        # Non-table forms (plain, list, blockquote): a single label per line, anchored at
        # line start after the list or blockquote marker is removed.
        text = strip_field_prefix(raw)
        if _COST_ANCHOR.match(text):
            self._option_cost = True
        if _MISSES_ANCHOR.match(text):
            # A pipe here is document content, never a cell boundary, so the value runs
            # to the end of the line with no realignment.
            if _MISSES_VALUE.sub("", text, count=1).strip():
                self._option_misses = True

    def _read_misses_cell(self, cell: str, cells: Sequence[str], position: int) -> None:
        value = cell[len("**Misses:**") :].strip()
        # The label may sit ALONE in its own cell with the value in the ADJACENT one —
        # look there only when this cell's value is empty, and only when that next cell
        # is not itself a recognised label: two label-only cells side by side are not a
        # label/value pair.
        if not value and position < len(cells):
            neighbour = cells[position].strip()
            if not _SLOT7_FIELD_CELL.match(neighbour):
                value = neighbour
        if value:
            self._option_misses = True
        else:
            self._misses_pending_column = position

    def _scan_slot3_fields(self, raw: str, section: str) -> None:
        # Remembers whether THIS line found the group already open, before any branch
        # below can change it — the only fact needed to attribute a closure to the label
        # that caused it rather than to whatever bullet happens to follow.
        was_in_group = self._group == "req"
        label = field_label(raw)

        # A list marker directly in front of the bold label fails field_label() too, so
        # the group never changes and, unguarded, the line would fall through to the
        # per-bullet "no From: tag" check, which cannot tell "this bullet IS the
        # malformed opener" from "this bullet lacks a tag".
        bulleted_open = False
        if _BULLETED_BOLD.match(raw):
            bulleted_open = field_label(strip_list_marker(raw)) in _REQUIREMENT_LABELS
        if bulleted_open:
            self.untagged += 1
            self._record_field_hit(section, opening_words(raw), _BULLETED_OPENER)

        if _EXACT_REQUIREMENT_OPENER.match(raw.lstrip()):
            self._group = "req"
            self._scan_bullets = True
            self._group_closer = ""
        elif label in _REQUIREMENT_LABELS:
            # markdown_parser.py collects a padded opener as a real requirement group, so
            # an inline From: tag beneath it is inside a group, not misplaced. The opener
            # itself is reported here, unconditionally, so its own hit tells the author
            # where to look; bullets beneath it are not individually flagged.
            self._group = "req"
            self._scan_bullets = False
            self._group_closer = ""
            self.untagged += 1
            self._record_field_hit(section, opening_words(raw), _PADDED_OPENER)
        elif label == "From":
            pass  # Misplaced — handled as occurrence 1 below; group state unchanged.
        elif label:
            self._group = "other"
            self._scan_bullets = False
            if was_in_group:
                self._group_closer = opening_words(raw)

        # Every bold From: occurrence on the line is validated independently — no
        # first-match or last-match rule. Splitting on the label yields one piece of
        # trailing text per occurrence, correctly scoped between consecutive occurrences.
        occurrences = _FROM_LABEL.split(raw)
        for index, value in enumerate(occurrences[1:], start=2):
            opens_line = index == 2 and label == "From"
            if opens_line or self._group != "req":
                self.from_tags += 1
                if opens_line:
                    self._record_field_hit(section, opening_words(raw), _FROM_OPENS_LINE)
                elif self._group_closer:
                    # The tag is genuinely outside the requirement group, but the group
                    # was closed by an earlier bold label, not by this bullet — pointing
                    # at the tagged bullet reads as "strip this tag", the wrong fix.
                    self._record_field_hit(section, self._group_closer, _FROM_AFTER_CLOSER)
                else:
                    self._record_field_hit(section, opening_words(raw), _FROM_OUTSIDE_GROUP)
            elif not _from_value_is_valid(value):
                self.from_tags += 1
                self._record_field_hit(section, opening_words(raw), _FROM_UNRECOGNISED)

        # A requirement bullet with no From: tag at all, independent of the validation
        # above, since an invalid or misplaced tag still counts as "has a tag". Reuses
        # the split result rather than a second, separately-spelled presence test: two
        # independent tests for "does a From: tag exist here" can disagree on a padded
        # tag and double-count the same bullet as both invalid AND untagged.
        if self._scan_bullets and not bulleted_open and is_bullet(raw):
            if len(occurrences) <= 1:
                self.untagged += 1
                self._record_field_hit(section, opening_words(raw), _BULLET_UNTAGGED)

    def _scan_fields(self, raw: str, section: str) -> None:
        """Check the design fields on one raw line.

        Always the RAW line, never the marker-stripped text the word count uses:
        stripping the list marker puts a bold label that opens a bullet at position 0,
        where the line-start test would misread it as a group opener or a misplaced
        From: tag.
        """
        slot = self._slot_of(section)
        if slot == "7":
            self._scan_slot7_fields(raw)
        elif slot == "3":
            self._scan_slot3_fields(raw, section)

    # --- line dispatch -------------------------------------------------------

    def _open_section(self, line: str, level: int) -> None:
        # Close design-field state for the section being left, before it is overwritten.
        self._close_option_block()
        self._close_slot7_section()
        self._close_slot3_section()
        # Cleared here rather than in _close_slot3_section(): a section ending INSIDE an
        # open group would otherwise leak its state into the next slot-3 section.
        self._group = ""
        self._scan_bullets = False

        name = heading_text(line)
        self._section = self._unique(name)
        self._register_section(self._section)
        # The first H1 is the document title. Five corpus titles matched the Test rule,
        # two of them in documents with no test section at all, dragging that slot down.
        if level == 1 and not self._seen_title:
            self._seen_title = True
            self._titles.add(self._section)
        # Scanned AFTER the switch: a hit in a heading belongs to the section the heading
        # opens, not to the one it closes.
        self._scan_register(name, self._section)

    def _open_subheading(self, line: str) -> None:
        text = heading_text(line)
        self._scan_register(text, self._section)
        slot = self._slot_of(self._section)
        # In slot 7 an EXACT H3 opens a new option block, closing any already open —
        # heading text is not inspected, so a sub-heading omitting the word "Option"
        # still opens one. H4+ opens no block: a sub-heading inside an option belongs to
        # that option.
        if heading_level(line) == 3 and slot == "7":
            self._close_option_block()
            self._option_open = True
            self._option_cost = False
            self._option_misses = False
            self._misses_pending_column = 0
            self._option_locator = text
            self._option_block_seen = True
        # In slot 3, ANY heading level 3+ naming a requirement-group label is a malformed
        # opener — the valid form is inline bold text, never a heading. This line never
        # reaches the field scan, so this is the only place that can catch the shape.
        if slot == "3" and _REQUIREMENT_HEADING.match(text):
            self.untagged += 1
            self._record_field_hit(self._section, text, _HEADING_OPENER)

    def feed(self, line: str, number: int) -> None:
        """Measure one line of the document."""
        # YAML frontmatter is metadata, not prose. Its closing --- also looks exactly
        # like a setext underline following a content line.
        if self._frontmatter.feed(line, number):
            return
        if self._fence.feed(line):
            self._prev_prose = False
            return
        if self._fence.is_open:
            return

        # A setext underline turns the preceding line into a heading. Supporting that
        # would mean retracting the previous line from its section, so this BLOCKs
        # instead: treating the heading as prose merges two sections into one budget, and
        # a zero ceiling count on a document whose sections were silently merged is the
        # same lie as counting past an unclosed fence. Only fires after a PROSE line — a
        # --- after a blank line, a fence, a heading, or a table row is a horizontal rule.
        if is_setext_underline(line):
            if self._prev_prose:
                self._setext += 1
            self._prev_prose = False
            return

        level = heading_level(line)
        if level:
            # H1 and H2 open a section; H3 and deeper roll up into the enclosing section.
            # `#` must open one: without it, prose under a mid-document H1 was attributed
            # to the last `##`.
            if level <= 2:
                self._open_section(line, level)
            else:
                self._open_subheading(line)
            self._prev_prose = False
            return

        if is_table_row(line):
            # Table rows: cell text counts at half weight, register at full.
            self._register_section(self._section)
            cells = strip_blockquote(line).replace("|", " ")
            self._halfwords[self._section] += count_words(cells)
            self._scan_register(line, self._section)
            self._scan_fields(line, self._section)
            self._prev_prose = False
            return

        if is_blank(line):
            self._prev_prose = False
            return

        # A --- after a list item or a blockquote is a thematic break, not a setext
        # underline, so those lines do not arm the setext test.
        self._prev_prose = not (is_bullet(line) or line.lstrip(" \t").startswith(">"))
        text = strip_list_marker(strip_blockquote(line, keep_indent=True))
        self._register_section(self._section)
        self._halfwords[self._section] += 2 * count_words(text)
        self._scan_register(text, self._section)
        self._scan_fields(line, self._section)

    def finish(self) -> Report:
        """Close outstanding state and return the measurement, or raise if it is not one."""
        if self._fence.is_open:
            raise MeasurementError(
                f"unclosed {self._fence.opener} fence in {self._path} — "
                "content after it was not counted.",
                "If a block nests another, make the outer fence ~~~ or four backticks.",
            )
        if self._frontmatter.is_open:
            raise MeasurementError(
                f"unclosed YAML frontmatter in {self._path} — the whole document was skipped."
            )
        if self._setext:
            raise MeasurementError(
                f"{self._setext} setext heading(s) in {self._path} — "
                "not treated as section boundaries,",
                "so their sections would share one budget. Use ## headings.",
            )

        self._close_option_block()
        self._close_slot7_section()
        self._close_slot3_section()

        report = Report(
            path=self._path,
            register_hits=self._register_hits,
            field_hits=self._field_hits,
            cost=self.cost,
            misses=self.misses,
            from_tags=self.from_tags,
            untagged=self.untagged,
        )
        for name in self._order:
            words = self._halfwords[name] // 2
            slot = self._slot_of(name)
            report.rows.append(SectionRow(name, words, self._register[name], slot))
            if slot:
                report.slot_words[slot] = report.slot_words.get(slot, 0) + words
                report.slot_rows[slot] = report.slot_rows.get(slot, 0) + 1
        return report


def analyze(text: str, path: str) -> Report:
    """Measure one document's text, or raise :class:`MeasurementError` if it cannot be.

    Line endings are normalised here, so a CRLF document measures the same as an LF one.
    """
    body = text.replace("\r\n", "\n").replace("\r", "\n")
    # The terminating newline is a terminator, not an empty final line. Keeping it would
    # give a frontmatter-only document a second line, which reads as "no YAML key
    # follows" and cancels the unclosed-frontmatter blocker.
    if body.endswith("\n"):
        body = body[:-1]
    analyzer = _Analyzer(path)
    for number, line in enumerate(body.split("\n"), start=1):
        analyzer.feed(line, number)
    return analyzer.finish()


def analyze_file(path: str | Path) -> Report:
    """Read and measure one document, as UTF-8."""
    name = str(path)
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            text = handle.read()
    except UnicodeDecodeError as err:
        raise MeasurementError(f"not valid UTF-8 — {name}") from err
    except OSError as err:
        raise MeasurementError(f"not readable — {name}: {err.strerror}") from err
    # NUL bytes mean this is not a text document; measuring one reports a number for
    # something that was never prose.
    if "\x00" in text:
        raise MeasurementError(f"NUL bytes in {name} — not a text document")
    return analyze(text, name)


def _row(values: Sequence[object]) -> str:
    name, words, share, register, target, ceiling, verdict = values
    return (
        f"{name!s:<38}\t{words!s:>7}\t{share!s:>7}\t{register!s:>5}"
        f"\t{target!s:>7}\t{ceiling!s:>7}\t{verdict}"
    )


def _ceiling_cell(report: Report, slot: str) -> str:
    ceiling = SECTION_CEILINGS.get(slot)
    if not slot or ceiling is None:
        return "-"
    # A slot spanning several rows shows its accumulated total beside the ceiling, or a
    # small row reads OVER-CEILING with nothing on the line to explain it.
    if report.slot_rows.get(slot, 0) > 1:
        return f"{report.slot_words.get(slot, 0)}/{ceiling}"
    return str(ceiling)


def render(report: Report) -> str:
    """Render a measurement as the tab-separated table and its summary lines."""
    total = report.total_words
    lines = [f"== {report.path} ==", _row(_TABLE_HEADER)]
    for row in report.rows:
        share = f"{100 * row.words / total:.1f}%" if total > 0 else "-"
        target = SECTION_TARGETS[row.slot] if row.slot else "-"
        lines.append(
            _row(
                (
                    row.name,
                    row.words,
                    share,
                    row.register,
                    target,
                    _ceiling_cell(report, row.slot),
                    report.verdict(row.slot),
                )
            )
        )
    if total > DOCUMENT_CEILING:
        document_verdict = "OVER-CEILING"
    elif total > DOCUMENT_TARGET:
        document_verdict = "over-target"
    else:
        document_verdict = "ok"
    lines.append(
        _row(
            (
                _SUMMARY_ROW,
                total,
                "-",
                report.total_register,
                DOCUMENT_TARGET,
                DOCUMENT_CEILING,
                document_verdict,
            )
        )
    )

    if report.register_hits:
        lines.append("")
        lines.append("register hits (detector list is non-exhaustive; the rule outranks it):")
        lines.extend(
            f"  {hit.section}\t{hit.locator}\t{hit.reason}" for hit in report.register_hits
        )
    lines.append("")
    lines.append(f"REGISTER: {report.total_register} hit(s)")
    lines.append(f"CEILING: {report.over_ceiling} slot(s) over ceiling")
    # A heading that matches no slot has no ceiling, so a large unslotted section is
    # invisible to the length gate. Reported rather than blocked: a design doc
    # legitimately carries feature-specific sections.
    lines.append(
        f"UNSLOTTED: {report.unslotted_sections} section(s) "
        f"holding {report.unslotted_words} word(s)"
    )
    # The four design-field counters print unconditionally, like the three above, so a
    # zero reads as checked-and-clean rather than not-checked. This tool states counts,
    # not verdicts — /verify-docs owns the warn-versus-block split.
    lines.append(f"COST: {report.cost} option block(s) or option-less section(s) with no Cost line")
    lines.append(f"MISSES: {report.misses} Cost line(s) with no Misses value")
    lines.append(f"FROM: {report.from_tags} misplaced or unrecognised From tag(s)")
    lines.append(
        f"UNTAGGED: {report.untagged} requirement bullet(s) with no From tag, "
        "or malformed requirement-group opener(s)"
    )
    if report.field_hits:
        lines.append("")
        lines.append("design-field hits (section, locator, reason):")
        lines.extend(f"  {hit.section}\t{hit.locator}\t{hit.reason}" for hit in report.field_hits)
    return "\n".join(lines) + "\n"
