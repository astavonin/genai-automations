"""Tests for Markdown request parsing."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from codex_flow.exceptions import ValidationError
from codex_flow.markdown_parser import (
    parse_implementation_request,
    parse_review_request,
)

# Sections codex-flow requires in every review request. Kept here so the template guard below
# and the coverage guard that follows it stay tied to one list.
REQUIRED_REQUEST_SECTIONS = (
    "Requirements",
    "Constraints",
    "Observed-Failure Ledger",
    "Evidence",
    "Review Focus",
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
    assert parsed.non_functional_requirements == [
        "Retry must add no more than 50 ms latency per attempt"
    ]
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

## Observed-Failure Ledger

No ledger exists for this work.

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

## Observed-Failure Ledger

No ledger exists for this work.

## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="must resolve under repository"):
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


def test_parse_review_request_rejects_missing_observed_failure_ledger(tmp_path: Path) -> None:
    """An omitted ledger section must fail loudly rather than reach Codex as silence.

    Codex sees only the review request. Without an explicit ledger statement it cannot tell
    a fix with no observed failure from one whose waiver it simply was not shown, and reports
    a High that no coder can clear.
    """
    request = tmp_path / "review.md"
    request.write_text(
        """
# Review Request — Retry Handling

**Repository:** `/tmp/repo`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry.md`

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

    with pytest.raises(ValidationError, match="No ledger exists for this work"):
        parse_review_request(request)


def test_parse_review_request_rejects_empty_observed_failure_ledger(tmp_path: Path) -> None:
    """A present-but-empty section is the same silence as an absent one."""
    request = tmp_path / "review.md"
    # Built rather than inlined: a literal whitespace-only line fails `git diff --check`.
    blank = "\n   \t\n"
    request.write_text(
        f"""
# Review Request — Retry Handling

**Repository:** `/tmp/repo`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry.md`

## Requirements

- Retry transient failures up to three times

## Constraints

- Keep the CLI unchanged

## Evidence

```bash
pytest tests/test_sync.py
```

## Observed-Failure Ledger
{blank}
## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="No ledger exists for this work"):
        parse_review_request(request)


def test_parse_review_request_rejects_unfilled_ledger_placeholder(tmp_path: Path) -> None:
    """The template placeholder must not satisfy the guard — it states nothing."""
    request = tmp_path / "review.md"
    request.write_text(
        """
# Review Request — Retry Handling

**Repository:** `/tmp/repo`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry.md`

## Requirements

- Retry transient failures up to three times

## Constraints

- Keep the CLI unchanged

## Observed-Failure Ledger

~~~markdown
# (paste ledger here, or: No ledger exists for this work.)
~~~

## Evidence

```bash
pytest tests/test_sync.py
```

## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )

    with pytest.raises(ValidationError, match="No ledger exists for this work"):
        parse_review_request(request)


def test_shipped_example_review_request_still_parses() -> None:
    """The reference request must satisfy the parser it ships beside."""
    example = Path(__file__).resolve().parents[1] / "examples" / "sample-review-request.md"
    assert example.is_file(), f"reference request missing: {example}"

    parsed = parse_review_request(example)

    assert parsed.output_file, "example must resolve an Output File"
    assert "No ledger exists for this work." in parsed.raw_markdown


# Every document a workflow command turns into a review request. codex-flow validates required
# sections, so one added to the parser but missed in a template kills that command's Codex leg
# at launch — the failure recorded in this repo's observed-failures ledger.
REQUEST_PRODUCERS = (
    "platforms/claude/skills/workflows/planning/REVIEW-REQUEST-TEMPLATE.md",
    "platforms/claude/skills/workflows/article-review/CODEX-REQUEST-TEMPLATE.md",
)


@pytest.mark.parametrize("producer", REQUEST_PRODUCERS)
def test_request_templates_carry_every_required_section(producer: str) -> None:
    """Each request-producing template must carry every section the parser requires.

    The example test above would not have caught the observed failure: the example is a third
    producer. This walks the actual templates, which live outside this package but inside the
    same repo, and skips when codex-flow is installed standalone.
    """
    repo_root = Path(__file__).resolve().parents[3]
    if not (repo_root / "platforms").is_dir():
        pytest.skip("config repo not present — codex-flow installed standalone")
    path = repo_root / producer
    assert path.is_file(), f"request producer missing: {producer}"

    text = path.read_text(encoding="utf-8")
    missing = [s for s in REQUIRED_REQUEST_SECTIONS if f"## {s}" not in text]

    assert not missing, f"{producer} is missing required section(s): {missing}"


def test_required_section_list_matches_what_the_parser_enforces(tmp_path: Path) -> None:
    """Guard the guard: REQUIRED_REQUEST_SECTIONS must track the parser.

    Without this, adding a required section to the parser and forgetting to list it here would
    leave the template test green while the templates are stale — the same drift, one level up.
    """
    body = {s: "- x" for s in REQUIRED_REQUEST_SECTIONS}
    body["Evidence"] = "```bash\npytest\n```"
    body["Observed-Failure Ledger"] = "No ledger exists for this work."

    for omitted in REQUIRED_REQUEST_SECTIONS:
        doc = [
            "# Review Request — Coverage Probe",
            "",
            "**Repository:** `/tmp/repo`",
            "**Review Scope:** `HEAD~1..HEAD`",
            "**Output File:** `out.md`",
            "",
        ]
        for section, content in body.items():
            if section != omitted:
                doc += [f"## {section}", "", content, ""]
        request = tmp_path / f"omit-{omitted.replace(' ', '-')}.md"
        request.write_text("\n".join(doc), encoding="utf-8")

        with pytest.raises(ValidationError):
            parse_review_request(request)


def _review_request_with_ledger(ledger_body: str) -> str:
    return f"""# Review Request — Ledger Shape

**Repository:** `/tmp/repo`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `out.md`

## Requirements

- Something

## Constraints

- Something

## Observed-Failure Ledger

{ledger_body}

## Evidence

```bash
pytest
```

## Review Focus

- correctness
"""


# Shapes the ledger guard must reject: template scaffolding that reads as content while saying
# nothing. A negative-form check ("not empty, not the placeholder") let every one of these through.
@pytest.mark.parametrize(
    "body",
    [
        pytest.param("---", id="lone-separator"),
        pytest.param("<!-- TODO fill this in -->", id="html-comment"),
        pytest.param("<issue-folder>/observed-failures.md", id="unresolved-placeholder-path"),
        pytest.param("~~~markdown\n~~~", id="empty-fence"),
        pytest.param(
            "Contents of the ledger, pasted verbatim — or the literal line\n"
            "`No ledger exists for this work.` when there is none.",
            id="template-prose-fence-deleted",
        ),
    ],
)
def test_parse_review_request_rejects_ledger_scaffolding(tmp_path: Path, body: str) -> None:
    request = tmp_path / "review.md"
    request.write_text(_review_request_with_ledger(body), encoding="utf-8")

    with pytest.raises(ValidationError, match="No ledger exists for this work"):
        parse_review_request(request)


# Shapes the guard must accept — including a real ledger whose entries are level-2 headings and
# whose Evidence block carries its own fence. The ledger extractor is fence-aware for this.
@pytest.mark.parametrize(
    "body",
    [
        pytest.param("No ledger exists for this work.", id="no-ledger"),
        pytest.param("No ledger exists for this work — external MR.", id="external-mr"),
        pytest.param("No ledger exists for this work — article review.", id="article-review"),
        pytest.param(
            "~~~markdown\n# Observed Failures — x\n\n## 2026-07-29 symptom\n"
            "**Status:** covered\n**Test:** `t.py::x`\n~~~",
            id="real-ledger-fenced",
        ),
        pytest.param(
            "~~~markdown\n## 2026-07-29 symptom\n**Status:** covered\n"
            "**Evidence:**\n```\ncaptured output\n```\n~~~",
            id="real-ledger-with-inner-fence",
        ),
    ],
)
def test_parse_review_request_accepts_valid_ledger_shapes(tmp_path: Path, body: str) -> None:
    request = tmp_path / "review.md"
    request.write_text(_review_request_with_ledger(body), encoding="utf-8")

    parsed = parse_review_request(request)

    assert body.splitlines()[0] in parsed.raw_markdown


def test_parse_implementation_request_extracts_fenced_observed_failure_ledger(
    tmp_path: Path,
) -> None:
    """A ledger in the design doc must survive parsing without disturbing its neighbours.

    Two things make this fragile: the ledger's entries are `## ` headings, which would end the
    Implementation Context section unfenced; and the On-Device Verification field absorbs
    everything up to Context Files, so the ledger sits after it. Both are load-bearing.
    """
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — Fix unbound version

## 3. Implementation Context

**Repository:** `/tmp/repo`
**Functional Requirements:**
- Fail fast when VERSION_NUMBER is unset
**Non-Functional Requirements:**
- none
**Constraints:**
- none
**Verification:**
```bash
pytest
```
**On-Device Verification:** N/A (on-device scope: NO)
**Context Files:**
- src/deploy.sh

**Observed-Failure Ledger:**
~~~markdown
## 2026-07-29 unbound VERSION_NUMBER on deploy
**Status:** open
~~~
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert "unbound VERSION_NUMBER on deploy" in (parsed.observed_failure_ledger or "")
    assert "**Status:** open" in (parsed.observed_failure_ledger or "")
    # Neighbours are undisturbed: the ledger did not leak into ODV, and Context Files survived
    # the ledger's own `## ` headings.
    assert parsed.on_device_verification == "N/A (on-device scope: NO)"
    assert parsed.context_files == ["src/deploy.sh"]


def test_parse_implementation_request_tolerates_absent_ledger(tmp_path: Path) -> None:
    """Design docs written before the field must still parse — it is optional."""
    request = tmp_path / "design.md"
    request.write_text(
        """
# Design — New feature

## 3. Implementation Context

**Repository:** `/tmp/repo`
**Functional Requirements:**
- Add a thing
**Non-Functional Requirements:**
- none
**Constraints:**
- none
**Verification:**
```bash
pytest
```
**On-Device Verification:** N/A (on-device scope: NO)
**Context Files:**
- src/thing.py
""".strip(),
        encoding="utf-8",
    )

    parsed = parse_implementation_request(request)

    assert parsed.observed_failure_ledger is None


def test_missing_request_error_names_the_directory_it_resolved_against(tmp_path: Path) -> None:
    """A not-found error must say what the path was resolved against.

    Relative request paths are supported and normal. When one does not resolve, the missing
    piece is always the working directory — codex-flow may be running somewhere the caller did
    not choose, and the path can look perfectly correct relative to the repo root. Naming the
    directory turns a two-step diagnosis into a one-step one.
    """
    import os

    with pytest.raises(ValidationError, match=re.escape(os.getcwd())):
        parse_review_request(Path("planning/nope/review.md"))


def test_absolute_missing_request_error_stays_unambiguous(tmp_path: Path) -> None:
    """An absolute path needs no cwd context — it would only add noise."""
    missing = tmp_path / "nope.md"

    with pytest.raises(ValidationError, match="Request file not found") as exc:
        parse_review_request(missing)

    assert "resolved against" not in str(exc.value)
