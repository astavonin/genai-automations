"""Tests for the codex-flow CLI."""

from __future__ import annotations

from pathlib import Path

import pytest

from codex_flow import cli, runner
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


def test_review_cli_fails_loudly_and_writes_no_output_when_request_is_invalid(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """A rejected request must exit non-zero and leave no output file.

    Observed failure: a review request missing a required section was rejected, and the
    caller — which launches codex-flow in the background and so only sees the *launch*
    succeed — aggregated three reviewer agents as though it were a 3+1 consensus. The
    workflow-side fix is the Codex-failure handler in consensus-review-protocol.md; this
    test guards the machine contract that handler relies on: a caller can distinguish
    "Codex ran" from "Codex was launched" by testing the output file, and stderr says why.
    """
    request = tmp_path / "review.md"
    output = tmp_path / "codex-review.md"
    request.write_text(
        f"""
# Review Request — Missing Ledger

**Repository:** `{tmp_path}`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `{output.name}`

## Requirements

- Something

## Constraints

- Something

## Evidence

```bash
pytest
```

## Review Focus

- correctness
""".strip(),
        encoding="utf-8",
    )

    # Hermetic, and it asserts the real invariant: validation must reject before anything
    # can spawn Codex. Without this the test still passes, but any regression that lets a
    # bad request through would launch a real `codex exec` from the unit suite.
    def must_not_launch(*args: object, **kwargs: object) -> None:
        raise AssertionError("Codex must not be launched for a rejected request")

    monkeypatch.setattr(runner.subprocess, "Popen", must_not_launch)

    with pytest.raises(SystemExit) as exc:
        cli.main(["review", str(request)])

    captured = capsys.readouterr()
    assert exc.value.code == 1, "a rejected request must not report success"
    assert not output.exists(), "no output file may be written for a rejected request"
    assert "Observed-Failure Ledger" in captured.err, "stderr must say why it was rejected"
    assert captured.out == "", "stdout carries the output path on success only"
