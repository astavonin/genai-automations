"""Tests for Markdown request parsing."""

from __future__ import annotations

from pathlib import Path

import pytest

from codex_flow.exceptions import ValidationError
from codex_flow.markdown_parser import (
    parse_implementation_request,
    parse_review_request,
)


def test_parse_implementation_request_extracts_contract(tmp_path: Path) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Retry Handling

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Requirements:**
- Retry transient failures up to three times

**Constraints:**
- Keep the CLI unchanged

**Verification:**

*Extract from the project README or CLAUDE.md.*

```bash
# Build / compile
make

# Test
pytest tests/test_sync.py

# Debug / run
make run
```

**Context Files:**
- `src/sync.py`
- `tests/test_sync.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.repository == Path("/tmp/repo")
    assert parsed.requirements == ["Retry transient failures up to three times"]
    assert parsed.constraints == ["Keep the CLI unchanged"]
    assert parsed.context_files == ["src/sync.py", "tests/test_sync.py"]
    assert parsed.output_path == tmp_path / "design.implementation-output.md"


def test_parse_implementation_request_rejects_missing_verification(tmp_path: Path) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Missing Verification

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Requirements:**
- Do the thing

**Constraints:**
- Keep scope small
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="Verification"):
        parse_implementation_request(request)


def test_parse_review_request_extracts_contract(tmp_path: Path) -> None:
    request = tmp_path / "review.md"
    request.write_text(
        """
# Review Request — Retry Handling

**Repository:** `/tmp/repo`
**Branch:** `feature/retry`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry.md`
**Date:** `2026-04-23`

## Requirements

- Retry transient failures up to three times

## Constraints

- Keep the CLI unchanged

## Evidence

```bash
pytest tests/test_sync.py
```

## Review Focus

- correctness
- regression risk
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_review_request(request)

    assert parsed.repository == Path("/tmp/repo")
    assert parsed.branch == "feature/retry"
    assert parsed.output_file == "planning/reviews/retry.md"
    assert parsed.review_focus == ["correctness", "regression risk"]


def test_parse_review_request_rejects_output_outside_repo(tmp_path: Path) -> None:
    request = tmp_path / "review.md"
    request.write_text(
        """
# Review Request — Retry Handling

**Repository:** `/tmp/repo`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `../escape.md`

## Requirements

- Retry transient failures up to three times

## Constraints

- Keep the CLI unchanged

## Evidence

```bash
pytest tests/test_sync.py
```

## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError):
        parse_review_request(request)
