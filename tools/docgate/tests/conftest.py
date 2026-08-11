"""Shared fixtures and readers for the docgate suite.

Assertions read exact fields rather than grepping for substrings: two earlier versions
of the shell suite this replaces passed vacuously because an assertion matched
something other than what it named.
"""

from __future__ import annotations

import io
import itertools
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import pytest

from docgate.cli import main

# Column index for field(), matching the rendered table order.
WORDS, SHARE, REGISTER, TARGET, CEILING, VERDICT = range(1, 7)


@dataclass(frozen=True)
class Result:
    """One invocation's streams and exit code."""

    stdout: str
    stderr: str
    code: int

    @property
    def output(self) -> str:
        """Both streams, as a caller redirecting 2>&1 would see them."""
        return self.stdout + self.stderr


def run(*arguments: object) -> Result:
    """Invoke the CLI entry function in process and capture both streams."""
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = main([str(argument) for argument in arguments])
    return Result(out.getvalue(), err.getvalue(), code)


def field(output: str, label: str, column: int) -> str:
    """Read one cell of the section row whose name matches ``label`` exactly."""
    for line in output.splitlines():
        cells = line.split("\t")
        if len(cells) == 7 and cells[0].rstrip() == label:
            return cells[column].strip()
    return ""


def summary(output: str, label: str) -> str:
    """Read the count from the first ``LABEL: <count> ...`` summary line."""
    for line in output.splitlines():
        if line.startswith(f"{label}: "):
            return line.split(" ")[1]
    return ""


def counters(output: str) -> tuple[str, str, str, str]:
    """Read the four design-field counters as (cost, misses, from, untagged)."""
    return (
        summary(output, "COST"),
        summary(output, "MISSES"),
        summary(output, "FROM"),
        summary(output, "UNTAGGED"),
    )


def detail_rows(output: str) -> list[list[str]]:
    """Return every indented detail line, split into its tab-separated fields."""
    rows = []
    for line in output.splitlines():
        if line.startswith("  ") and "\t" in line:
            fields = line.split("\t")
            fields[0] = fields[0][2:]
            rows.append(fields)
    return rows


@pytest.fixture
def write_doc(tmp_path: Path) -> Callable[..., Path]:
    """Return a factory writing a Markdown fixture and yielding its path."""
    counter = itertools.count()

    def _write(body: str, name: str | None = None) -> Path:
        path = tmp_path / (name or f"doc{next(counter)}.md")
        path.write_text(body, encoding="utf-8")
        return path

    return _write


@pytest.fixture
def measure(write_doc: Callable[..., Path]) -> Callable[[str], Result]:
    """Return a helper measuring a Markdown body and yielding the run's result."""

    def _measure(body: str) -> Result:
        return run(write_doc(body))

    return _measure


@pytest.fixture
def totals(measure: Callable[[str], Result]) -> Callable[[str], tuple[str, str]]:
    """Return a helper yielding (total words, register hits) for a Markdown body."""

    def _totals(body: str) -> tuple[str, str]:
        result = measure(body)
        return field(result.output, "TOTAL", WORDS), summary(result.output, "REGISTER")

    return _totals


@pytest.fixture
def fields(measure: Callable[[str], Result]) -> Callable[[str], tuple[str, str, str, str]]:
    """Return a helper yielding the four design-field counters for a Markdown body."""

    def _fields(body: str) -> tuple[str, str, str, str]:
        return counters(measure(body).output)

    return _fields
