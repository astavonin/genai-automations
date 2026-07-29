"""Tests for prompt assembly — ODV branches of build_implementation_prompt, and the
observed-failure regression guidance that build_review_prompt must deliver to Codex."""

from __future__ import annotations

from pathlib import Path

from codex_flow.contracts import ImplementationRequest, ReviewRequest
from codex_flow.prompting import build_implementation_prompt, build_review_prompt


def _make_request(odv: str | None, ledger: str | None = None) -> ImplementationRequest:
    return ImplementationRequest(
        request_path=Path("/tmp/design.md"),
        repository=Path("/tmp/repo"),
        functional_requirements=["Do the thing"],
        non_functional_requirements=[],
        constraints=[],
        verification="pytest",
        on_device_verification=odv,
        observed_failure_ledger=ledger,
        context_files=[],
        raw_markdown="# Design — Test\n\n## 3. Implementation Context\n\n**Repository:** `/tmp/repo`\n",
    )


def test_build_implementation_prompt_includes_odv_block_when_present() -> None:
    request = _make_request("**On-Device Verification:**\n**Entry point:** make verify-device\n")

    result = build_implementation_prompt(request)

    assert "On-Device Verification field from design doc:" in result
    assert "make verify-device" in result


def test_build_implementation_prompt_includes_absent_odv_note_when_none() -> None:
    request = _make_request(None)

    result = build_implementation_prompt(request)

    assert "On-Device Verification field from design doc: ABSENT" in result
    assert "missing from design doc" in result
    assert "software-only" not in result
    assert "make verify-device" not in result


def _make_review_request(ledger: str) -> ReviewRequest:
    return ReviewRequest(
        request_path=Path("/tmp/review.md"),
        repository=Path("/tmp/repo"),
        branch="fix/ci-unbound-version",
        review_scope="HEAD~1..HEAD",
        output_file="codex-review.md",
        date=None,
        requirements=["Fix the unbound variable"],
        constraints=[],
        evidence="```bash\npytest  # exit 0\n```",
        review_focus=["correctness"],
        raw_markdown=f"# Review Request — Test\n\n## Observed-Failure Ledger\n\n{ledger}\n",
    )


def test_build_review_prompt_carries_observed_failure_pass() -> None:
    """The regression gate must reach Codex via bundled guidance, not user config.

    codex-flow invokes Codex with --ignore-user-config --ignore-rules, so rules living
    in ~/.codex/ never arrive. Regression test for that delivery path.
    """
    result = build_review_prompt(_make_review_request("No ledger exists for this work."))

    assert "Observed-Failure Regression Pass" in result
    # Assert on the mapping's own distinctive rows. "Report as High" alone is satisfied by an
    # incidental bullet elsewhere in the bundle, so deleting the whole severity paragraph would
    # not have failed this test.
    assert "an entry carrying two `**Status:**` lines or none" in result
    assert "Report as Medium" in result
    assert "user-approved waiver" in result  # a recorded waiver is a valid resolution
    assert "external merge requests" in result.lower()  # carve-out for MRs we do not own


def test_build_review_prompt_includes_ledger_contents() -> None:
    ledger = "## 2026-07-28 unbound VERSION_NUMBER\n**Status:** open"

    result = build_review_prompt(_make_review_request(ledger))

    assert "unbound VERSION_NUMBER" in result
    assert "**Status:** open" in result


def test_build_implementation_prompt_delivers_open_ledger_entries() -> None:
    """An open ledger entry must reach implementation mode.

    Observed failure class: `codex-flow implement` runs from a design doc, not from the issue
    folder, so without this field Codex cannot know the work fixes a failure that already
    happened — and can ship the fix with no regression test while `/verify` later blocks on the
    still-open entry.
    """
    ledger = "## 2026-07-29 unbound VERSION_NUMBER\n**Status:** open"

    result = build_implementation_prompt(_make_request(None, ledger))

    assert "unbound VERSION_NUMBER" in result
    assert "**Status:** open" in result
    assert "requires a regression test in this implementation" in result


def test_build_implementation_prompt_states_ledger_absence_explicitly() -> None:
    """Absence must be stated, not implied — silence is indistinguishable from omission."""
    result = build_implementation_prompt(_make_request(None, None))

    assert "Observed-Failure Ledger: absent from the design doc" in result
