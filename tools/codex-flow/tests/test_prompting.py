"""Tests for prompt assembly — covers ODV-present and ODV-absent branches of build_implementation_prompt."""

from __future__ import annotations

from pathlib import Path

from codex_flow.contracts import ImplementationRequest
from codex_flow.prompting import build_implementation_prompt


def _make_request(odv: str | None) -> ImplementationRequest:
    return ImplementationRequest(
        request_path=Path("/tmp/design.md"),
        repository=Path("/tmp/repo"),
        functional_requirements=["Do the thing"],
        non_functional_requirements=[],
        constraints=[],
        verification="pytest",
        on_device_verification=odv,
        context_files=[],
        raw_markdown="# Design — Test\n\n## 3. Implementation Context\n\n**Repository:** `/tmp/repo`\n",
    )


def test_build_implementation_prompt_includes_odv_block_when_present() -> None:
    request = _make_request(
        "**On-Device Verification:**\n**Entry point:** make verify-device\n"
    )

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
