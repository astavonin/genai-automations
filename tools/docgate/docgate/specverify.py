"""Mechanical verification of an appendix spec's fact contract.

`APPENDIX-SPEC-TEMPLATE.md` §5 makes every on-device claim reproducible: the row records
the command, the captured output, the host, and the date. This module re-runs what the
row says it ran and checks that the tokens its Conclusion turns on are still there, plus
the two document-only Source Requirements — SR7 field presence and SR8 §2↔§5 graph
consistency.

Nothing here knows about design-doc semantics; that is :mod:`docgate.metrics`. The two
share :mod:`docgate.markdown` and the exit contract in :mod:`docgate.cli`.

Two failure classes are in scope: fabricated evidence, where the command was never run,
and decayed facts, where the row was true when measured and is not now. Over-reach on
genuine evidence is not — a row can reproduce perfectly and still support a claim its
output does not entail, and both heuristics measured against the corpus were noise.
"""

from __future__ import annotations

import http.client
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from enum import StrEnum
from typing import Callable, Sequence

from .markdown import FenceTracker, field_label, heading_level, heading_text, is_blank
from .metrics import MeasurementError

__all__ = [
    "COVERS",
    "REQUIRED_FIELDS",
    "SENTINEL",
    "ClaimRow",
    "Fetcher",
    "GraphBreak",
    "RowResult",
    "Runner",
    "SpecDocument",
    "SpecReport",
    "Verdict",
    "VerificationRow",
    "backtick_spans",
    "cites_web_page",
    "fetch_document",
    "field_breaks",
    "graph_breaks",
    "normalise",
    "parse_spec",
    "raw_url",
    "read_text",
    "render",
    "run_over_ssh",
    "sequence_breaks",
    "source_location",
    "spec_kind",
    "ssh_host",
    "token_set",
    "verify",
]

#: Appended to every piped script; a reply not ending in it means the row never ran.
SENTINEL = "__docgate_spec_verify_ran__"

#: Fields SR7 requires on every §5 row, widened from where-and-when to all six.
REQUIRED_FIELDS = (
    "Establishes",
    "Method",
    "Ran on",
    "Run date",
    "Conclusion",
    "Side effects",
)

#: Printed on every scanning run, so a reader seeing `FAIL: 0` also sees what it misses.
COVERS = (
    "fabricated evidence and decayed facts, except that a claim asserting something is "
    "absent is not re-checked. Over-reach on genuine evidence is NOT checked."
)

SSH_TIMEOUT_SECONDS = 60.0
FETCH_TIMEOUT_SECONDS = 30.0
_SSH_CONNECT_TIMEOUT_SECONDS = 10

_RAW_HOST = "raw.githubusercontent.com"

#: An output block opens at four columns; a tab counts to the next four-column stop.
_INDENT_COLUMNS = 4
_TAB_WIDTH = 4

_CLAIM_ID = re.compile(r"^C\d+$")
_ROW_ID = re.compile(r"^V(?P<number>\d+)\b")
_SECTION_NUMBER = re.compile(r"^(?P<number>\d+)\.")
_FIELD_VALUE = re.compile(r"^\*\*[^*]+:\*\*(?P<value>.*)$")
_BACKTICK_SPAN = re.compile(r"`([^`]+)`")
_TABLE_DELIMITER = re.compile(r"^[\s|:-]+$")
_PLACEHOLDER = re.compile(r"<[^>]*>")
_RUN_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_SSH_SPAN = re.compile(r"^ssh\s+(?P<host>\S+)$")
_HEADING_INDENT = re.compile(r"^ {0,3}")
# A host reaches ssh as an argv element, so no shell metacharacter can act; a leading
# dash would still be read as an option, and an embedded space would split the target.
_SSH_HOST = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*(@[A-Za-z0-9_][A-Za-z0-9_.-]*)?$")
_REPO_SPAN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_WEB_URL = re.compile(r"^https?://", re.IGNORECASE)

#: The seam both channels sit behind: a host plus a script in, combined text out.
Runner = Callable[[str, str], str]
#: The fetch counterpart: a location in, the document text out, or None for no document.
Fetcher = Callable[[str], str | None]


class Verdict(StrEnum):
    """The three verdicts FR-9 allows, one per §5 row."""

    PASS = "PASS"
    FAIL = "FAIL"
    SKIP = "SKIP"


@dataclass(frozen=True)
class ClaimRow:
    """One §2 claim: its ID, what it says verifies it, and whether its table says so."""

    claim_id: str
    verified_by: tuple[str, ...]
    has_verified_column: bool


@dataclass(frozen=True)
class VerificationRow:
    """One `### V<N>` row: its fields, its command blocks, and its captured output.

    ``parse_breaks`` carries what the parse itself rejected — a structure that makes the
    fields or the commands not the ones the author wrote for this row.
    """

    row_id: str
    number: int
    fields: dict[str, str]
    commands: tuple[str, ...]
    outputs: tuple[str, ...]
    parse_breaks: tuple[str, ...] = ()

    def value(self, label: str) -> str:
        """Return the row's value for one field label, or an empty string."""
        return self.fields.get(label, "")

    @property
    def recorded_output(self) -> str:
        """Every captured output block joined, in document order.

        The token check reads the row's output as one text: the blocks are an ordered
        list rather than one per row, and no block pairs with a command block.
        """
        return "\n".join(self.outputs)


@dataclass(frozen=True)
class SpecDocument:
    """One parsed appendix spec: its §2 claims and its §5 verification rows."""

    path: str
    claims: tuple[ClaimRow, ...]
    rows: tuple[VerificationRow, ...]


@dataclass(frozen=True)
class GraphBreak:
    """One §2↔§5 inconsistency and the row it is reported against.

    ``against_claim`` decides the counters: `GRAPH:` counts exactly the claim-side
    breaks, while a §5-side break fails its row and is counted there instead.
    """

    target: str
    against_claim: bool
    message: str


@dataclass(frozen=True)
class RowResult:
    """One §5 row's verdict, with the one-line reason FR-9 requires for FAIL and SKIP."""

    row_id: str
    verdict: Verdict
    reason: str = ""
    details: tuple[str, ...] = ()
    tokens_checked: int = 0


@dataclass(frozen=True)
class SpecReport:
    """Everything one run measured, before rendering."""

    path: str
    results: tuple[RowResult, ...]
    breaks: tuple[GraphBreak, ...]
    claim_count: int

    @property
    def passed(self) -> int:
        """Count §5 rows holding a PASS verdict."""
        return sum(1 for result in self.results if result.verdict is Verdict.PASS)

    @property
    def skipped(self) -> int:
        """Count §5 rows holding a SKIP verdict."""
        return sum(1 for result in self.results if result.verdict is Verdict.SKIP)

    @property
    def failed_rows(self) -> int:
        """Count §5 rows holding a FAIL verdict, each row once however many breaks it holds."""
        return sum(1 for result in self.results if result.verdict is Verdict.FAIL)

    @property
    def graph_count(self) -> int:
        """Count the graph breaks reported against a §2 claim row."""
        return sum(1 for issue in self.breaks if issue.against_claim)

    @property
    def failed(self) -> int:
        """The `FAIL:` total — failing rows plus claim-side graph breaks."""
        return self.failed_rows + self.graph_count

    @property
    def token_total(self) -> int:
        """Count the tokens checked over every row that carried one."""
        return sum(result.tokens_checked for result in self.results)

    @property
    def token_rows(self) -> int:
        """Count the rows carrying at least one token, which is what `TOKENS:` spans."""
        return sum(1 for result in self.results if result.tokens_checked)


def normalise(text: str) -> str:
    """Collapse every whitespace run to one space, so a token may span a line break.

    Both sides of every match go through this: §5's own preamble concedes that spacing,
    blank lines and stdout/stderr interleaving are not reproducible, and a byte
    comparison ran 53% false positives against zero real drift on the reference corpus.
    """
    return " ".join(text.split())


def _indent_columns(line: str) -> int:
    width = 0
    for char in line:
        if char == " ":
            width += 1
        elif char == "\t":
            width += _TAB_WIDTH - (width % _TAB_WIDTH)
        else:
            break
    return width


def _field_value(line: str) -> str:
    match = _FIELD_VALUE.match(line.strip())
    return match.group("value").strip() if match else ""


def backtick_spans(text: str) -> tuple[str, ...]:
    """Return every backtick-quoted span of a line, in order."""
    return tuple(_BACKTICK_SPAN.findall(text))


class _OutputBlockReader:
    """Collects the indented output blocks of one row.

    The one primitive `docgate.markdown` does not carry. Two measured properties fix its
    contract: a blank line does not close a block — 69 sit interior to output blocks in
    the reference corpus — and a row carries a list of blocks rather than one, so nothing
    may pair a block with a command block by position.
    """

    def __init__(self) -> None:
        self._blocks: list[str] = []
        self._current: list[str] = []
        self._pending: list[str] = []

    def feed(self, line: str) -> None:
        """Consume one line that sits outside every fence."""
        if is_blank(line):
            # Held rather than emitted: a blank run reaching the closing line belongs to
            # neither block, and one reaching another indented line is interior.
            if self._current:
                self._pending.append(line)
            return
        if _indent_columns(line) >= _INDENT_COLUMNS:
            self._current.extend(self._pending)
            self._pending.clear()
            self._current.append(line)
        else:
            self.flush()

    def flush(self) -> None:
        """Close whatever block is open, discarding a trailing blank run."""
        if self._current:
            self._blocks.append("\n".join(self._current))
        self._current.clear()
        self._pending.clear()

    def blocks(self) -> tuple[str, ...]:
        """Return every block collected so far, in document order."""
        self.flush()
        return tuple(self._blocks)


class _TableReader:
    """Reads the claim rows of one §2 table, keyed on its own header cells."""

    def __init__(self, header: str) -> None:
        cells = _split_cells(header)
        labels = [cell.strip().lower() for cell in cells]
        self._id_column = labels.index("id") if "id" in labels else 0
        self._verified_column = labels.index("verified by") if "verified by" in labels else -1

    @property
    def has_verified_column(self) -> bool:
        """Report whether this table carries a `Verified by` column at all.

        A table without one is an unverified table, and SR1 carves its rows out; keying
        that on table order instead would fail every row of the corpus's third table.
        """
        return self._verified_column >= 0

    def read(self, line: str) -> ClaimRow | None:
        """Return the claim row this table line holds, or None when it holds none."""
        cells = _split_cells(line)
        if len(cells) <= self._id_column:
            return None
        claim_id = cells[self._id_column].strip()
        if not _CLAIM_ID.match(claim_id):
            return None
        verified: tuple[str, ...] = ()
        if self.has_verified_column and len(cells) > self._verified_column:
            verified = tuple(
                entry.strip() for entry in cells[self._verified_column].split(",") if entry.strip()
            )
        return ClaimRow(claim_id, verified, self.has_verified_column)


def _split_cells(line: str) -> list[str]:
    return line.strip().removeprefix("|").removesuffix("|").split("|")


def spec_kind(text: str) -> str:
    """Return ``appendix``, ``main`` or an empty string, from the header field alone.

    C-3: keying on §5's number or title instead lets a spec that lost or retitled §5 read
    as a main spec and skip every check.
    """
    fences = FenceTracker()
    for line in text.splitlines():
        marker = fences.feed(line)
        if fences.is_open or marker:
            continue
        if heading_level(line) == 2:
            break
        label = field_label(line)
        if label == "Page":
            return "appendix"
        if label == "Article":
            return "main"
    return ""


def _unindented(line: str) -> str:
    """Remove the one to three leading spaces CommonMark still reads a heading through.

    A fourth column makes the line indented code, so `### imx477 …` inside captured
    output is left where it is.
    """
    return _HEADING_INDENT.sub("", line, count=1)


def parse_spec(text: str, path: str) -> SpecDocument:
    """Parse one appendix spec into its §2 claims and its §5 verification rows."""
    fences = FenceTracker()
    claims: list[ClaimRow] = []
    rows: list[VerificationRow] = []
    section = ""
    table: _TableReader | None = None
    builder: _RowBuilder | None = None

    for line in text.splitlines():
        marker = fences.feed(line)
        inside_fence = fences.is_open or marker
        level = heading_level(_unindented(line))

        if inside_fence:
            if builder is not None:
                # A heading reached with the fence still open means the fence never
                # closed, so the following row's commands are landing in this script.
                if fences.is_open and level in (2, 3):
                    builder.mark_open_fence()
                builder.feed_fenced(line, marker=marker, closing=not fences.is_open)
            continue

        if level in (2, 3):
            if builder is not None:
                rows.append(builder.build())
                builder = None
            table = None
            heading = heading_text(_unindented(line))
            if level == 2:
                match = _SECTION_NUMBER.match(heading)
                section = match.group("number") if match else ""
            elif section == "5":
                builder = _RowBuilder.open(heading)
            continue

        if section == "2":
            table = _feed_claim_table(line, table, claims)
        elif section == "5" and builder is not None:
            builder.feed(line)

    if builder is not None:
        rows.append(builder.build())
    return SpecDocument(path, tuple(claims), tuple(rows))


def _feed_claim_table(
    line: str,
    table: _TableReader | None,
    claims: list[ClaimRow],
) -> _TableReader | None:
    stripped = line.strip()
    if not stripped.startswith("|"):
        # A table is a contiguous run of pipe rows, so anything else closes it and the
        # next run reads its own header — §2 carries three tables of three column shapes.
        return None
    if table is None:
        return _TableReader(line)
    if _TABLE_DELIMITER.match(stripped):
        return table
    claim = table.read(line)
    if claim is not None:
        claims.append(claim)
    return table


class _RowBuilder:
    """Accumulates one `### V<N>` row until the next level-2 or level-3 heading.

    A heading is read through up to three leading spaces, which is what CommonMark
    renders as one; at four columns the line is captured output, so the indented `### …`
    lines a row records end nothing.
    """

    def __init__(self, row_id: str, number: int) -> None:
        self._row_id = row_id
        self._number = number
        self._fields: dict[str, str] = {}
        #: Labels seen twice, as an ordered set — a label repeated is still one rejection.
        self._duplicated: dict[str, None] = {}
        self._open_fence = False
        self._trailing_fence = False
        self._commands: list[str] = []
        self._command: list[str] = []
        self._outputs = _OutputBlockReader()

    @classmethod
    def open(cls, heading: str) -> _RowBuilder | None:
        """Return a builder for a `V<N>` heading, or None for any other level-3 heading."""
        match = _ROW_ID.match(heading.strip())
        if match is None:
            return None
        number = int(match.group("number"))
        return cls(f"V{number}", number)

    def feed(self, line: str) -> None:
        """Consume one row line sitting outside every fence."""
        # An indented line belongs to captured output, where a `**Label:**` is text the
        # command printed rather than a field this row declares.
        if _indent_columns(line) < _INDENT_COLUMNS:
            label = field_label(line)
            if label in REQUIRED_FIELDS:
                # First wins, and the row is rejected for it: `none` followed by
                # `mutating — …` would otherwise run on a declaration its author retracted.
                if label in self._fields:
                    self._duplicated[label] = None
                else:
                    self._fields[label] = _field_value(line)
        self._outputs.feed(line)

    def feed_fenced(self, line: str, *, marker: bool, closing: bool) -> None:
        """Consume one fence marker or one line of fenced content."""
        self._outputs.flush()
        if not marker:
            self._command.append(line)
        elif closing:
            self._commands.append("\n".join(self._command))
            self._command.clear()
        elif "Conclusion" in self._fields:
            # A row's commands precede the Conclusion it draws from them, so a fence
            # opening after it holds text of the following section or of no row at all.
            # Closing that fence puts it past both the heading guard and `unterminated`.
            self._trailing_fence = True

    def mark_open_fence(self) -> None:
        """Record that a heading arrived while this row's command fence was still open."""
        self._open_fence = True

    def build(self) -> VerificationRow:
        """Finish the row, closing an output block or an unterminated command block."""
        # Read before the flush below clears it: §5 is the last section of every spec in
        # the corpus, so a fence left open after the last row's Conclusion meets no
        # heading to trip `mark_open_fence()` and its content reaches this row's script.
        unterminated = bool(self._command)
        if self._command:
            self._commands.append("\n".join(self._command))
            self._command.clear()
        breaks = [f"**{label}:** is declared more than once" for label in self._duplicated]
        if self._trailing_fence:
            breaks.insert(
                0,
                "a command fence opens after this row's **Conclusion:** — the lines it "
                "holds merged into this row's script",
            )
        if self._open_fence or unterminated:
            breaks.insert(
                0,
                "a command fence is still open where this row ends — the lines after it "
                "merged into this row's script",
            )
        return VerificationRow(
            self._row_id,
            self._number,
            dict(self._fields),
            tuple(self._commands),
            self._outputs.blocks(),
            tuple(breaks),
        )


def read_text(path: str) -> str:
    """Read one spec file as UTF-8, or raise when it cannot be read."""
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            return handle.read()
    except UnicodeDecodeError as err:
        raise MeasurementError(f"not valid UTF-8 — {path}") from err
    except OSError as err:
        raise MeasurementError(f"not readable — {path}: {err.strerror}") from err


def field_breaks(row: VerificationRow) -> tuple[str, ...]:
    """Return one message per parse and SR7 field rejection on this row.

    The parse's own breaks lead: a row whose fields or commands are not the ones its
    author wrote for it is rejected before any of them is read. A missing `Conclusion:`
    is a rejection like any other: left to the token check it would yield an empty token
    set and a vacuous PASS.
    """
    problems: list[str] = list(row.parse_breaks)
    for label in REQUIRED_FIELDS:
        problem = _field_break(label, row.fields.get(label))
        if problem:
            problems.append(f"**{label}:** {problem}")
    return tuple(problems)


def _field_break(label: str, value: str | None) -> str:
    if value is None:
        return "is absent"
    if not value:
        return "is empty"
    if _PLACEHOLDER.search(value):
        return f"is still a placeholder — {value}"
    if value.strip().upper() == "TBD":
        return "is still TBD"
    # `Ran on:` carries no shape rule: each resolver decides the shape it needs, and one
    # imposed here would fail every documentation row, none of which names an ssh host.
    if label == "Run date" and not _RUN_DATE.match(value.strip()):
        return f"is not YYYY-MM-DD — {value}"
    if label == "Side effects" and not _side_effects_legal(value):
        return f"reads neither `none` nor `mutating — <what changes>` — {value}"
    return ""


def _side_effects_legal(value: str) -> bool:
    text = value.strip().lower()
    return text == "none" or (text.startswith("mutating") and bool(_mutating_tail(value)))


def _mutating_tail(value: str) -> str:
    """Return what a `mutating` row declares it changes, or an empty string."""
    text = value.strip()
    if not text.lower().startswith("mutating"):
        return ""
    return text[len("mutating") :].strip(" \t:—–-")


def graph_breaks(document: SpecDocument) -> tuple[GraphBreak, ...]:
    """Return every SR8 inconsistency between §2's claim tables and §5's rows."""
    breaks: list[GraphBreak] = []
    seen: dict[str, ClaimRow] = {}
    for claim in document.claims:
        if claim.claim_id in seen:
            breaks.append(
                GraphBreak(
                    claim.claim_id,
                    True,
                    f"{claim.claim_id} appears in more than one §2 table",
                )
            )
        else:
            seen[claim.claim_id] = claim

    establishes = {row.row_id: _establishes(row) for row in document.rows}
    for claim in document.claims:
        if not claim.has_verified_column:
            continue
        if not claim.verified_by:
            breaks.append(
                GraphBreak(claim.claim_id, True, f"{claim.claim_id} has an empty `Verified by`")
            )
            continue
        for entry in claim.verified_by:
            if entry not in establishes:
                breaks.append(
                    GraphBreak(
                        claim.claim_id,
                        True,
                        f"{claim.claim_id} is verified by {entry}, which is no §5 row",
                    )
                )
            elif claim.claim_id not in establishes[entry]:
                breaks.append(
                    GraphBreak(
                        claim.claim_id,
                        True,
                        f"{claim.claim_id} is verified by {entry}, whose "
                        f"**Establishes:** omits it",
                    )
                )

    for row in document.rows:
        for claim_id in establishes[row.row_id]:
            if claim_id not in seen:
                breaks.append(
                    GraphBreak(
                        row.row_id,
                        False,
                        f"**Establishes:** names {claim_id}, which is no §2 claim",
                    )
                )
    return tuple(breaks)


def _establishes(row: VerificationRow) -> tuple[str, ...]:
    return tuple(
        entry.strip()
        for entry in row.value("Establishes").split(",")
        if _CLAIM_ID.match(entry.strip())
    )


def token_set(conclusion: str, recorded_output: str) -> tuple[str, ...]:
    """Return the Conclusion's backticked spans that also sit in the recorded output.

    One filter, sound in both directions: a token the author never had in the output was
    never SR6-supported, so flagging it would fire on authoring style rather than on
    evidence; a token that was recorded and is now gone is decay or fabrication.
    Duplicates collapse — the same literal quoted twice is one fact, not two.
    """
    haystack = normalise(recorded_output)
    kept: list[str] = []
    for span in backtick_spans(conclusion):
        token = normalise(span)
        if token and token in haystack and span not in kept:
            kept.append(span)
    return tuple(kept)


def ssh_host(ran_on: str) -> str:
    """Return the host the first `ssh <host>` span names, or an empty string."""
    for span in backtick_spans(ran_on):
        match = _SSH_SPAN.match(span.strip())
        if match is None:
            continue
        host = match.group("host")
        return host if _SSH_HOST.match(host) else ""
    return ""


def source_location(ran_on: str) -> tuple[str, str, str]:
    """Return (path, repo, branch) from the first three backticked spans, or empties.

    Trailing clauses are ignored: the corpus's rows carry a table name or a struct field
    after the branch, and reading past the third span would reject them.
    """
    spans = [span.strip() for span in backtick_spans(ran_on)]
    if len(spans) < 3:
        return "", "", ""
    path, repo, branch = spans[0], spans[1], spans[2]
    if not path or not branch or not _REPO_SPAN.match(repo):
        return "", "", ""
    return path, repo, branch


def cites_web_page(ran_on: str) -> bool:
    """Report whether the row cites an http URL, which is a different resolver."""
    spans = backtick_spans(ran_on)
    return bool(spans) and _WEB_URL.match(spans[0].strip()) is not None


def raw_url(path: str, repo: str, branch: str) -> str:
    """Build the raw.githubusercontent.com URL for one file at one branch."""
    quoted = urllib.parse.quote(f"{repo}/{branch}/{path}", safe="/")
    return f"https://{_RAW_HOST}/{quoted}"


def run_over_ssh(host: str, script: str, *, timeout: float = SSH_TIMEOUT_SECONDS) -> str:
    """Pipe one script to `bash -s` on a host and return stdout and stderr joined.

    Every transport failure returns text not ending in the sentinel rather than raising,
    so the caller's one signal for "the row did not run" covers a refused connection, a
    missing ssh binary and a hang alike. The command's own exit status is never read: the
    corpus holds rows whose non-zero exit *is* the evidence, and ssh returns 255 both for
    a remote 255 and for its own transport failure.
    """
    try:
        completed = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                f"ConnectTimeout={_SSH_CONNECT_TIMEOUT_SECONDS}",
                host,
                "bash -s",
            ],
            input=script,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            # A row's output is whatever the board printed, and one undecodable byte in it
            # would otherwise raise past this function and lose every row already measured.
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return completed.stdout


def fetch_document(location: str, *, timeout: float = FETCH_TIMEOUT_SECONDS) -> str | None:
    """Fetch one document over HTTPS, or return None when none came back.

    A 404, a 403, a 5xx, a DNS failure and a hang are all "no document", which takes the
    same transport SKIP the ssh side has — so only a 200 missing a recorded block fails.
    """
    # The scheme is checked rather than trusted: `Ran on:` is document text, and an
    # opener handed `file://` or `ftp://` would read a local path as a fetched document.
    if not location.startswith("https://"):
        return None
    request = urllib.request.Request(location, headers={"User-Agent": "docgate/spec-verify"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                return None
            body: bytes = response.read()
    # `http.client.HTTPException` is neither an `OSError` nor a `ValueError`, so a
    # truncated or malformed response would otherwise escape and lose every row already
    # measured on the board.
    except (urllib.error.URLError, OSError, ValueError, http.client.HTTPException):
        return None
    return body.decode("utf-8", errors="replace")


def verify(
    document: SpecDocument,
    *,
    runner: Runner | None = None,
    fetcher: Fetcher | None = None,
) -> SpecReport:
    """Run the three checks over one parsed spec and return what they found.

    Document-only running is the seam's absence rather than a flag: with no ``runner``
    no subprocess is spawned and every on-device row reports SKIP.
    """
    breaks = graph_breaks(document)
    row_breaks: dict[str, list[str]] = {}
    for issue in breaks:
        if not issue.against_claim:
            row_breaks.setdefault(issue.target, []).append(issue.message)

    sequence = sequence_breaks(document.rows)
    results = [
        _verify_row(row, sequence[index], row_breaks.get(row.row_id, ()), runner, fetcher)
        for index, row in enumerate(document.rows)
    ]
    return SpecReport(document.path, tuple(results), breaks, len(document.claims))


def sequence_breaks(rows: Sequence[VerificationRow]) -> list[str]:
    """Return one message per row whose ID is not the next in the walk, empty for the rest.

    Walked in order rather than compared as a set: a set check reads V1, V2, V2 as
    complete, and an ID duplicated in place is one of the three causes named below. The
    break reports against the row after the gap, or against a repeat's second copy.
    """
    messages: list[str] = []
    expected = 1
    for row in rows:
        messages.append(
            ""
            if row.number == expected
            else (
                f"row ID out of sequence — expected V{expected}, found {row.row_id}: a row was "
                "deleted without renumbering, an unclosed command fence swallowed one, or an "
                "ID is duplicated in place"
            )
        )
        expected = row.number + 1
    return messages


def _verify_row(
    row: VerificationRow,
    sequence_break: str,
    row_graph_breaks: Sequence[str],
    runner: Runner | None,
    fetcher: Fetcher | None,
) -> RowResult:
    problems = list(field_breaks(row))
    if sequence_break:
        problems.insert(0, sequence_break)
    problems.extend(row_graph_breaks)
    if problems:
        return RowResult(
            row.row_id,
            Verdict.FAIL,
            problems[0],
            tuple(problems[1:]),
        )

    # `Side effects:` is read before `Method:`: a mutating row is never re-executed, and
    # a verifier that ran one would hand the board back in a state it was not found in.
    tail = _mutating_tail(row.value("Side effects"))
    if tail:
        return RowResult(row.row_id, Verdict.SKIP, f"declared mutating — {tail}, never re-run")

    method = row.value("Method").strip().lower()
    if method == "on-device":
        return _verify_on_device(row, runner)
    if method == "documentation lookup":
        return _verify_documentation(row, fetcher)
    return RowResult(
        row.row_id,
        Verdict.SKIP,
        f"no resolver for **Method:** value — {row.value('Method')}",
    )


def _verify_on_device(row: VerificationRow, runner: Runner | None) -> RowResult:
    host = ssh_host(row.value("Ran on"))
    if not host:
        return RowResult(
            row.row_id,
            Verdict.SKIP,
            f"**Ran on:** names no `ssh <host>` — {row.value('Ran on')}",
        )
    # The document's own defect is reported ahead of the channel's absence, so a
    # document-only run gives the same reason a live one would.
    # A fence closed immediately parses to one empty command, which walks past a truth
    # test and pipes the appended completion line to the board by itself.
    if not any(command.strip() for command in row.commands):
        return RowResult(row.row_id, Verdict.SKIP, "no command block to run")
    # The token check's other operand: with no recorded output the haystack is empty,
    # every token the Conclusion asserts is dropped, and the row passes on transport alone.
    if not row.outputs:
        return RowResult(row.row_id, Verdict.SKIP, "no recorded output block to match")
    if runner is None:
        return RowResult(row.row_id, Verdict.SKIP, "no execution channel — document-only run")

    # The row's commands run inside a brace group so their stderr folds into stdout on
    # the remote side, ahead of the sentinel, rather than racing it: remote stderr is
    # unbuffered while remote stdout through a pipe is block-buffered, so a command
    # writing to stderr can otherwise have that line arrive after the sentinel already
    # has, and `_completed()` reports a transport failure for a row that ran cleanly.
    # `{ ...; }` runs in the current shell rather than a subshell, so it costs no fork
    # and leaves a row's variable assignments visible to the rest of its own script —
    # a `( ... )` subshell would work too, but only by accident for this corpus, since
    # nothing here reads a variable a background job or a nested block set.
    script = "{\n" + "\n".join(row.commands) + "\n} 2>&1\n" + f"printf '%s\\n' {SENTINEL}\n"
    fresh = _completed(runner(host, script))
    if fresh is None:
        return RowResult(row.row_id, Verdict.SKIP, "transport failed")

    tokens = token_set(row.value("Conclusion"), row.recorded_output)
    haystack = normalise(fresh)
    missing = [token for token in tokens if normalise(token) not in haystack]
    if missing:
        return RowResult(
            row.row_id,
            Verdict.FAIL,
            f"a recorded token is absent from the fresh output — `{normalise(missing[0])}`",
            tuple(f"also absent: `{normalise(token)}`" for token in missing[1:])
            + (f"looked in {len(fresh.splitlines())} line(s) of fresh output from {host}",),
            len(tokens),
        )
    return RowResult(row.row_id, Verdict.PASS, tokens_checked=len(tokens))


def _completed(fresh: str) -> str | None:
    """Return the reply without its completion line, or None when the row never ran.

    The sentinel must be the reply's last non-empty line rather than sit anywhere in it:
    the script is document text, so a row printing the sentinel itself would otherwise
    stand in for the appended completion command having run. Only that one line is
    scrubbed, leaving whatever the row genuinely printed for the token check.
    """
    lines = fresh.splitlines()
    for index in reversed(range(len(lines))):
        if is_blank(lines[index]):
            continue
        if lines[index].strip() != SENTINEL:
            return None
        return "\n".join(lines[:index] + lines[index + 1 :])
    return None


def _verify_documentation(row: VerificationRow, fetcher: Fetcher | None) -> RowResult:
    ran_on = row.value("Ran on")
    if cites_web_page(ran_on):
        return RowResult(
            row.row_id,
            Verdict.SKIP,
            "cites a web page — HTML quote matching is a different resolver",
        )
    path, repo, branch = source_location(ran_on)
    if not path:
        return RowResult(
            row.row_id,
            Verdict.SKIP,
            f"**Ran on:** names no `<path>` from `<repo>` branch `<branch>` — {ran_on}",
        )
    if not row.outputs:
        return RowResult(row.row_id, Verdict.SKIP, "no recorded output block to match")
    if fetcher is None:
        return RowResult(row.row_id, Verdict.SKIP, "no fetch channel — document-only run")

    body = fetcher(raw_url(path, repo, branch))
    if body is None:
        return RowResult(row.row_id, Verdict.SKIP, "transport failed")

    haystack = normalise(body)
    # Each block is matched on its own: a row's blocks are an ordered list and the corpus
    # holds a row with one command block against two output blocks, so no positional
    # pairing — and no concatenation, which would demand the two be adjacent in the file.
    for block in row.outputs:
        quote = normalise(block)
        if quote and quote not in haystack:
            return RowResult(
                row.row_id,
                Verdict.FAIL,
                "a recorded quote is absent from the fetched file — the author misquoted, "
                "or the file changed under the cited branch",
                (
                    f"looked for: {_excerpt(quote)}",
                    f"fetched: {raw_url(path, repo, branch)}",
                ),
            )
    return RowResult(row.row_id, Verdict.PASS)


def _excerpt(text: str, limit: int = 120) -> str:
    return text if len(text) <= limit else f"{text[:limit]}…"


def render(report: SpecReport) -> str:
    """Render one run as its per-row lines, its diagnostics and its summary counters."""
    lines = [f"== {report.path} =="]
    for result in report.results:
        row = f"{result.row_id}\t{result.verdict}"
        if result.reason:
            row = f"{row}\t{normalise(result.reason)}"
        lines.append(row)
        # Two spaces in front of every diagnostic, and every one folded to a single line:
        # a line-leading `KEY: ` is reserved for a summary counter, and captured output
        # carries lines that begin `FAIL:` which would otherwise corrupt the counts.
        lines.extend(f"  {normalise(detail)}" for detail in result.details)
    for issue in report.breaks:
        if issue.against_claim:
            lines.append(f"{issue.target}\tGRAPH\t{normalise(issue.message)}")

    lines.append("")
    lines.append(f"PASS: {report.passed} row(s)")
    lines.append(f"FAIL: {report.failed} row(s) or graph break(s)")
    lines.append(f"SKIP: {report.skipped} row(s)")
    lines.append(f"TOKENS: {report.token_total} checked across {report.token_rows} row(s)")
    lines.append(f"GRAPH: {report.graph_count} inconsistency across {report.claim_count} claim(s)")
    lines.append(f"COVERS: {COVERS}")
    return "\n".join(lines) + "\n"
