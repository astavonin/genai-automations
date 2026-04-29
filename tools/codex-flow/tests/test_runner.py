"""Tests for codex-flow runtime behavior."""

from __future__ import annotations

import json
import io
import subprocess
from pathlib import Path
from typing import Callable

import pytest

from codex_flow.progress import PROGRESS_MARKER, ProgressConfig, repository_state_key
from codex_flow.runner import DISABLED_EXTERNAL_TOOL_FEATURES, run_implementation, run_review


class _FakeProcess:
    def __init__(self, stdout_text: str = "", return_code: int = 0) -> None:
        self.stdin = io.StringIO()
        self.stdout = io.StringIO(stdout_text)
        self._return_code = return_code

    def wait(self) -> int:
        return self._return_code


def _install_fake_popen(
    monkeypatch: pytest.MonkeyPatch,
    on_start: Callable[[list[str]], None],
    stdout_text: str = "",
    return_code: int = 0,
) -> None:
    def fake_popen(
        command: list[str],
        stdin: int,
        stdout: int,
        stderr: int,
        text: bool,
        bufsize: int,
    ) -> _FakeProcess:
        assert stdin == subprocess.PIPE
        assert stdout == subprocess.PIPE
        assert stderr == subprocess.STDOUT
        assert text is True
        assert bufsize == 1
        on_start(command)
        return _FakeProcess(stdout_text, return_code)

    monkeypatch.setattr("codex_flow.runner.subprocess.Popen", fake_popen)


def _config_values(command: list[str]) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command) if value == "--config"]


def _disabled_features(command: list[str]) -> list[str]:
    return [command[index + 1] for index, value in enumerate(command) if value == "--disable"]


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

    def on_start(command: list[str]) -> None:
        assert command[:2] == ["codex", "exec"]
        assert "--json" in command
        assert "--ignore-user-config" not in command
        assert "--ignore-rules" not in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == "gpt-5.4"
        assert _config_values(command) == ["model_reasoning_effort=xhigh"]
        assert _disabled_features(command) == list(DISABLED_EXTERNAL_TOOL_FEATURES)
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

    _install_fake_popen(monkeypatch, on_start)

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

    def on_start(command: list[str]) -> None:
        assert command[:2] == ["codex", "exec"]
        assert "--json" in command
        assert "--ignore-user-config" in command
        assert "--ignore-rules" in command
        assert "--model" in command
        assert command[command.index("--model") + 1] == "gpt-5.4"
        assert _config_values(command) == [
            "model_reasoning_effort=xhigh",
            "approval_policy=never",
        ]
        assert _disabled_features(command) == list(DISABLED_EXTERNAL_TOOL_FEATURES)
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

    _install_fake_popen(monkeypatch, on_start)

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

    def on_start(command: list[str]) -> None:
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

    _install_fake_popen(monkeypatch, on_start)

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
    state_home = tmp_path / "state"

    def on_start(command: list[str]) -> None:
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

    _install_fake_popen(monkeypatch, on_start)

    output = run_review(request, ProgressConfig(state_home=state_home))

    captured = capsys.readouterr()
    assert output.exists()
    assert output.read_text(encoding="utf-8").startswith("# Review Output")
    assert "codex-flow warning: review mode observed repository changes" in captured.err
    assert "file.txt" in captured.err
    assert not (repository / ".codex-flow").exists()
    trace_files = sorted((state_home / "runs").glob("*/review-traces/*.json"))
    assert len(trace_files) == 1
    trace = json.loads(trace_files[0].read_text(encoding="utf-8"))
    assert trace["event"] == "review_mode_repository_changed"
    assert trace["output_file"] == str(output.resolve())
    assert trace["changed_during_codex"] == ["file.txt"]
    assert trace["unexpected_changed_paths"] == ["file.txt"]


def test_run_review_emits_json_progress_and_external_log(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "file.txt").write_text("before\n", encoding="utf-8")
    request = tmp_path / "review.md"
    _write_review_request(request, repository)
    stream = io.StringIO()
    state_home = tmp_path / "state"

    def on_start(command: list[str]) -> None:
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

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text='{"type":"tool_call","tool_name":"rg"}\n{"type":"unknown"}\n',
    )

    output = run_review(
        request,
        ProgressConfig(
            mode="json",
            log_enabled=True,
            state_home=state_home,
            stream=stream,
        ),
    )

    assert output.exists()
    progress_events = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert {event["marker"] for event in progress_events} == {PROGRESS_MARKER}
    assert {event["workflow"] for event in progress_events} == {"review"}
    assert any(event.get("tool") == "rg" for event in progress_events)

    repo_key = repository_state_key(repository)
    log_files = sorted((state_home / "runs" / repo_key).glob("*.jsonl"))
    assert len(log_files) == 1
    log_content = log_files[0].read_text(encoding="utf-8")
    assert PROGRESS_MARKER in log_content
    assert "tool_call" not in log_content


def test_run_implementation_emits_plain_progress(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repo"
    repository.mkdir()
    (repository / "src").mkdir()
    (repository / "src/sync.py").write_text("print('ok')\n", encoding="utf-8")
    request = tmp_path / "design.md"
    _write_implementation_request(request, repository)
    stream = io.StringIO()

    def on_start(command: list[str]) -> None:
        output_index = command.index("--output-last-message") + 1
        Path(command[output_index]).write_text(
            json.dumps(
                {
                    "final_status": "SUCCESS",
                    "summary": "Implemented retry handling.",
                    "files_changed": ["src/sync.py"],
                    "verification_results": [],
                    "reasoning": [],
                    "open_issues": [],
                }
            ),
            encoding="utf-8",
        )

    _install_fake_popen(
        monkeypatch,
        on_start,
        stdout_text='{"type":"exec_command","cmd":"pytest tests"}\n',
    )

    output = run_implementation(
        request,
        ProgressConfig(mode="plain", log_enabled=False, stream=stream),
    )

    assert output.exists()
    progress = stream.getvalue()
    assert "codex-flow: Parsed implementation request" in progress
    assert "codex-flow: Codex ran tool: pytest" in progress
