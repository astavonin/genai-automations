"""Tests for the codex-flow CLI."""

from __future__ import annotations

from pathlib import Path

import pytest

from codex_flow import cli
from codex_flow.progress import ProgressConfig


def test_review_cli_passes_progress_config_and_keeps_output_path_on_stdout(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    request = tmp_path / "review.md"
    request.write_text("# Review\n", encoding="utf-8")
    output = tmp_path / "review-output.md"

    def fake_run_review(path: Path, progress_config: ProgressConfig) -> Path:
        assert path == request
        assert progress_config.mode == "json"
        assert progress_config.log_enabled is False
        return output

    monkeypatch.setattr(cli, "run_review", fake_run_review)

    exit_code = cli.main(
        [
            "review",
            "--progress",
            "json",
            "--no-progress-log",
            str(request),
        ]
    )

    captured = capsys.readouterr()
    assert exit_code == 0
    assert captured.out == f"{output}\n"
    assert captured.err == ""
