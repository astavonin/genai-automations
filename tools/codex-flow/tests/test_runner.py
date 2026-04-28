"""Tests for codex-flow runtime behavior."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from codex_flow.runner import run_implementation, run_review


def _config_values(command: list[str]) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command) if value == "--config"]


def _write_implementation_request(path: Path, repository: Path) -> None:
    path.write_text(
        f"""
# Design — Retry Handling

## 3. Implementation Context

**Repository:** `{repository}`

**Requirements:**
- Retry transient failures up to three times

**Constraints:**
- Keep the CLI unchanged

**Verification:**
```bash
pytest tests/test_sync.py
```

**Context Files:**
- `src/sync.py`
""".strip(),
        encoding="utf-8",
    )


def _write_review_request(path: Path, repository: Path) -> None:
    path.write_text(
        f"""
# Review Request — Retry Handling

**Repository:** `{repository}`
**Review Scope:** `HEAD~1..HEAD`
**Output File:** `planning/reviews/retry-review.md`

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


def test_run_implementation_writes_standardized_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "src/sync.py").write_text("print('ok')\n", encoding="utf-8")
    request = tmp_path / "design.md"
    _write_implementation_request(request, repository)

    def fake_run(command: list[str], input: str, text: bool, capture_output: bool, check: bool):
        assert command[:2] == ["codex", "exec"]
        assert "--ignore-user-config" not in command
        assert "--ignore-rules" not in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == "gpt-5.4"
        assert _config_values(command) == ["model_reasoning_effort=xhigh"]
        assert "--dangerously-bypass-approvals-and-sandbox" in command
        assert "--sandbox" not in command
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "SUCCESS",
                    "summary": "Implemented retry handling.",
                    "files_changed": ["src/sync.py"],
                    "verification_results": [
                        {
                            "command": "pytest tests/test_sync.py",
                            "status": "passed",
                            "details": "1 passed",
                        }
                    ],
                    "reasoning": ["Kept the CLI unchanged."],
                    "open_issues": [],
                }
            ),
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("codex_flow.runner.subprocess.run", fake_run)

    output = run_implementation(request)

    assert output.exists()
    content = output.read_text(encoding="utf-8")
    assert "**Final Status:** `SUCCESS`" in content
    assert "`src/sync.py`" in content


def test_run_review_uses_read_only_and_only_writes_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def fake_run(command: list[str], input: str, text: bool, capture_output: bool, check: bool):
        assert command[:2] == ["codex", "exec"]
        assert "--ignore-user-config" in command
        assert "--ignore-rules" in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == "gpt-5.4"
        assert _config_values(command) == [
            "model_reasoning_effort=xhigh",
            "approval_policy=never",
        ]
        assert "--dangerously-bypass-approvals-and-sandbox" not in command
        assert "--sandbox" in command
        assert command[command.index("--sandbox") + 1] == "read-only"
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [
                        {
                            "requirement": "Retry transient failures up to three times",
                            "status": "verified",
                            "notes": "Behavior matches the diff.",
                        }
                    ],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("codex_flow.runner.subprocess.run", fake_run)

    output = run_review(request)

    assert output.exists()
    assert output.read_text(encoding="utf-8").startswith("# Review Output")


def test_run_review_ignores_pytest_and_pyc_artifacts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "tests").mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def fake_run(command: list[str], input: str, text: bool, capture_output: bool, check: bool):
        pycache_dir = repository / "src" / "__pycache__"
        pytest_cache_dir = repository / ".pytest_cache" / "v" / "cache"
        pycache_dir.mkdir(parents=True, exist_ok=True)
        pytest_cache_dir.mkdir(parents=True, exist_ok=True)
        (pycache_dir / "example.cpython-312.pyc").write_text("cache", encoding="utf-8")
        (pytest_cache_dir / "nodeids").write_text("[]", encoding="utf-8")
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "APPROVE",
                    "summary": "No correctness issues found.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": [],
                    "recommendation": "Approve.",
                }
            ),
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("codex_flow.runner.subprocess.run", fake_run)

    output = run_review(request)

    assert output.exists()


def test_run_review_warns_and_traces_when_repo_changes_during_codex_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    target = repository / "file.txt"
    target.write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)

    def fake_run(command: list[str], input: str, text: bool, capture_output: bool, check: bool):
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "REQUEST CHANGES",
                    "summary": "A regression is present.",
                    "findings": [],
                    "requirement_coverage": [],
                    "verification_gaps": ["Tests were not rerun."],
                    "recommendation": "Request changes.",
                }
            ),
            encoding="utf-8",
        )
        target.write_text("after\n", encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("codex_flow.runner.subprocess.run", fake_run)

    output = run_review(request)

    captured = capsys.readouterr()
    assert output.exists()
    assert output.read_text(encoding="utf-8").startswith("# Review Output")
    assert "codex-flow warning: review mode observed repository changes" in captured.err
    assert "file.txt" in captured.err
    trace_files = sorted((repository / ".codex-flow" / "review-traces").glob("*.json"))
    assert len(trace_files) == 1
    trace = json.loads(trace_files[0].read_text(encoding="utf-8"))
    assert trace["event"] == "review_mode_repository_changed"
    assert trace["output_file"] == str(output.resolve())
    assert trace["changed_during_codex"] == ["file.txt"]
    assert trace["unexpected_changed_paths"] == ["file.txt"]
