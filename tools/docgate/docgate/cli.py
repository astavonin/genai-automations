"""Command line entry point for the document metrics gate.

Exit codes:
  0  ran — read the output
  1  BLOCKER — bad input, or a measurement that cannot be trusted

A non-zero exit means "this number is not a measurement", never "hits found" or "over
ceiling". Callers read the REGISTER, CEILING, and the four design-field summary lines
for those: a document with fifty register hits exits 0.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .metrics import MeasurementError, analyze_file, render

__all__ = ["main"]

_USAGE = "usage: doc-metrics <file.md> [<file.md> ...]"


class _StdoutClosed(Exception):
    """The reader went away; what is still to be measured is unaffected."""


def _blocker(error: MeasurementError) -> None:
    print(f"BLOCKER: {error.message}", file=sys.stderr)
    if error.detail:
        print(f"         {error.detail}", file=sys.stderr)


def _check_path(argument: str) -> Path:
    # An unsubstituted placeholder is a caller that never filled its template in; it
    # would otherwise report "not a file" and read as a missing document.
    if "<" in argument:
        raise MeasurementError(f"placeholder left in path — {argument}")
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
