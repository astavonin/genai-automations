"""Fence-aware Markdown section extraction: one anchor heading's body, verbatim.

Built for ``tests/verify-config-consistency.sh``, which asserts the presence or absence
of literal tokens inside one named section of a public command file. That suite carries
no Markdown parser of its own — every fence rule it would need already lives in
:class:`docgate.markdown.FenceTracker`, and a second copy would be exactly the class of
drift the suite exists to catch.
"""

from __future__ import annotations

from .markdown import FenceTracker, heading_level, heading_text

__all__ = [
    "AmbiguousAnchorError",
    "SectionNotFoundError",
    "UnclosedFenceError",
    "extract_section",
]


class SectionNotFoundError(Exception):
    """The anchor heading does not occur in the document.

    Raised rather than returning an empty range: an absence assertion run against an
    empty extraction passes vacuously, which is the exact shape that lets a gutted rule
    stay green. The caller must fail loudly instead of silently measuring nothing.
    """


class AmbiguousAnchorError(Exception):
    """More than one heading in the document matches the anchor.

    Raised rather than silently returning the first match's body: a caller asserting
    against "the" section would otherwise read whichever copy happens to come first —
    the same silent-pass shape :class:`SectionNotFoundError`'s docstring argues
    against for an absent heading applies equally to a duplicate one.
    """


class UnclosedFenceError(Exception):
    """A fence opened in the document was never closed.

    Raised instead of letting the boundary scan run to end of file: an open fence
    hides every later heading from :func:`docgate.markdown.heading_level`, so the
    section would otherwise silently swallow the rest of the document — either
    extending a found section past its real end, or hiding the anchor itself behind a
    misleading "no heading matching" report. :func:`docgate.metrics.analyze` raises
    the same way for the same reason.
    """


def _matches(candidate: str, anchor_name: str) -> bool:
    """Report whether a heading's text names the anchor, exactly or as its label.

    This repository's command files write headings as ``Label: Description`` (`` "Step
    2b: Resolve Epic and Instantiate Epic Folder" ``). An anchor naming just the label
    (``"Step 2b"``) must still find it, so the label is accepted as a match when it is
    followed by a colon — anchored on the colon rather than a bare prefix so ``"Step 2"``
    cannot also match ``"Step 20: ..."``.
    """
    return candidate == anchor_name or candidate.startswith(f"{anchor_name}:")


def extract_section(text: str, anchor: str) -> str:
    """Return the body of the section ``anchor`` opens, fenced blocks left intact.

    ``anchor`` is a full ATX heading line, e.g. ``"## Output"`` or ``"### Step 2b"`` —
    its marker run fixes the level the closing boundary is measured against. The body
    runs from the line after the matching heading to the next heading at that level or
    shallower, or to end of file when none follows. A line that only looks like a
    heading because it sits inside a fenced block never opens or closes a section:
    :class:`FenceTracker` is fed every line, mirroring the same ahead-of-heading-check
    placement :mod:`docgate.metrics` uses, so a column-0 ``#`` inside a pasted fenced
    example is never mistaken for a boundary.

    Raises :class:`ValueError` when ``anchor`` is not itself a well-formed ATX heading,
    :class:`UnclosedFenceError` when a fence in the document is never closed,
    :class:`SectionNotFoundError` when no line in ``text`` opens a matching section, and
    :class:`AmbiguousAnchorError` when more than one line does.
    """
    anchor_level = heading_level(anchor)
    if not anchor_level:
        raise ValueError(f"not an ATX heading: {anchor!r}")
    anchor_name = heading_text(anchor)

    body = text.replace("\r\n", "\n").replace("\r", "\n")
    if body.endswith("\n"):
        body = body[:-1]
    lines = body.split("\n")

    # One fence-aware pass computes every line's effective heading level up front, so
    # ambiguity and the unclosed-fence check can both be decided before any boundary is
    # chosen — a second pass over `collected` could not undo a boundary picked too early.
    fence = FenceTracker()
    levels: list[int] = []
    for line in lines:
        is_marker = fence.feed(line)
        fenced_content = not is_marker and fence.is_open
        levels.append(0 if is_marker or fenced_content else heading_level(line))

    if fence.is_open:
        # Checked before the anchor search: an open fence hides every heading after it,
        # so a "no heading matching" report from here would name the wrong cause — the
        # anchor may well be present, just behind the swallowed range.
        raise UnclosedFenceError(f"unclosed {fence.opener} fence in the document")

    matches = [
        index
        for index, (line, level) in enumerate(zip(lines, levels))
        if level == anchor_level and _matches(heading_text(line), anchor_name)
    ]
    if not matches:
        raise SectionNotFoundError(f"no heading matching {anchor!r} in the document")
    if len(matches) > 1:
        raise AmbiguousAnchorError(f"{len(matches)} headings match {anchor!r} in the document")

    start = matches[0] + 1
    end = len(lines)
    for index in range(start, len(lines)):
        if levels[index] and levels[index] <= anchor_level:
            end = index
            break
    return "\n".join(lines[start:end])
