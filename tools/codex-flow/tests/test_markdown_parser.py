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

**Goal:** `sync`
**Milestone:** `milestone-01-reliability` · `%12`
**Feature:** `#34`
**Branch:** `feature/retry-handling`
**Status:** Draft
**Revision:** 1

---

## 1. Problem Statement

Retries are needed for transient sync failures.

---

## 2. Goals and Non-Goals

### Goals
- Retry transient failures.

### Non-Goals
- Redesign the CLI.

---

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Retry transient failures up to three times

**Non-Functional Requirements:**
- Retry must add no more than 50 ms latency per attempt

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

---

## 4. Architecture Overview

No architecture change.

---

## 5. Detailed Design

Keep retry handling inside the sync component boundary.

---

## 6. Test Requirements

### Unit Tests
- Retry logic fires on transient error codes only

### Integration Tests
- Full sync with injected transient failure recovers within three retries

### E2E Tests

*(None — software-only feature)*

---

## 7. Trade-offs and Alternatives

No meaningful alternatives for this narrow retry behavior.

---

## 8. Open Questions

No open questions.
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.repository == Path("/tmp/repo")
    assert parsed.functional_requirements == ["Retry transient failures up to three times"]
    assert parsed.non_functional_requirements == ["Retry must add no more than 50 ms latency per attempt"]
    assert parsed.constraints == ["Keep the CLI unchanged"]
    assert parsed.context_files == ["src/sync.py", "tests/test_sync.py"]
    assert parsed.output_path == tmp_path / "design.implementation-output.md"
    assert parsed.on_device_verification is None


def test_parse_implementation_request_rejects_missing_verification(tmp_path: Path) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Missing Verification

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Do the thing

**Non-Functional Requirements:**
- Keep it fast

**Constraints:**
- Keep scope small
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="Verification"):
        parse_implementation_request(request)


def test_parse_implementation_request_rejects_when_all_requirements_empty(tmp_path: Path) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Empty Requirements

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**

**Non-Functional Requirements:**

**Constraints:**
- Keep scope small

**Verification:**

```bash
pytest
```

**Context Files:**
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="at least one Functional or Non-Functional"):
        parse_implementation_request(request)


def test_parse_implementation_request_rejects_legacy_requirements_field(tmp_path: Path) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Legacy Format

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Requirements:**
- Do the thing

**Constraints:**
- Keep scope small

**Verification:**

```bash
pytest
```
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="Missing required field: Functional Requirements"):
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


def test_parse_implementation_request_extracts_on_device_verification_full_block(
    tmp_path: Path,
) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Device Feature

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Deploy and verify on device

**Non-Functional Requirements:**
- Verification must complete within 60 s

**Constraints:**
- Do not modify device firmware

**Verification:**

```bash
pytest tests/
```

**On-Device Verification:**

*Derived from project README.*

**Entry point:** `make verify-device`

```bash
# Deploy to device
make deploy-device

# Verify on device
make verify-device
```

Expected outcome on device:
- All tests pass

**CI integration:** Set DEVICE_IP env var in CI.

**Context Files:**
- `src/main.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.on_device_verification is not None
    assert "Entry point" in parsed.on_device_verification
    assert "make verify-device" in parsed.on_device_verification
    assert "CI integration" in parsed.on_device_verification
    assert parsed.context_files == ["src/main.py"]


def test_parse_implementation_request_extracts_on_device_verification_skip_note(
    tmp_path: Path,
) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Software-Only Feature

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Process data in memory

**Non-Functional Requirements:**
- Low latency

**Constraints:**
- No external dependencies

**Verification:**

```bash
pytest tests/
```

**On-Device Verification:** N/A — feature is software-only (on-device scope: NO).

**Context Files:**
- `src/processor.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.on_device_verification is not None
    assert "on-device scope: NO" in parsed.on_device_verification


def test_parse_implementation_request_on_device_verification_empty_content_is_none(
    tmp_path: Path,
) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Empty ODV Field

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Handle network timeouts

**Non-Functional Requirements:**
- Retry within 100 ms

**Constraints:**
- Keep API surface unchanged

**Verification:**

```bash
pytest tests/
```

**On-Device Verification:**
**Context Files:**
- `src/network.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.on_device_verification is None


def test_parse_implementation_request_on_device_verification_empty_content_blank_line_is_none(
    tmp_path: Path,
) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Empty ODV With Blank Line

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Handle network timeouts

**Non-Functional Requirements:**
- Retry within 100 ms

**Constraints:**
- Keep API surface unchanged

**Verification:**

```bash
pytest tests/
```

**On-Device Verification:**

**Context Files:**
- `src/main.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.on_device_verification is None


def test_parse_implementation_request_on_device_verification_absent_is_none(
    tmp_path: Path,
) -> None:
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — No Device Field

## 3. Implementation Context

**Repository:** `/tmp/repo`

**Functional Requirements:**
- Handle network timeouts

**Non-Functional Requirements:**
- Retry within 100 ms

**Constraints:**
- Keep API surface unchanged

**Verification:**

```bash
pytest tests/
```

**Context Files:**
- `src/network.py`
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.on_device_verification is None
