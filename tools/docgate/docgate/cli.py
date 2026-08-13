"""Command line entry points for the document gates.

Exit codes, shared by both scripts:
  0  ran — read the output
  1  BLOCKER — bad input, or a measurement that cannot be trusted

A non-zero exit means "this number is not a measurement", never "hits found" or "over
ceiling". Callers read the REGISTER, CEILING, and the four design-field summary lines
for those: a document with fifty register hits exits 0, and a spec holding several FAIL
rows exits 0 as well.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from . import specverify
from .metrics import MeasurementError, analyze_file, render

__all__ = ["main", "spec_main"]

_USAGE = "usage: doc-metrics <file.md> [<file.md> ...]"
_SPEC_USAGE = "usage: spec-verify <issue-folder>"


class _StdoutClosed(Exception):
    """The reader went away; what is still to be measured is unaffected."""


def _blocker(error: MeasurementError) -> None:
    print(f"BLOCKER: {error.message}", file=sys.stderr)
    if error.detail:
        print(f"         {error.detail}", file=sys.stderr)


def _check_placeholder(argument: str) -> None:
    # An unsubstituted placeholder is a caller that never filled its template in; it
    # would otherwise report "not a file" and read as a missing document.
    if "<" in argument:
        raise MeasurementError(f"placeholder left in path — {argument}")


def _check_path(argument: str) -> Path:
    _check_placeholder(argument)
    path = Path(argument)
    if not path.is_file():
        raise MeasurementError(f"not a file — {argument}")
    if not os.access(path, os.R_OK):
        raise MeasurementError(f"not readable — {argument}")
    return path


def _write(text: str) -> None:
    try:
        sys.stdout.write(text)
        sys.stdout.flush()
    except BrokenPipeError as err:
        raise _StdoutClosed from err


def _discard_stdout() -> None:
    """Point stdout at /dev/null so the interpreter's own shutdown flush cannot fail."""
    devnull = os.open(os.devnull, os.O_WRONLY)
    try:
        os.dup2(devnull, sys.stdout.fileno())
    finally:
        os.close(devnull)


def main(argv: list[str] | None = None) -> int:
    """Measure every document named on the command line."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments:
        print(f"BLOCKER: no file given — {_USAGE}", file=sys.stderr)
        return 1

    paths: list[Path] = []
    for argument in arguments:
        try:
            paths.append(_check_path(argument))
        except MeasurementError as err:
            _blocker(err)
            return 1

    unmeasured = 0
    for path in paths:
        try:
            report = analyze_file(path)
        except MeasurementError as err:
            _blocker(err)
            unmeasured += 1
            continue
        try:
            _write(render(report))
        except _StdoutClosed:
            # A caller piping into `head -1` closes the pipe mid-write. What was measured
            # does not change with the reader going away, so the remaining documents are
            # still measured and still decide the exit status; returning 0 here instead
            # would report success for a set holding a document that blocked.
            _discard_stdout()

    if unmeasured:
        print(f"BLOCKER: no usable measurement for {unmeasured} file(s)", file=sys.stderr)
        return 1
    return 0


def _no_scan(path: Path, reason: str) -> int:
    """Report a run with nothing to scan: the house path header, the reason, no counters.

    An absent `FAIL:` line is what tells a caller "nothing was scanned" apart from a
    clean run, so the reason carries a two-space indent rather than a `KEY: ` prefix.
    """
    try:
        _write(f"== {path} ==\n  {reason}\n")
    except _StdoutClosed:
        _discard_stdout()
    return 0


def spec_main(argv: list[str] | None = None) -> int:
    """Verify the fact contract of the appendix spec in one issue folder."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    if len(arguments) != 1:
        problem = "no folder given" if not arguments else "one folder at a time"
        print(f"BLOCKER: {problem} — {_SPEC_USAGE}", file=sys.stderr)
        return 1

    folder = Path(arguments[0])
    spec = folder / "spec.md"
    try:
        # The guard fires on the joined path, so `spec-verify <issue-folder>` is caught
        # whichever half the caller left unsubstituted.
        _check_placeholder(str(spec))
        if not folder.is_dir():
            raise MeasurementError(f"not a folder — {arguments[0]}")
        if not spec.is_file():
            # 8 of the reference tree's 11 issue folders hold no spec.md, so this is the
            # ordinary case rather than a caller error — it scans nothing and exits 0.
            return _no_scan(spec, "no spec.md in this folder — nothing to scan")
        text = specverify.read_text(str(spec))
        kind = specverify.spec_kind(text)
        if not kind:
            raise MeasurementError(
                f"neither **Page:** nor **Article:** in {spec}",
                "the header field is what tells an appendix spec from a main spec",
            )
        if kind == "main":
            return _no_scan(spec, "main spec (**Article:**) — appendix specs only, nothing to scan")
        document = specverify.parse_spec(text, str(spec))
        if not document.rows:
            raise MeasurementError(
                f"no parseable §5 Verification Procedure in {spec}",
                "an appendix spec with no `### V<N>` row states no verifiable fact",
            )
    except MeasurementError as err:
        _blocker(err)
        return 1

    report = specverify.verify(
        document,
        runner=specverify.run_over_ssh,
        fetcher=specverify.fetch_document,
    )
    try:
        _write(specverify.render(report))
    except _StdoutClosed:
        # Exit status never encodes findings, so a reader going away changes nothing: the
        # run measured, and a spec holding several FAIL rows exits 0 too.
        _discard_stdout()
    return 0
